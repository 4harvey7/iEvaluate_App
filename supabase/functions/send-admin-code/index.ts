import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { email } = await req.json()

    // ── IDENTITY VERIFICATION ─────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── 🛡️ CRITICAL ROLE CHECK ────────────────────────────────────────────────
    const { data: adminCheck, error: adminError } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .single()

    if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

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
    const hashedCode = await hashString(code)
    await supabaseAdmin.from('admin_verifications').upsert({
      admin_id: caller.id,
      code: hashedCode,
      attempts: 0,   // Reset attempt counter on each new OTP
      expires_at: new Date(Date.now() + 10 * 60000).toISOString()
    })

    // ── 📝 AUDIT LOG ──────────────────────────────────────────────────────────
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'OTP_REQUESTED',
      metadata: { target: email, method: '2FA_EMAIL' }
    })

    // ── 📧 SECURE DELIVERY ────────────────────────────────────────────────────
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')

    if (!BREVO_KEY) throw new Error('BREVO_API_KEY is not set in Supabase secrets')
    // L-2 FIX: No hardcoded fallback — throw if not configured
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not set in Supabase secrets')

    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_KEY,
        'content-type': 'application/json',
        'accept': 'application/json'
      },
      body: JSON.stringify({
        sender: { name: 'SAO Secure System', email: SENDER_EMAIL },
        to: [{ email: email }],
        subject: 'Verification Code: Admin Action',
        htmlContent: `
          <div style="font-family: sans-serif; padding: 20px;">
            <h2>Secure Authorization</h2>
            <p>Your verification code is:</p>
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
