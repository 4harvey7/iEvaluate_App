import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 🛡️ SHA-256 Hashing for secure storage
async function hashString(str: string) {
  const encoder = new TextEncoder()
  const data = encoder.encode(str)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

// ── H-1 FIX: OTP attempt limit ────────────────────────────────────────────────
const MAX_OTP_ATTEMPTS = 5

// What a code is allowed to authorise. Stored on the row and re-checked by
// whichever function consumes it, so a code emailed to approve a role change
// cannot also unlock account deactivation -- the recipient was told what they
// were approving, and that has to stay true.
//   ADMIN_ACTION     SAO admin mutations (role change, user creation)
//   SELF_DEACTIVATE  the account owner deactivating their own account
const PURPOSES = ['ADMIN_ACTION', 'SELF_DEACTIVATE']

const COPY = {
  ADMIN_ACTION: {
    subject: 'Verification Code: Admin Action',
    heading: 'Secure Authorization',
    blurb: 'Use this code to authorise the administrative change you just started.',
  },
  SELF_DEACTIVATE: {
    subject: 'Verification Code: Deactivate Your Account',
    heading: 'Confirm Account Deactivation',
    blurb:
      'Use this code to deactivate your iEvaluate account. Once deactivated you ' +
      'will not be able to sign in until an SAO administrator reactivates you.',
  },
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    const body = await req.json().catch(() => ({}))
    const purpose = PURPOSES.includes(body?.purpose) ? body.purpose : 'ADMIN_ACTION'

    // ── IDENTITY VERIFICATION ─────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── 🛡️ CRITICAL ROLE CHECK ────────────────────────────────────────────────
    // Only admin-purpose codes require the admin role. A SELF_DEACTIVATE code is
    // requested by ordinary instructors and gatherers, is sent to the caller's
    // own inbox, and authorises nothing beyond deactivating the caller's own
    // account -- delete-user still enforces self-only separately.
    if (purpose === 'ADMIN_ACTION') {
      const { data: adminCheck, error: adminError } = await supabaseAdmin
        .from('Sao_users')
        .select('roles!inner(Roles)')
        .eq('user_id', caller.id)
        .single()

      if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
        throw new Error('Forbidden: Admin access required')
      }
    }

    // The recipient comes from the authenticated session, never from the request
    // body. Every caller was already sending its own address, so this changes no
    // behaviour -- but it means a compromised client cannot aim a live code at
    // an inbox it does not own.
    const recipient = caller.email
    if (!recipient) throw new Error('Forbidden: this account has no email address on file')

    // ── 🛑 RATE LIMITING (1 request per 60s) ─────────────────────────────────
    const { data: existing } = await supabaseAdmin
      .from('admin_verifications')
      .select('expires_at, attempts')
      .eq('admin_id', caller.id)
      .single()

    if (existing) {
      const lastReq = new Date(new Date(existing.expires_at).getTime() - 10 * 60000)
      const diff = (Date.now() - lastReq.getTime()) / 1000
      if (diff < 60) throw new Error(`Rate limit: Wait ${Math.ceil(60 - diff)}s before requesting a new code.`)
    }

    // ── 🎲 CRYPTO-SECURE OTP ──────────────────────────────────────────────────
    const otpBuffer = new Uint32Array(1)
    crypto.getRandomValues(otpBuffer)
    const code = (otpBuffer[0] % 900000 + 100000).toString()

    // ── 🔐 HASH BEFORE STORAGE ────────────────────────────────────────────────
    // admin_id is still the primary key, so this overwrites whatever code the
    // user already had, including one of a different purpose. That is
    // intentional: the old code stops working rather than two live codes
    // coexisting.
    const hashedCode = await hashString(code)
    await supabaseAdmin.from('admin_verifications').upsert({
      admin_id: caller.id,
      code: hashedCode,
      purpose,
      attempts: 0,   // Reset attempt counter on each new OTP
      expires_at: new Date(Date.now() + 10 * 60000).toISOString()
    })

    // ── 📝 AUDIT LOG ──────────────────────────────────────────────────────────
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'OTP_REQUESTED',
      metadata: { target: recipient, method: '2FA_EMAIL', purpose }
    })

    // ── 📧 SECURE DELIVERY ────────────────────────────────────────────────────
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')

    if (!BREVO_KEY) throw new Error('BREVO_API_KEY is not set in Supabase secrets')
    // L-2 FIX: No hardcoded fallback — throw if not configured
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not set in Supabase secrets')

    const copy = COPY[purpose]
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_KEY,
        'content-type': 'application/json',
        'accept': 'application/json'
      },
      body: JSON.stringify({
        sender: { name: 'SAO Secure System', email: SENDER_EMAIL },
        to: [{ email: recipient }],
        subject: copy.subject,
        htmlContent: `
          <div style="font-family: sans-serif; padding: 20px;">
            <h2>${copy.heading}</h2>
            <p>${copy.blurb}</p>
            <h1 style="color: #3b82f6; letter-spacing: 5px;">${code}</h1>
            <p>This code will expire in <b>10 minutes</b>.</p>
            <p>You have a maximum of <b>${MAX_OTP_ATTEMPTS} attempts</b> before the code is invalidated.</p>
            <p style="color: #999; font-size: 12px;">If you did not request this code, please secure your account immediately.</p>
          </div>
        `
      })
    })

    const resData = await res.json()
    if (!res.ok) {
      console.error('Brevo API Error:', resData)
      throw new Error(`Email delivery failed. Please contact support.`)
    }

    return new Response(JSON.stringify({ message: 'Secure code sent' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    const safePrefixes = ['Unauthorized', 'Forbidden', 'Rate limit', 'BREVO_', 'Email delivery failed']
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
