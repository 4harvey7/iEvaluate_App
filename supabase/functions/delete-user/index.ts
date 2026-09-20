import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Matches the limit send-admin-code tells the user about in the email.
const MAX_OTP_ATTEMPTS = 5

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
    const supabaseAdmin = createAdminClient()

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    const { userId, verificationCode } = await req.json()

    // Safety: Users can only delete themselves, unless it's a SAO_ADMIN (optional, for now just self-delete)
    const isSelf = caller.id === userId
    if (!isSelf) {
        // Check if caller is admin
        const { data: adminCheck } = await supabaseAdmin
          .from('Sao_users')
          .select('roles!inner(Roles)')
          .eq('user_id', caller.id)
          .single()

        if ((adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
            throw new Error('Forbidden: You can only delete your own account.')
        }
    }

    // ── 0. EMAILED CODE, CHECKED HERE ────────────────────────────────────────
    // Enforced server-side on purpose. This is a public HTTP endpoint: anyone
    // holding the publishable key and a valid session could call it directly
    // and skip whatever the app's dialog asked for, so a client-side check
    // would be decoration. Self-deactivation only -- an SAO admin acting on
    // someone else already passed the role check above, and has no code of
    // their own for this.
    //
    // The purpose filter matters: without it, a code emailed to authorise a
    // role change would also unlock account deactivation, which is not what
    // its recipient was told they were approving.
    if (isSelf) {
      if (!verificationCode) {
        throw new Error('Verification code required to deactivate your account.')
      }

      const { data: verifyData } = await supabaseAdmin
        .from('admin_verifications')
        .select('code, expires_at, attempts, purpose')
        .eq('admin_id', caller.id)
        .eq('purpose', 'SELF_DEACTIVATE')
        .single()

      if (!verifyData || new Date(verifyData.expires_at) < new Date()) {
        throw new Error('Verification code expired. Please request a new one.')
      }

      if (verifyData.attempts >= MAX_OTP_ATTEMPTS) {
        await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
        throw new Error('Too many failed attempts. Code invalidated. Please request a new code.')
      }

      const inputHash = await hashString(String(verificationCode))
      if (verifyData.code !== inputHash) {
        await supabaseAdmin
          .from('admin_verifications')
          .update({ attempts: verifyData.attempts + 1 })
          .eq('admin_id', caller.id)
        const left = MAX_OTP_ATTEMPTS - verifyData.attempts - 1
        throw new Error(`Invalid verification code. ${left} attempt(s) remaining.`)
      }

      // Single-use: consumed whether or not the rest of this succeeds, so a
      // retry has to start from a fresh emailed code.
      await supabaseAdmin.from('admin_verifications').delete().eq('admin_id', caller.id)
    }

    // 1. Soft delete: mark the account disabled.
    //
    // Was 'deleted', which contradicted what the app promises the user. Every
    // deactivate dialog says "ask the SAO Admin to reactivate it", but the SAO
    // screens list users by 'approved'/'disabled' and never show 'deleted', so
    // a self-deactivated account could not be reactivated through the UI at
    // all. 'disabled' is the status the admin toggle already understands, and
    // admin-accept-user clears the auth ban when it moves back to 'approved'.
    //
    // It also keeps the account inside the identity-uniqueness indexes
    // (20240130000008 excludes only 'deleted'), so a deactivated person's
    // university id and email stay reserved for them rather than becoming
    // claimable by someone else while they are away.
    const { error: updateError } = await supabaseAdmin
        .from('user_info')
        .update({ account_status: 'disabled' })
        .eq('id', userId)

    if (updateError) throw updateError

    // 2. Ban the user in auth so they cannot log in again
    // We set a very long ban duration to effectively disable the account
    const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      { ban_duration: '87600h' } // 10 years ban
    )
    if (banError) throw banError

    // 2. Audit Log
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'USER_DEACTIVATED',
      metadata: {
        deactivated_user: userId,
        self_service: isSelf,
        verified_by_otp: isSelf,
      }
    })

    return new Response(JSON.stringify({ message: 'Account deactivated' }), {
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
