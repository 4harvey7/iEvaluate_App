import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
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

function generateTempPassword() {
  const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
  let retVal = "SAO-"
  const randomValues = new Uint32Array(8)
  crypto.getRandomValues(randomValues)
  for (let i = 0; i < 8; ++i) { retVal += charset.charAt(randomValues[i] % charset.length) }
  return retVal
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
    const { firstName, lastName, email, universityId, roleName, address, verificationCode } = await req.json()

    // Identity & Role Verification
    const authHeader = req.headers.get('Authorization')
    const { data: { user: caller } } = await supabaseAdmin.auth.getUser(authHeader!.replace('Bearer ', ''))
    const { data: callerRole } = await supabaseAdmin.from('Sao_users').select('roles!inner(Roles)').eq('user_id', caller!.id).single()
    if ((callerRole as any)?.roles?.Roles !== 'SAO_ADMIN') throw new Error("Forbidden")

    // OTP Verification (Mandatory for SAO Admin/Staff changes)
    const { data: verifyData } = await supabaseAdmin.from('admin_verifications').select('code, expires_at, attempts').eq('admin_id', caller!.id).single()
    if (!verifyData || new Date(verifyData.expires_at) < new Date()) throw new Error("OTP expired")

    if (verifyData.code !== await hashString(verificationCode)) {
      await supabaseAdmin.from('admin_verifications').update({ attempts: verifyData.attempts + 1 }).eq('admin_id', caller!.id)
      throw new Error("Invalid OTP")
    }

    const tempPassword = generateTempPassword()

    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email, password: tempPassword, email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName }
    })
    if (authError) throw authError

    const userId = authData.user.id
    await supabaseAdmin.from('user_info').insert({ id: userId, first_name: firstName, last_name: lastName, email, university_id: universityId, address: address || 'SAO Office', account_status: 'approved' })
    const { data: roleData } = await supabaseAdmin.from('roles').select('id').eq('Roles', roleName).single()
    await supabaseAdmin.from('Sao_users').insert({ user_id: userId, role_id: roleData!.id })

    // 📧 Notify
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: Deno.env.get('BREVO_SENDER_EMAIL') },
        to: [{ email }],
        subject: 'Welcome to SAO Personnel',
        htmlContent: `<h3>Hello, ${firstName}!</h3><p>Your SAO account as <b>${roleName}</b> has been created.</p><p>Temp Password: <b>${tempPassword}</b></p>`
      })
    })

    await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller!.id)
    await supabaseAdmin.from('audit_logs').insert({ user_id: caller!.id, action: 'SAO_USER_CREATED', metadata: { target: email, role: roleName } })

    return new Response(JSON.stringify({ message: 'SAO Personnel created' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
  }
})
