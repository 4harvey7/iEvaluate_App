import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

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

    // Validate status value to prevent arbitrary string injection
    const allowedStatuses = ['approved', 'rejected', 'suspended', 'pending']
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

    // ── Audit log ────────────────────────────────────────────────────────────
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'USER_STATUS_CHANGED',
      metadata: { target_user: targetUserId, new_status: status },
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
    // Return safe error messages only — never expose internal details
    const safeMessage = ['Unauthorized', 'Forbidden: Admin access required', 'Invalid status value'].some(
      m => error.message?.startsWith(m)
    ) ? error.message : 'Operation failed. Please try again.'

    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
