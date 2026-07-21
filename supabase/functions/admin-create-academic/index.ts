import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 🛡️ Helper: SHA-256 Hashing
async function hashString(str: string) {
  const encoder = new TextEncoder()
  const data = encoder.encode(str)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('')
}

// 🎲 Helper: Secure Random Password Generator
function generateTempPassword() {
  const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
  let retVal = "SAO-"
  const length = 8
  const randomValues = new Uint32Array(length)
  crypto.getRandomValues(randomValues)
  for (let i = 0; i < length; ++i) {
    retVal += charset.charAt(randomValues[i] % charset.length)
  }
  return retVal
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { firstName, lastName, email, universityId, roleName, deptId, verificationCode } = await req.json()

    // 1. Identity & Role Verification (Is caller SAO_ADMIN?)
    const authHeader = req.headers.get('Authorization')
    const { data: { user: caller } } = await supabaseAdmin.auth.getUser(authHeader!.replace('Bearer ', ''))

    const { data: callerRole } = await supabaseAdmin.from('Sao_users').select('roles!inner(Roles)').eq('user_id', caller!.id).single()
    if ((callerRole as any)?.roles?.Roles !== 'SAO_ADMIN') throw new Error("Forbidden")

    // 2. 🛡️ OTP CHECK (Required ONLY for Department Head)
    if (roleName === 'DEPARTMENT_HEAD') {
      const { data: verifyData } = await supabaseAdmin.from('admin_verifications').select('code, expires_at, attempts').eq('admin_id', caller!.id).single()
      if (!verifyData || new Date(verifyData.expires_at) < new Date()) throw new Error("Verification code expired.")

      const inputHash = await hashString(verificationCode)
      if (verifyData.code !== inputHash) {
        await supabaseAdmin.from('admin_verifications').update({ attempts: verifyData.attempts + 1 }).eq('admin_id', caller!.id)
        throw new Error("Invalid verification code.")
      }
    }

    // 3. 🎲 Generate Temp Password
    const tempPassword = generateTempPassword()

    // 4. Create User in Auth
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email, password: tempPassword, email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName }
    })
    if (authError) throw authError

    const userId = authData.user.id

    // 5. Update user_info
    await supabaseAdmin.from('user_info').insert({
      id: userId, first_name: firstName, last_name: lastName,
      email, university_id: universityId, account_status: 'approved'
    })

    // 6. Update department_table
    const { data: roleData } = await supabaseAdmin.from('roles').select('id').eq('Roles', roleName).single()
    await supabaseAdmin.from('department_table').insert({
      user_id: userId,
      Department_name_ID: deptId,
      roles: roleData!.id
    })

    // 7. 📧 Notify User via Brevo
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: Deno.env.get('BREVO_SENDER_EMAIL') },
        to: [{ email }],
        subject: 'Welcome! Your Academic Account is Ready',
        htmlContent: `
          <h3>Hello, ${firstName}!</h3>
          <p>Your account as <b>${roleName}</b> has been created.</p>
          <p>Temporary Password: <b>${tempPassword}</b></p>
          <p>Please change your password after logging in.</p>
        `
      })
    })

    // 8. 📝 Audit & Cleanup
    if (roleName === 'DEPARTMENT_HEAD') await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller!.id)
    await supabaseAdmin.from('audit_logs').insert({ user_id: caller!.id, action: 'ACADEMIC_USER_CREATED', metadata: { target: email, role: roleName } })

    return new Response(JSON.stringify({ message: 'Academic user created' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
  }
})
