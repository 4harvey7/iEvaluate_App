import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  cleanIdentity,
  describeConflict,
  describeUniqueViolation,
  findIdentityConflict,
  validateIdentityFormat,
} from '../_shared/identity_guard.ts'

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    const {
      targetUserId,
      firstName: rawFirstName,
      lastName: rawLastName,
      roleId, roleName, verificationCode, isAcademic, isPromotion,
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

    // ── OTP Protection Logic ──────────────────────────────────────────────────
    // OTP is ONLY required when isPromotion=true (i.e., actual role escalation).
    // Regular name edits or keeping the same role never need OTP.
    const needsOTP = isPromotion === true

    if (needsOTP) {
      const { data: verifyData } = await supabaseAdmin
        .from('admin_verifications')
        .select('code, expires_at, attempts')
        .eq('admin_id', caller.id)
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
      await supabaseAdmin.from('department_table').update({ roles: roleId }).eq('user_id', targetUserId)
    } else {
      await supabaseAdmin.from('Sao_users').update({ role_id: roleId }).eq('user_id', targetUserId)
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
      metadata: { target: targetUserId, new_role: roleName }
    })

    return new Response(JSON.stringify({ message: 'Update successful' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    const safePrefixes = ['Unauthorized', 'Forbidden', 'Verification code expired', 'Too many failed', 'Invalid verification', 'BREVO_', 'Duplicate', 'Invalid input']
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
