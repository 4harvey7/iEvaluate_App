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

    // ── Authenticate caller ──────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── C-3 FIX: Verify caller is SAO_ADMIN ─────────────────────────────────
    const { data: adminCheck, error: adminError } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .single()

    if (adminError || (adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

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
      if (!SENDER_EMAIL) throw new Error('BREVO_SENDER_EMAIL is not configured')

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
    const safeMessage = ['Unauthorized', 'Forbidden:', 'BREVO_SENDER_EMAIL'].some(
      m => error.message?.startsWith(m)
    ) ? error.message : 'Operation failed. Please try again.'

    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
