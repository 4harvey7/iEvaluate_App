import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
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

    const {
      firstName: rawFirstName,
      lastName: rawLastName,
      email: rawEmail,
      universityId: rawUniversityId,
      roleName, deptId, verificationCode,
    } = await req.json()

    // ── Input hygiene ────────────────────────────────────────────────────────
    // Same rules as admin-create-user, from the same shared module, so a value
    // rejected on one admin screen cannot be accepted on the other.
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

    // 3. 🚫 Duplicate check BEFORE creating anything
    // Ahead of createUser on purpose: creating the auth account first and
    // hitting the duplicate at the user_info insert would leave an auth user
    // with no profile row, invisible in the admin lists but still holding that
    // email address.
    const conflict = await findIdentityConflict(supabaseAdmin, {
      firstName, lastName, email, universityId,
    })
    if (conflict) throw new Error(describeConflict(conflict, firstName, lastName))

    // 4. 🎲 Generate Temp Password
    const tempPassword = generateTempPassword()

    // 5. Create User in Auth
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email, password: tempPassword, email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName }
    })
    if (authError) {
      const taken = describeAuthEmailTaken(authError)
      throw taken ? new Error(taken) : authError
    }

    const userId = authData.user.id

    // 6. Profile + department rows. Any failure past this point has to undo the
    // auth account, otherwise that email is stranded.
    try {
      const { error: infoError } = await supabaseAdmin.from('user_info').insert({
        id: userId, first_name: firstName, last_name: lastName,
        email, university_id: universityId, account_status: 'approved'
      })
      if (infoError) throw infoError

      const { data: roleData, error: roleFetchError } = await supabaseAdmin
        .from('roles').select('id').eq('Roles', roleName).single()
      if (roleFetchError || !roleData) throw new Error('Invalid input: unknown role')

      const { error: deptError } = await supabaseAdmin.from('department_table').insert({
        user_id: userId,
        Department_name_ID: deptId,
        roles: roleData.id
      })
      if (deptError) throw deptError
    } catch (insertError) {
      await rollbackAuthUser(supabaseAdmin, userId)
      const dup = describeUniqueViolation(insertError)
      throw dup ? new Error(dup) : insertError
    }

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
    // Only known-safe messages are returned verbatim; anything else could carry
    // database or internal detail. Matches admin-create-user and
    // admin-update-role, which already filter this way.
    const safePrefixes = ['Unauthorized', 'Forbidden', 'Verification code expired', 'Invalid verification', 'Duplicate', 'Invalid input']
    const safeMessage = safePrefixes.some(p => error.message?.startsWith(p))
      ? error.message
      : 'Operation failed. Please try again.'
    return new Response(JSON.stringify({ error: safeMessage }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
  }
})
