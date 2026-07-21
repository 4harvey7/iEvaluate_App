import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { email } = await req.json()

    // 0. IDENTITY VERIFICATION
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // 1. 🛡️ CRITICAL ROLE CHECK: Only SAO Admins can request OTPs for admin actions
    const { data: adminCheck, error: adminError } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .single()

    if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
       throw new Error('Forbidden: Admin access required')
    }

    // 2. 🛑 RATE LIMITING (1 request per 60s)
    const { data: existing } = await supabaseAdmin
      .from('admin_verifications')
      .select('expires_at')
      .eq('admin_id', caller.id)
      .single()

    if (existing) {
      const lastReq = new Date(new Date(existing.expires_at).getTime() - 10 * 60000)
      const diff = (Date.now() - lastReq.getTime()) / 1000
      if (diff < 60) throw new Error(`Rate limit: Wait ${Math.ceil(60 - diff)}s.`)
    }

    // 3. 🎲 CRYPTO-SECURE OTP
    const otpBuffer = new Uint32Array(1)
    crypto.getRandomValues(otpBuffer)
    const code = (otpBuffer[0] % 900000 + 100000).toString()

    // 4. 🔐 HASH BEFORE STORAGE
    const hashedCode = await hashString(code)
    await supabaseAdmin.from('admin_verifications').upsert({
      admin_id: caller.id,
      code: hashedCode,
      attempts: 0,
      expires_at: new Date(Date.now() + 10 * 60000).toISOString()
    })

    // 5. 📝 AUDIT LOG
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'OTP_REQUESTED',
      metadata: { target: email, method: '2FA_EMAIL' }
    })

    // 6. 📧 SECURE DELIVERY
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL') || 'rodzharveydlicayan@gmail.com'

    if (!BREVO_KEY) throw new Error('BREVO_API_KEY is not set in Supabase secrets')

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
            <p>This code will expire in 10 minutes.</p>
          </div>
        `
      })
    })

    const resData = await res.json()
    if (!res.ok) {
      console.error('Brevo API Error:', resData)
      throw new Error(`Email failed: ${resData.message || res.statusText}`)
    }

    return new Response(JSON.stringify({ message: 'Secure code sent' }), {

      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
