import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    const { firstName, lastName, email, universityId, roleName, address, verificationCode } = await req.json()

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

    const tempPassword = generateTempPassword()

    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName }
    })
    if (authError) throw authError

    const userId = authData.user.id
    await supabaseAdmin.from('user_info').insert({
      id: userId,
      first_name: firstName,
      last_name: lastName,
      email,
      university_id: universityId,
      address: address || 'SAO Office',
      account_status: 'approved'
    })
    const { data: roleData } = await supabaseAdmin.from('roles').select('id').eq('Roles', roleName).single()
    await supabaseAdmin.from('Sao_users').insert({ user_id: userId, role_id: roleData!.id })

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
    const safePrefixes = ['Unauthorized', 'Forbidden', 'OTP expired', 'Too many failed', 'Invalid OTP', 'BREVO_']
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
