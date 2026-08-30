import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    // ── C-2 FIX: Authenticate the caller ────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── C-2 FIX: Verify caller is SAO_ADMIN ─────────────────────────────────
    const { data: adminCheck, error: adminError } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .single()

    if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

    const { targetUserId, status = 'approved' } = await req.json()

    // Validate status value to prevent arbitrary string injection.
    //
    // 'disabled' was MISSING, and it is the only value the two admin screens
    // ever send when deactivating someone (user_management_screen.dart and
    // personnel_management_screen.dart both compute
    // `currentStatus == 'approved' ? 'disabled' : 'approved'`). So every
    // deactivation threw `Invalid status value: disabled` and showed the raw
    // error in a red snackbar. Deactivation had never once worked -- all 17
    // accounts sat at 'approved' because no other value could ever be written.
    const allowedStatuses = ['approved', 'rejected', 'suspended', 'pending', 'disabled']
    if (!allowedStatuses.includes(status)) {
      throw new Error(`Invalid status value: ${status}`)
    }

    // Update status
    const { data: userData, error: updateError } = await supabaseAdmin
      .from('user_info')
      .update({ account_status: status })
      .eq('id', targetUserId)
      .select('email, first_name, last_name')
      .single()

    if (updateError) throw updateError

    // ── Keep Supabase Auth in step with account_status ──────────────────────
    //
    // account_status alone is only an application-layer gate: signIn() reads it
    // and refuses, but the row is not what actually stops a session being
    // issued. Anything holding the anon key can call signInWithPassword
    // directly. Banning at the auth layer is what genuinely revokes access.
    //
    // The reverse direction is the bug that mattered: delete-user bans for
    // 87600h (10 years) and NOTHING anywhere cleared it. Reactivating a deleted
    // user set account_status back to 'approved', the admin screen looked
    // correct, and login still failed -- with "Incorrect ID or password",
    // because a banned user is indistinguishable from a wrong password at the
    // client. There is a live victim: af6f7dda-ed6e-489b-a4c3-edaf23e2bebb,
    // banned until 2036, who has real evaluation data.
    const BAN_STATUSES = ['disabled', 'rejected', 'suspended']
    let authAction: 'banned' | 'unbanned' | 'unchanged' = 'unchanged'

    if (BAN_STATUSES.includes(status)) {
      const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(
        targetUserId,
        { ban_duration: '87600h' },
      )
      if (banError) {
        throw new Error(
          'Status saved but the account could not be locked in Auth. Please retry.',
        )
      }
      authAction = 'banned'
    } else if (status === 'approved') {
      // 'none' is how Supabase clears an existing ban. Safe to send even when
      // the user was never banned, which makes reactivation idempotent.
      const { error: unbanError } = await supabaseAdmin.auth.admin.updateUserById(
        targetUserId,
        { ban_duration: 'none' },
      )
      if (unbanError) {
        throw new Error(
          'Status saved but the account could not be unlocked in Auth. Please retry.',
        )
      }
      authAction = 'unbanned'
    }
    // 'pending' deliberately leaves Auth alone: a fresh signup is already
    // blocked by the account_status check and has never been banned.

    // ── Audit log ────────────────────────────────────────────────────────────
    // auth_action is recorded because "status changed to approved" and "the auth
    // ban was actually cleared" are two different facts, and it was the gap
    // between them that locked a real user out for ten years.
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'USER_STATUS_CHANGED',
      metadata: { target_user: targetUserId, new_status: status, auth_action: authAction },
    })

    const isApproved = status === 'approved'

    // 📧 Notify User via Brevo
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not configured')

    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: SENDER_EMAIL },
        to: [{ email: userData.email }],
        subject: isApproved ? 'Account Approved!' : 'Account Status Updated',
        htmlContent: `
          <h3>Hello, ${userData.first_name}!</h3>
          <p>Your account status has been updated to: <b>${status.toUpperCase()}</b>.</p>
          ${isApproved
            ? '<p>Your registration has been approved. You can now log in to the iEvaluate app.</p>'
            : '<p>Your account has been deactivated/disabled by the administrator. If you believe this is an error, please contact the SAO office.</p>'}
          <p>Best regards,<br>SAO Management Team</p>
        `
      })
    })

    return new Response(JSON.stringify({ message: `User ${status} and notified` }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    // Return safe error messages only — never expose internal details.
    // The two "Status saved but..." messages are listed on purpose: they are the
    // difference between an admin knowing to retry and an admin believing a
    // reactivation worked when the account is still locked.
    const safeMessage = [
      'Unauthorized',
      'Forbidden: Admin access required',
      'Invalid status value',
      'Status saved but the account could not be locked in Auth.',
      'Status saved but the account could not be unlocked in Auth.',
    ].some(
      m => error.message?.startsWith(m)
    ) ? error.message : 'Operation failed. Please try again.'

    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
