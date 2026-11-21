// retention-storage-cleanup: nightly deletion of old page pictures in Storage (migration 040).
//
// Called by pg_cron + pg_net with header x-retention-secret (RETENTION_CLEANUP_SECRET,
// compared in constant time). No user JWT: deploy with --no-verify-jwt.
// Which files: public.retention_storage_candidates(days) -- 'scan-pages' objects
// older than `days` (>= 30) that no open batch or open review needs.
// Body: {"dry_run": false, "days": 90} deletes; anything without dry_run:false only counts.
// Returns and logs counts only (no file names, no student data).
import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'
import { corsFor } from '../_shared/cors.ts'
import { parsePlan, secretMatches } from './logic.ts'

const BUCKET = 'scan-pages'
const CHUNK = 500       // below the Storage remove() limit of 1000
const MAX_ROUNDS = 20   // at most 10,000 files per run; the rest go the next night

serve(async (req) => {
  const corsHeaders = corsFor(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const reply = (body: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405)
  if (!(await secretMatches(req.headers.get('x-retention-secret'), Deno.env.get('RETENTION_CLEANUP_SECRET') || ''))) {
    return reply({ error: 'Unauthorized' }, 401)
  }

  let body: unknown = {}
  try { body = await req.json() } catch { /* empty body = dry run with defaults */ }
  const plan = parsePlan(body)
  if ('error' in plan) return reply({ error: plan.error }, 400)

  const sb = createAdminClient()
  const out = { dry_run: plan.dryRun, days: plan.days, eligible: 0, deleted: 0, rounds: 0, more_left: false }
  try {
    if (plan.dryRun) {
      const { data, error } = await sb.rpc('retention_storage_candidates', { p_days: plan.days, p_limit: 1000 })
      if (error) throw { stage: 'list', code: error.code }
      out.eligible = (data ?? []).length
      out.more_left = out.eligible >= 1000
    } else {
      while (out.rounds < MAX_ROUNDS) {
        out.rounds++
        const { data, error } = await sb.rpc('retention_storage_candidates', { p_days: plan.days, p_limit: CHUNK })
        if (error) throw { stage: 'list', code: error.code }
        const names: string[] = (data ?? []).map((r: { name: string }) => r.name)
        if (!names.length) break
        out.eligible += names.length
        const rm = await sb.storage.from(BUCKET).remove(names)
        if (rm.error) throw { stage: 'remove', code: (rm.error as any).statusCode ?? rm.error.name }
        const removed = (rm.data ?? []).length
        out.deleted += removed
        // the page row keeps page_image_saved_at, so the viewer can say why the picture is gone
        const up = await sb.from('scan_batch_items').update({ page_image_path: null }).in('page_image_path', names)
        if (up.error) throw { stage: 'clear_paths', code: up.error.code }
        out.more_left = names.length === CHUNK && removed > 0
        if (!out.more_left) break // nothing left (or Storage removed nothing: stop, don't spin)
      }
    }
    console.log('retention-storage-cleanup', JSON.stringify(out))
    return reply(out)
  } catch (e) {
    const info = (e && typeof e === 'object' && 'stage' in e) ? e : { stage: 'unexpected', code: (e as Error)?.name }
    console.error('retention-storage-cleanup failed', JSON.stringify({ ...info, deleted: out.deleted }))
    return reply({ error: 'Cleanup failed', ...info, deleted: out.deleted }, 500)
  }
})
