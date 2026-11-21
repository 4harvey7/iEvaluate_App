import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'
import { corsFor } from '../_shared/cors.ts'

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

// Largest accepted request body: a phone scan is ~3-5 MB of base64.
const MAX_BODY_BYTES = 15 * 1024 * 1024

// Fields the app actually sends per action; anything else is dropped.
// Score keys (m1..m10, p1..p10) are matched by pattern.
const SCORE_KEY = /^[mp](10|[1-9])$/
const ACTION_FIELDS: Record<string, string[]> = {
  'scan-upload': ['user_id', 'term_id', 'task_id', 'filename', 'paper_size', 'form_suspect', 'timestamp', 'image'],
  'link-upload': ['user_id', 'term_id', 'link', 'type', 'semester', 'academic_year', 'timestamp'],
  'manual-correction': [
    'failed_scan_id', 'task_id', 'user_id', 'term_id', 'instructor', 'instructor_id', 'subject',
    'subject_name', 'subject_id', 'remarks', 'student_id', 'stamp_no', 'stamp_source',
    'manually_corrected', 'validation_status', 'correction_source', 'timestamp',
  ],
  'bulk-import': ['link', 'term_id', 'user_id'],
  'import-error-correction': [
    'import_error_id', 'corrected_instructor_id', 'corrected_subject_id', 'term_id',
    'resolved_by', 'raw_data', 'source', 'timestamp',
  ],
}

function pickFields(action: string, payload: any): Record<string, unknown> {
  const allowed = ACTION_FIELDS[action]
  const out: Record<string, unknown> = {}
  if (!allowed || !payload || typeof payload !== 'object') return out
  for (const [k, v] of Object.entries(payload)) {
    if (allowed.includes(k) || (action === 'manual-correction' && SCORE_KEY.test(k))) out[k] = v
  }
  return out
}

serve(async (req) => {
  const corsHeaders = corsFor(req)
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
    // Cap the body (Content-Length first, then the real size) before parsing.
    const declared = Number(req.headers.get('Content-Length') || 0)
    const rawBody = declared > MAX_BODY_BYTES ? null : await req.text()
    if (rawBody === null || rawBody.length > MAX_BODY_BYTES) {
      return new Response(JSON.stringify({ error: 'Payload too large' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 413,
      })
    }
    let body: any = {}
    try { body = JSON.parse(rawBody) } catch { /* invalid JSON falls through to the action check */ }
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

      // A pending signup can hold an SAO_STAFF row, so the account must also be approved.
      const { data: callerInfo, error: infoError } = await supabaseAdmin
        .from('user_info')
        .select('account_status, disabled')
        .eq('id', caller.id)
        .maybeSingle()
      const approved = !infoError &&
        String(callerInfo?.account_status ?? '').trim().toLowerCase() === 'approved' &&
        callerInfo?.disabled !== true

      const roleName = (saoRole as any)?.roles?.Roles?.toUpperCase()
      if (roleError || !approved || !roleName || (!roleName.includes('SAO_ADMIN') && !roleName.includes('SAO_STAFF'))) {
        return new Response(JSON.stringify({ error: 'Forbidden: SAO permissions required' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 403,
        })
      }
    }

    // ── 4. Resolve Target n8n Webhook URL ─────────────────────────────────────
    // Configured exclusively in Supabase Secrets — completely invisible to mobile client!
    const n8nBase = (Deno.env.get('N8N_BASE_URL') || '').trim().replace(/\/+$/, '')
    const allowHttp = (Deno.env.get('N8N_ALLOW_HTTP') || 'false').trim().toLowerCase() === 'true'
    if (!n8nBase || (!n8nBase.startsWith('https://') && !allowHttp)) {
      console.error('n8n-proxy: N8N_BASE_URL is unset or not https (set N8N_ALLOW_HTTP=true for local testing only)')
      return new Response(JSON.stringify({ error: 'Service misconfigured' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      })
    }
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
      ...pickFields(action, payload),
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
      console.error('n8n-proxy: upstream fetch failed:', fetchErr)
      return new Response(JSON.stringify({ error: 'Could not connect to automation server' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 502,
      })
    }
  } catch (error: any) {
    console.error('n8n-proxy error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
