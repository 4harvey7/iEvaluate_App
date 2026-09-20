import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Map logical action names to n8n webhook paths
const ACTION_PATHS: Record<string, string> = {
  'health': 'health-check',
  'health-check': 'health-check',
  'scan-upload': 'sast-scan-upload',
  'link-upload': 'sast-link-upload',
  'crop-ocr': 'sast-crop-ocr',
  'manual-correction': 'sast-manual-correction',
  'bulk-import': 'subject-bulk-import',
  'import-error-correction': 'import-error-correction',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    // ── 1. Authenticate Caller ───────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized: Missing token' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user: caller }, error: userError } = await supabaseAdmin.auth.getUser(token)
    if (userError || !caller) {
      return new Response(JSON.stringify({ error: 'Unauthorized: Invalid token' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    // ── 2. Parse Request Body ────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}))
    const { action, payload } = body

    if (!action || !ACTION_PATHS[action]) {
      return new Response(JSON.stringify({ error: `Invalid action: ${action}` }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // ── 3. Role Authorization ────────────────────────────────────────────────
    // Actions other than health check require verified SAO membership
    if (action !== 'health' && action !== 'health-check') {
      const { data: saoRole, error: roleError } = await supabaseAdmin
        .from('Sao_users')
        .select('roles!inner(Roles)')
        .eq('user_id', caller.id)
        .maybeSingle()

      const roleName = (saoRole as any)?.roles?.Roles?.toUpperCase()
      if (roleError || !roleName || (!roleName.includes('SAO_ADMIN') && !roleName.includes('SAO_STAFF'))) {
        return new Response(JSON.stringify({ error: 'Forbidden: SAO permissions required' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 403,
        })
      }
    }

    // ── 4. Resolve Target n8n Webhook URL ─────────────────────────────────────
    // Configured exclusively in Supabase Secrets — completely invisible to mobile client!
    const n8nBase = (Deno.env.get('N8N_BASE_URL') || 'http://5.104.84.162:5678').trim().replace(/\/+$/, '')
    const useTest = (Deno.env.get('USE_N8N_TEST') || 'false').trim().toLowerCase() === 'true'
    const webhookPrefix = useTest ? 'webhook-test' : 'webhook'
    const webhookPath = ACTION_PATHS[action]
    const targetUrl = `${n8nBase}/${webhookPrefix}/${webhookPath}`

    // Forwarding headers
    const forwardHeaders: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Forwarded-For-User': caller.id,
      'X-Caller-Email': caller.email ?? '',
    }

    // Optional shared secret header between Edge Function and n8n
    const n8nSecret = (Deno.env.get('N8N_WEBHOOK_SECRET') || '').trim()
    if (n8nSecret) {
      forwardHeaders['X-Webhook-Secret'] = n8nSecret
    }

    // Inject verified user_id into payload to prevent spoofing
    const enrichedPayload = {
      ...(payload || {}),
      user_id: caller.id,
    }

    // ── 5. Proxy to n8n ──────────────────────────────────────────────────────
    const controller = new AbortController()
    // 60-second timeout for heavy OCR / bulk-import processing
    const timeoutId = setTimeout(() => controller.abort(), 60000)

    try {
      const n8nResponse = await fetch(targetUrl, {
        method: action === 'health' || action === 'health-check' ? 'GET' : 'POST',
        headers: forwardHeaders,
        body: action === 'health' || action === 'health-check' ? undefined : JSON.stringify(enrichedPayload),
        signal: controller.signal,
      })
      clearTimeout(timeoutId)

      const responseText = await n8nResponse.text()
      let responseJson: any = null
      try {
        responseJson = JSON.parse(responseText)
      } catch {
        responseJson = { message: responseText }
      }

      return new Response(JSON.stringify(responseJson), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: n8nResponse.status,
      })
    } catch (fetchErr: any) {
      clearTimeout(timeoutId)
      if (fetchErr.name === 'AbortError') {
        return new Response(JSON.stringify({ error: 'Gateway Timeout: n8n took too long to respond' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 504,
        })
      }
      return new Response(JSON.stringify({ error: `Could not connect to automation server: ${fetchErr.message}` }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 502,
      })
    }
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message || 'Internal server error' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
