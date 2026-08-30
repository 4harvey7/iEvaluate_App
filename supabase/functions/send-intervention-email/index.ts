import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    // This function is called by a Database Webhook (not a logged-in user)
    // so we use the service role key to read data freely.
    const supabaseAdmin = createAdminClient()

    // The webhook sends the full new row as { record: { ... } }
    const { record } = await req.json()

    if (!record || !record.instructor_id) {
      return new Response(JSON.stringify({ error: 'No record provided' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // 1. Fetch instructor email + name
    const { data: instructor } = await supabaseAdmin
      .from('user_info')
      .select('email, first_name, last_name')
      .eq('id', record.instructor_id)
      .single()

    // 2. Fetch dean name
    const { data: dean } = await supabaseAdmin
      .from('user_info')
      .select('first_name, last_name')
      .eq('id', record.dean_id)
      .single()

    if (!instructor?.email) {
      return new Response(JSON.stringify({ error: 'Instructor email not found' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const deanName = dean
      ? `${dean.first_name ?? ''} ${dean.last_name ?? ''}`.trim()
      : 'Your Department Head'

    const instructorFirstName = instructor.first_name ?? 'Instructor'

    // 3. Send email via Brevo (same API key already in Supabase secrets)
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not set in Supabase secrets')

    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_KEY,
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: JSON.stringify({
        sender: { name: 'iEvaluate System', email: SENDER_EMAIL },
        to: [{ email: instructor.email }],
        subject: '⚠️ Official Notice: Intervention Report Issued',
        htmlContent: `
          <div style="font-family: sans-serif; max-width: 600px; margin: auto; padding: 24px; border: 1px solid #f0f0f0; border-radius: 12px;">
            <div style="background: #e53e3e; border-radius: 8px; padding: 16px; text-align: center; margin-bottom: 24px;">
              <h2 style="color: white; margin: 0;">⚠️ Official Intervention Notice</h2>
            </div>

            <p style="color: #333;">Dear <strong>${instructorFirstName}</strong>,</p>

            <p style="color: #333;">
              Your department head, <strong>${deanName}</strong>, has issued an official intervention report 
              regarding your recent evaluation results. This is an action that requires your attention.
            </p>

            <div style="background: #fff5f5; border-left: 4px solid #e53e3e; padding: 16px; border-radius: 4px; margin: 20px 0;">
              <p style="margin: 0 0 8px 0;"><strong>Action Required:</strong> ${record.action_type ?? 'N/A'}</p>
              <p style="margin: 0 0 8px 0;"><strong>Notes:</strong> ${record.notes ?? 'No additional notes provided.'}</p>
              <p style="margin: 0; color: #666; font-size: 13px;">Status: ${record.status ?? 'Active Tracking'}</p>
            </div>

            <p style="color: #333;">
              Please log in to the <strong>iEvaluate app</strong> to view the full details of this notice 
              on your dashboard.
            </p>

            <p style="color: #999; font-size: 12px; margin-top: 32px; border-top: 1px solid #f0f0f0; padding-top: 16px;">
              This is an automated message from the iEvaluate System. 
              This notice can only be removed by your department head once resolved.
            </p>
          </div>
        `,
      }),
    })

    const resData = await res.json()

    if (!res.ok) {
      console.error('Brevo API Error:', resData)
      throw new Error(`Email failed: ${resData.message || res.statusText}`)
    }

    console.log(`Intervention email sent to ${instructor.email}`)

    return new Response(JSON.stringify({ message: 'Email sent successfully' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('send-intervention-email error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})