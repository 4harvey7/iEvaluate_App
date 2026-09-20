// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'
import { isDepartmentHeadRole } from '../_shared/department_head_guard.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** How far the caller's authority over the target account reaches. */
type Authority = 'sao_admin' | 'dept_head'

/**
 * A PostgREST embed comes back as an object for a to-one relationship and as
 * an array when PostgREST cannot prove it is to-one. Both shapes already occur
 * in this project, so both are unwrapped rather than assumed.
 */
function embedded(value: unknown): any {
  return Array.isArray(value) ? value[0] : value
}

/**
 * Decides whether this caller may make this change, and reports which kind of
 * caller they are. Throws a 'Forbidden: ...' message otherwise.
 *
 * TWO KINDS OF CALLER
 *
 * SAO_ADMIN is unchanged: any allowed status, on any account. That is what the
 * User Management, Personnel Management and dashboard screens have always used.
 *
 * DEPARTMENT HEAD is new, and exists because of BUG-2026-TC-D08. The dept head
 * screen used to write user_info straight from the phone, which RLS refused --
 * the only UPDATE policy on that table is auth.uid() = id, so the update
 * matched zero rows, and the .select().single() after it turned that into
 * "PGRST116: The result contains 0 rows" in a red snackbar. Deactivation from
 * that screen had never worked once.
 *
 * The fix is deliberately NOT an RLS policy for heads. Letting the phone make
 * the write would have silenced the error while leaving the instructor able to
 * sign in: account_status is only the gate signIn() reads, and Supabase still
 * issues a session for an account that carries no Auth ban. It would also have
 * left audit_logs empty for the most consequential action in that module. So
 * the head is routed here, where the ban and the audit row already happen.
 *
 * A head's authority is narrow, and each limit is its own refusal so the head
 * is told which one they hit:
 *   - 'disabled' only. A head cannot approve, reject, suspend or reinstate.
 *   - Their own department only, resolved exactly the way the faculty roster
 *     resolves it, so "who I may deactivate" matches "who I can see".
 *   - Not themselves. A head deactivating their own account would lock the
 *     department out of its own dashboard, reversible only by the SAO office.
 *   - Not another head. Removing a head is an SAO decision.
 */
