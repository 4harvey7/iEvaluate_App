import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import {
  cleanIdentity,
  describeConflict,
  describeUniqueViolation,
  findIdentityConflict,
  validateIdentityFormat,
} from '../_shared/identity_guard.ts'
import { createAdminClient } from '../_shared/admin_client.ts'
import {
  assertDepartmentHeadVacant,
  HEAD_CONFLICT_PREFIX,
} from '../_shared/department_head_guard.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function hashString(str: string) {
  const encoder = new TextEncoder()
  const data = encoder.encode(str)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('')
}

// ── H-1 FIX: OTP attempt limit ────────────────────────────────────────────────
const MAX_OTP_ATTEMPTS = 5

/**
 * 'Full-Time' / 'Part-Time' when the role name itself states the employment,
 * otherwise null meaning "leave whatever is on record alone".
 *
 * Casing matches what is already in user_info.employment_status.
 */
function employmentForRole(roleName: unknown): string | null {
  const role = String(roleName ?? '').trim().toUpperCase()
  if (role === 'FULL-TIME' || role === 'FULL_TIME') return 'Full-Time'
  if (role === 'PART-TIME' || role === 'PART_TIME') return 'Part-Time'
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()
    const {
      targetUserId,
      firstName: rawFirstName,
      lastName: rawLastName,
      roleId, roleName, verificationCode, isAcademic, isPromotion,
      deptId,
    } = await req.json()

    if (!targetUserId) throw new Error('Invalid input: missing target user')

    // Renaming is the other way a duplicate gets created: the account was
    // unique when it was made, then someone edits the name to match an existing
    // person. Same rules as the create endpoints, from the same module.
    const formatError = validateIdentityFormat({
      firstName: rawFirstName,
      lastName: rawLastName,
    })
    if (formatError) throw new Error(`Invalid input: ${formatError}`)

    const firstName = cleanIdentity(rawFirstName)
    const lastName = cleanIdentity(rawLastName)

    // ── Authenticate caller ───────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── H-7 FIX: Verify caller is SAO_ADMIN before ANY operation ─────────────
    const { data: adminCheck, error: adminError } = await supabaseAdmin
      .from('Sao_users').select('roles!inner(Roles)').eq('user_id', caller.id).single()
    if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

    // ── One head per department ───────────────────────────────────────────────
    // Runs before the OTP block on purpose: the admin should learn the chair is
    // taken before a code is emailed and typed, and before that code is spent.
    //
    // The role NAME is re-read from roleId rather than trusted from the body.
    // roleId is what actually gets written, so a request carrying roleName
    // 'FULL-TIME' with a department-head roleId would otherwise walk straight
    // past this check. The trigger department_table_one_head (migration
    // 20240130000016) would still stop it -- but with a message this function
    // is not expecting at a point where the user_info update has already been
    // applied.
    if (isAcademic) {
      const { data: roleRow } = await supabaseAdmin
        .from('roles').select('Roles').eq('id', roleId).limit(1)
      const effectiveRoleName =
        roleRow && roleRow.length > 0 ? roleRow[0].Roles : roleName

      // The department dropdown is optional in the dialog. When it is not sent,
      // the role still lands on whatever department the person is already in,
      // and that department is the one whose chair has to be free.
      let targetDeptId = deptId
      if (targetDeptId == null) {
        const { data: currentDept } = await supabaseAdmin
          .from('department_table')
          .select('Department_name_ID')
          .eq('user_id', targetUserId)
          .limit(1)
        targetDeptId = currentDept && currentDept.length > 0
          ? currentDept[0].Department_name_ID
          : null
      }

      await assertDepartmentHeadVacant(supabaseAdmin, {
        roleName: effectiveRoleName,
        deptId: targetDeptId,
        // Re-saving the sitting head must not report them as their own blocker.
        excludeUserId: targetUserId,
      })
    }

    // ── OTP Protection Logic ──────────────────────────────────────────────────
    // OTP is ONLY required when isPromotion=true (i.e., actual role escalation).
    // Regular name edits or keeping the same role never need OTP.
    const needsOTP = isPromotion === true

    if (needsOTP) {
      const { data: verifyData } = await supabaseAdmin
        .from('admin_verifications')
        .select('code, expires_at, attempts')
        .eq('admin_id', caller.id)
        // Admin codes only -- a SELF_DEACTIVATE code must not authorise this.
        .eq('purpose', 'ADMIN_ACTION')
        .single()

      if (!verifyData || new Date(verifyData.expires_at) < new Date()) {
        throw new Error('Verification code expired. Please request a new one.')
      }

      // H-1 FIX: Enforce attempt limit
      if (verifyData.attempts >= MAX_OTP_ATTEMPTS) {
        await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
        throw new Error('Too many failed attempts. OTP invalidated. Please request a new code.')
      }

      const inputHash = await hashString(verificationCode)
      if (verifyData.code !== inputHash) {
        await supabaseAdmin.from('admin_verifications')
          .update({ attempts: verifyData.attempts + 1 }).eq('admin_id', caller.id)
        throw new Error(`Invalid verification code. ${MAX_OTP_ATTEMPTS - verifyData.attempts - 1} attempts remaining.`)
      }
      await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
    }

    // ── Duplicate name check ──────────────────────────────────────────────────
    // excludeUserId is this account, so saving the dialog without changing the
    // name does not report the person as a duplicate of themselves.
    const conflict = await findIdentityConflict(supabaseAdmin, {
      firstName, lastName, excludeUserId: targetUserId,
    })
    if (conflict) throw new Error(describeConflict(conflict, firstName, lastName))

    // ── Perform Updates ───────────────────────────────────────────────────────
    const { error: updateError } = await supabaseAdmin.from('user_info').update({
      first_name: firstName,
      last_name: lastName
    }).eq('id', targetUserId)
    if (updateError) {
      const dup = describeUniqueViolation(updateError)
      throw dup ? new Error(dup) : updateError
    }

    if (isAcademic) {
      // The Department dropdown in "Edit Academic Profile" used to be
      // decorative: the client never sent a department and this function only
      // wrote `roles`, so the control looked like it saved and silently did not.
      const deptUpdate: Record<string, unknown> = { roles: roleId }
      if (deptId != null) deptUpdate.Department_name_ID = deptId

      const { error: deptError } = await supabaseAdmin
        .from('department_table')
        .update(deptUpdate)
        .eq('user_id', targetUserId)
      if (deptError) throw deptError

      // department_table and instructor_departments both record the primary
      // department and must move together. The dean roster reads
      // instructor_departments while the profile reads department_table, so
      // updating one alone makes the two screens disagree about where someone
      // works.
      if (deptId != null) {
        // .limit(1) rather than .maybeSingle(): maybeSingle throws when it
        // finds more than one row, and duplicate primaries are exactly the
        // state migration 10's unique index exists to clean up.
        const { data: primaries, error: readError } = await supabaseAdmin
          .from('instructor_departments')
          .select('id')
          .eq('instructor_id', targetUserId)
          .eq('is_primary', true)
          .limit(1)
        if (readError) throw readError

        const existingPrimary = primaries && primaries.length > 0 ? primaries[0] : null

        const primaryWrite = existingPrimary
          ? await supabaseAdmin
              .from('instructor_departments')
              .update({ department_id: deptId })
              .eq('id', existingPrimary.id)
          : await supabaseAdmin
              .from('instructor_departments')
              .insert({ instructor_id: targetUserId, department_id: deptId, is_primary: true })

        if (primaryWrite.error) {
          // 23505 on (instructor_id, department_id) means this person is
          // already linked to that department as a secondary. Say so, rather
          // than leaking a Postgres error to the dialog.
          if ((primaryWrite.error as any).code === '23505') {
            throw new Error('Duplicate: this instructor is already assigned to that department. Remove the secondary assignment first.')
          }
          throw primaryWrite.error
        }
      }
    } else {
      const { error: saoError } = await supabaseAdmin
        .from('Sao_users').update({ role_id: roleId }).eq('user_id', targetUserId)
      if (saoError) throw saoError
    }

    // Employment status is written ONLY when the new role states it.
    // FULL-TIME and PART-TIME are the two instructor roles and each names its
    // own employment; DEPARTMENT_HEAD, DEAN and the SAO roles do not, so
    // overwriting theirs would be a guess. Same rule the signup screen applies.
    //
    // This matters beyond tidiness: employment_status is what gates the
    // "Assign Second Department" action, so a stale value hands out -- or
    // withholds -- an ability the role no longer matches.
    const derivedEmployment = employmentForRole(roleName)
    if (derivedEmployment) {
      const { error: empError } = await supabaseAdmin
        .from('user_info')
        .update({ employment_status: derivedEmployment })
        .eq('id', targetUserId)
      if (empError) throw empError
    }

    // Department name for the notification email, if it moved.
    let newDeptName: string | null = null
    if (isAcademic && deptId != null) {
      const { data: deptRow } = await supabaseAdmin
        .from('department_name').select('d_name').eq('id', deptId).limit(1)
      newDeptName = deptRow && deptRow.length > 0 ? deptRow[0].d_name : null
    }

    // ── Notify User ───────────────────────────────────────────────────────────
    const { data: userData } = await supabaseAdmin
      .from('user_info').select('email, account_status').eq('id', targetUserId).single()

    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not configured')

    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: SENDER_EMAIL },
        to: [{ email: userData!.email }],
        subject: 'Account Information Updated',
        htmlContent: `
          <h3>Hello, ${firstName}!</h3>
          <p>Your account information has been updated by an administrator.</p>
          <p><b>Updated Details:</b></p>
          <ul>
            <li><b>Name:</b> ${firstName} ${lastName}</li>
            <li><b>Role:</b> ${roleName}</li>
            ${newDeptName ? `<li><b>Department:</b> ${newDeptName}</li>` : ''}
            ${derivedEmployment ? `<li><b>Employment:</b> ${derivedEmployment}</li>` : ''}
            <li><b>Status:</b> ${userData!.account_status.toUpperCase()}</li>
          </ul>
          <p>If you did not request these changes or believe this is an error, please contact the SAO office immediately.</p>
          <p>Best regards,<br>SAO Management Team</p>
        `
      })
    })

    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'ROLE_UPDATED',
      metadata: {
        target: targetUserId,
        new_role: roleName,
        new_dept: deptId ?? null,
        new_employment: derivedEmployment ?? null,
      }
    })

    return new Response(JSON.stringify({ message: 'Update successful' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    // HEAD_CONFLICT_PREFIX covers both sources of that message: the pre-flight
    // check above, and the trigger's own exception if the race is lost between
    // the check and the update. Both start with the same words.
    const safePrefixes = ['Unauthorized', 'Forbidden', 'Verification code expired', 'Too many failed', 'Invalid verification', 'BREVO_', 'Duplicate', 'Invalid input', HEAD_CONFLICT_PREFIX]
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
