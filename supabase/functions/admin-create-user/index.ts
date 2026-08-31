import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import {
  cleanEmail,
  cleanIdentity,
  describeAuthEmailTaken,
  describeConflict,
  describeUniqueViolation,
  findIdentityConflict,
  rollbackAuthUser,
  validateIdentityFormat,
} from '../_shared/identity_guard.ts'
import { createAdminClient } from '../_shared/admin_client.ts'

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

// ── L-6 FIX: Unbiased random password generation ─────────────────────────────
function generateTempPassword(): string {
  const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
  const result: string[] = []
  // Rejection sampling to eliminate modulo bias
  while (result.length < 8) {
    const buf = new Uint8Array(16)
    crypto.getRandomValues(buf)
    for (const byte of buf) {
      if (result.length >= 8) break
      const limit = Math.floor(256 / charset.length) * charset.length
      if (byte < limit) result.push(charset[byte % charset.length])
    }
  }
  return 'SAO-' + result.join('')
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()
    const {
      firstName: rawFirstName,
      lastName: rawLastName,
      email: rawEmail,
      universityId: rawUniversityId,
      roleName, address, verificationCode,
    } = await req.json()

    // ── Input hygiene ────────────────────────────────────────────────────────
    // Reject malformed values, then work only with the cleaned ones from here
    // down. Untrimmed input is how near-duplicates get in: " 12345" and "12345"
    // are two different rows to a plain equality check but the same ID number
    // to a human.
    const formatError = validateIdentityFormat({
      firstName: rawFirstName,
      lastName: rawLastName,
      email: rawEmail,
      universityId: rawUniversityId,
    })
    if (formatError) throw new Error(`Invalid input: ${formatError}`)

    const firstName = cleanIdentity(rawFirstName)
    const lastName = cleanIdentity(rawLastName)
    const email = cleanEmail(rawEmail)
    const universityId = cleanIdentity(rawUniversityId)

    // ── Identity & Role Verification ─────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    const { data: callerRole, error: roleError } = await supabaseAdmin
      .from('Sao_users').select('roles!inner(Roles)').eq('user_id', caller.id).single()
    if (roleError || (callerRole as any)?.roles?.Roles !== 'SAO_ADMIN') throw new Error('Forbidden')

    // ── OTP Verification — ONLY required for SAO_ADMIN (H-1 FIX) ────────────
    // Regular SAO_STAFF can be created without OTP — same pattern as admin-create-academic.
    if (roleName === 'SAO_ADMIN') {
      const { data: verifyData } = await supabaseAdmin
        .from('admin_verifications')
        .select('code, expires_at, attempts')
        .eq('admin_id', caller.id)
        // Admin codes only -- a SELF_DEACTIVATE code must not authorise this.
        .eq('purpose', 'ADMIN_ACTION')
        .single()

      if (!verifyData || new Date(verifyData.expires_at) < new Date()) {
        throw new Error('OTP expired. Please request a new verification code.')
      }

      if (verifyData.attempts >= MAX_OTP_ATTEMPTS) {
        await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
        throw new Error('Too many failed attempts. OTP invalidated. Please request a new code.')
      }

      if (verifyData.code !== await hashString(verificationCode)) {
        await supabaseAdmin.from('admin_verifications')
          .update({ attempts: verifyData.attempts + 1 }).eq('admin_id', caller.id)
        throw new Error(`Invalid OTP. ${MAX_OTP_ATTEMPTS - verifyData.attempts - 1} attempts remaining.`)
      }
    }

    // ── Duplicate check BEFORE creating anything ─────────────────────────────
    // Deliberately ahead of createUser. Creating the auth account first and
    // discovering the duplicate at the user_info insert leaves an auth user
    // with no profile row: invisible in every admin list, yet still holding
    // that email address forever.
    const conflict = await findIdentityConflict(supabaseAdmin, {
      firstName, lastName, email, universityId,
    })
    if (conflict) throw new Error(describeConflict(conflict, firstName, lastName))

    const tempPassword = generateTempPassword()

    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName }
    })
    if (authError) {
      // auth.users has its own unique email index, and a soft-deleted person
      // still occupies theirs.
      const taken = describeAuthEmailTaken(authError)
      throw taken ? new Error(taken) : authError
    }

    const userId = authData.user.id

    // From here on, any failure must undo the auth account. The unique indexes
    // on user_info are the real duplicate guarantee, and they fire here -- the
    // check above can still be beaten by two admins submitting at the same
    // instant.
    try {
      const { error: infoError } = await supabaseAdmin.from('user_info').insert({
        id: userId,
        first_name: firstName,
        last_name: lastName,
        email,
        university_id: universityId,
        address: address || 'SAO Office',
        account_status: 'approved'
      })
      if (infoError) throw infoError

      const { data: roleData, error: roleFetchError } = await supabaseAdmin
        .from('roles').select('id').eq('Roles', roleName).single()
      if (roleFetchError || !roleData) throw new Error('Invalid input: unknown role')

      const { error: saoError } = await supabaseAdmin
        .from('Sao_users').insert({ user_id: userId, role_id: roleData.id })
      if (saoError) throw saoError
    } catch (insertError) {
      await rollbackAuthUser(supabaseAdmin, userId)
      const dup = describeUniqueViolation(insertError)
      throw dup ? new Error(dup) : insertError
    }

    // ── H-2 FIX: Send magic-link invitation instead of plaintext password ────
    // Use Supabase's invite flow — sends a secure time-limited setup link.
    // The temp password is still created above as a Supabase auth requirement,
    // but we do NOT include it in the email.
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not configured')

    // Generate a password-reset link so the new user sets their own password on first login
    const { data: linkData } = await supabaseAdmin.auth.admin.generateLink({
      type: 'recovery',
      email,
    })
    const setupLink = linkData?.properties?.action_link ?? ''

    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: SENDER_EMAIL },
        to: [{ email }],
        subject: 'Welcome to SAO Personnel — Set Your Password',
        htmlContent: `
          <h3>Hello, ${firstName}!</h3>
          <p>Your SAO account as <b>${roleName}</b> has been created.</p>
          <p>Please click the button below to set your own password and activate your account.
             This link expires in 24 hours.</p>
          <p><a href="${setupLink}" style="background:#3b82f6;color:white;padding:12px 24px;
             border-radius:6px;text-decoration:none;font-weight:bold;">Set My Password</a></p>
          <p>If you did not expect this email, please contact the SAO office immediately.</p>
        `
      })
    })

    // Only clean up OTP if one was used (SAO_ADMIN creation)
    if (roleName === 'SAO_ADMIN') {
      await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
    }
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'SAO_USER_CREATED',
      metadata: { target: email, role: roleName }
    })

    return new Response(JSON.stringify({ message: 'SAO Personnel created' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    const safePrefixes = ['Unauthorized', 'Forbidden', 'OTP expired', 'Too many failed', 'Invalid OTP', 'BREVO_', 'Duplicate', 'Invalid input']
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