async function authoriseCaller(
  client: any,
  callerId: string,
  targetUserId: string,
  status: string,
): Promise<Authority> {
  // ── SAO admin? ────────────────────────────────────────────────────────────
  // maybeSingle, not single: a caller absent from Sao_users is now the normal
  // case rather than an error. single() throws on zero rows, which would refuse
  // every department head before their own check could run.
  const { data: adminRow } = await client
    .from('Sao_users')
    .select('roles!inner(Roles)')
    .eq('user_id', callerId)
    .maybeSingle()

  if (embedded(adminRow?.roles)?.Roles === 'SAO_ADMIN') return 'sao_admin'

  // ── Department head? ──────────────────────────────────────────────────────
  const { data: callerDept } = await client
    .from('department_table')
    .select('Department_name_ID, roles:roles(Roles)')
    .eq('user_id', callerId)
    .maybeSingle()

  if (!isDepartmentHeadRole(embedded(callerDept?.roles)?.Roles)) {
    // Neither an SAO admin nor a head. Same wording as before, so anything that
    // already handles this message keeps working.
    throw new Error('Forbidden: Admin access required')
  }

  const callerDeptId = callerDept?.Department_name_ID
  if (callerDeptId === null || callerDeptId === undefined) {
    throw new Error(
      'Forbidden: your account has no department on file. Please contact the SAO office.')
  }

  if (status !== 'disabled') {
    throw new Error('Forbidden: a department head may only deactivate an account.')
  }

  if (targetUserId === callerId) {
    throw new Error('Forbidden: you cannot deactivate your own account from here.')
  }

  // The same rule the faculty roster uses to build the list this button sits
  // on: instructor_departments, is_primary, matched against the head's own
  // Department_name_ID. Keeping the two identical is the point -- a head must
  // not be able to act on anyone the roster would not have shown them.
  const { data: memberRows, error: memberError } = await client
    .from('instructor_departments')
    .select('department_id')
    .eq('instructor_id', targetUserId)
    .eq('is_primary', true)
  if (memberError) throw memberError

  const sameDepartment = (memberRows ?? []).some(
    (row: any) => String(row.department_id) === String(callerDeptId),
  )
  if (!sameDepartment) {
    throw new Error('Forbidden: that account is not in your department.')
  }

  const { data: targetDept } = await client
    .from('department_table')
    .select('roles:roles(Roles)')
    .eq('user_id', targetUserId)
    .maybeSingle()

  if (isDepartmentHeadRole(embedded(targetDept?.roles)?.Roles)) {
    throw new Error('Forbidden: only the SAO office can deactivate a department head.')
  }

  return 'dept_head'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    // ── C-2 FIX: Authenticate the caller ────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    const { targetUserId, status = 'approved' } = await req.json()

    // Read the body BEFORE authorising. Who may make this call depends on which
    // account is being changed and to what, not only on who is asking.
    if (!targetUserId || typeof targetUserId !== 'string') {
      throw new Error('Invalid input: missing target user')
    }

    // Validate status value to prevent arbitrary string injection.
    //
    // 'disabled' was MISSING, and it is the only value the two admin screens
    // ever send when deactivating someone (user_management_screen.dart and
    // personnel_management_screen.dart both compute
    // `currentStatus == 'approved' ? 'disabled' : 'approved'`). So every
    // deactivation threw `Invalid status value: disabled` and showed the raw
    // error in a red snackbar. Deactivation had never once worked -- all 17
    // accounts sat at 'approved' because no other value could ever be written.
    const allowedStatuses = ['approved', 'rejected', 'suspended', 'pending', 'disabled']
    if (!allowedStatuses.includes(status)) {
      throw new Error(`Invalid status value: ${status}`)
    }

    // ── C-2 FIX: Verify the caller is allowed to make THIS change ───────────
    const authority = await authoriseCaller(
      supabaseAdmin,
      caller.id,
      targetUserId,
      status,
    )

    // Update status
    const { data: userData, error: updateError } = await supabaseAdmin
      .from('user_info')
      .update({ account_status: status })
      .eq('id', targetUserId)
      .select('email, first_name, last_name')
      .single()

    if (updateError) throw updateError

    // ── Keep Supabase Auth in step with account_status ──────────────────────
    //
    // account_status alone is only an application-layer gate: signIn() reads it
    // and refuses, but the row is not what actually stops a session being
    // issued. Anything holding the anon key can call signInWithPassword
    // directly. Banning at the auth layer is what genuinely revokes access.
    //
    // The reverse direction is the bug that mattered: delete-user bans for
    // 87600h (10 years) and NOTHING anywhere cleared it. Reactivating a deleted
    // user set account_status back to 'approved', the admin screen looked
    // correct, and login still failed -- with "Incorrect ID or password",
    // because a banned user is indistinguishable from a wrong password at the
    // client. There is a live victim: af6f7dda-ed6e-489b-a4c3-edaf23e2bebb,
    // banned until 2036, who has real evaluation data.
    const BAN_STATUSES = ['disabled', 'rejected', 'suspended']
    let authAction: 'banned' | 'unbanned' | 'unchanged' = 'unchanged'

    if (BAN_STATUSES.includes(status)) {
      const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(
        targetUserId,
        { ban_duration: '87600h' },
      )
      if (banError) {
        throw new Error(
          'Status saved but the account could not be locked in Auth. Please retry.',
        )
      }
      authAction = 'banned'
    } else if (status === 'approved') {
      // 'none' is how Supabase clears an existing ban. Safe to send even when
      // the user was never banned, which makes reactivation idempotent.
      const { error: unbanError } = await supabaseAdmin.auth.admin.updateUserById(
        targetUserId,
        { ban_duration: 'none' },
      )
      if (unbanError) {
        throw new Error(
          'Status saved but the account could not be unlocked in Auth. Please retry.',
        )
      }
      authAction = 'unbanned'
    }
    // 'pending' deliberately leaves Auth alone: a fresh signup is already
    // blocked by the account_status check and has never been banned.

    // ── Audit log ────────────────────────────────────────────────────────────
    // auth_action is recorded because "status changed to approved" and "the auth
    // ban was actually cleared" are two different facts, and it was the gap
    // between them that locked a real user out for ten years.
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'USER_STATUS_CHANGED',
      // caller_role travels with the entry because this function now serves two
      // kinds of caller. "The SAO office disabled this account" and "the
      // department head did" are different facts, and the Security Audit Logs
      // screen is where that has to be answerable.
      metadata: {
        target_user: targetUserId,
        new_status: status,
        auth_action: authAction,
        caller_role: authority,
      },
    })

    const isApproved = status === 'approved'

    // 📧 Notify User via Brevo
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not configured')

    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: SENDER_EMAIL },
        to: [{ email: userData.email }],
        subject: isApproved ? 'Account Approved!' : 'Account Status Updated',
        htmlContent: `
          <h3>Hello, ${userData.first_name}!</h3>
          <p>Your account status has been updated to: <b>${status.toUpperCase()}</b>.</p>
          ${isApproved
            ? '<p>Your registration has been approved. You can now log in to the iEvaluate app.</p>'
            : '<p>Your account has been deactivated/disabled by the administrator. If you believe this is an error, please contact the SAO office.</p>'}
          <p>Best regards,<br>SAO Management Team</p>
        `
      })
    })

    return new Response(JSON.stringify({ message: `User ${status} and notified` }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    // Return safe error messages only — never expose internal details.
    // The two "Status saved but..." messages are listed on purpose: they are the
    // difference between an admin knowing to retry and an admin believing a
    // reactivation worked when the account is still locked.
    const safeMessage = [
      'Unauthorized',
      // Every 'Forbidden:' message raised here names one specific limit the
      // caller hit -- wrong status, wrong department, their own account, a
      // fellow head. Flattening those into "Operation failed" would leave a
      // department head guessing at a rule they cannot see. None of them carry
      // internal detail.
      'Forbidden',
      'Invalid input',
      'Invalid status value',
      'Status saved but the account could not be locked in Auth.',
      'Status saved but the account could not be unlocked in Auth.',
    ].some(
      m => error.message?.startsWith(m)
    ) ? error.message : 'Operation failed. Please try again.'

    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
