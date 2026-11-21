// CORS for the edge functions. The Flutter app is not subject to CORS, so by
// default no Access-Control-Allow-Origin is sent and browsers are blocked.
// Set ALLOWED_ORIGINS (comma-separated) to allow specific browser origins.
export function corsFor(req: Request): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  const allowed = (Deno.env.get('ALLOWED_ORIGINS') || '').split(',').map((o) => o.trim()).filter(Boolean)
  const origin = req.headers.get('Origin')
  if (origin && allowed.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin
    headers['Vary'] = 'Origin'
  }
  return headers
}
