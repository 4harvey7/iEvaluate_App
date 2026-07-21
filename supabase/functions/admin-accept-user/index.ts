import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
    const { targetUserId, status = 'approved' } = await req.json()

    // Update status
    const { data: userData, error: updateError } = await supabaseAdmin
      .from('user_info')
      .update({ account_status: status })
      .eq('id', targetUserId)
      .select('email, first_name, last_name')
      .single()

    if (updateError) throw updateError

    const isApproved = status === 'approved'

    // 📧 Notify User via Brevo
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { name: 'SAO Management', email: Deno.env.get('BREVO_SENDER_EMAIL') },
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

    return new Response(JSON.stringify({ message: `User ${status} and notified` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
  }
})
