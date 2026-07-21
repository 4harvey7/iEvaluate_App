import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
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

    const authHeader = req.headers.get('Authorization')
    const { data: { user: caller } } = await supabaseAdmin.auth.getUser(authHeader!.replace('Bearer ', ''))

    const { autoSync, semester, academicYear } = await req.json()

    // 1. Fetch all SAO Admin emails
    const { data: admins } = await supabaseAdmin
      .from('Sao_users')
      .select('user_info(email)')
      .eq('roles!inner(Roles)', 'SAO_ADMIN')

    const adminEmails = admins?.map(a => (a.user_info as any).email).filter(Boolean) || []

    if (adminEmails.length > 0) {
      const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
      const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')

      const syncStatus = autoSync ? 'ENABLED' : 'DISABLED'
      let message = `Auto-Sync with system clock has been <b>${syncStatus}</b> by ${caller?.email}.<br><br>`

      if (!autoSync) {
        message += `The active term has been manually set to:<br>`
        message += `<ul><li><b>Semester:</b> ${semester}</li><li><b>Academic Year:</b> ${academicYear}</li></ul>`
      }

      await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: { 'api-key': BREVO_KEY!, 'content-type': 'application/json' },
        body: JSON.stringify({
          sender: { name: 'iEvaluate System', email: SENDER_EMAIL },
          to: adminEmails.map(email => ({ email })),
          subject: `[SYSTEM] Academic Term Settings Updated`,
          htmlContent: `
            <h3>System Setting Alert</h3>
            <p>${message}</p>
            <p>Please check the admin dashboard for details.</p>
          `
        })
      })
    }

    // 2. Audit Log
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller!.id,
      action: 'SYSTEM_SETTINGS_UPDATED',
      metadata: { autoSync, semester, academicYear }
    })

    return new Response(JSON.stringify({ message: 'Settings updated and notifications sent' }), {
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
