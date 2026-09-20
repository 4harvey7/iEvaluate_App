// supabase/functions/_shared/admin_client.ts
//
// One place that decides which key the admin (service-role) client uses.
//
// WHY THIS EXISTS
// The project's original service_role JWT was public in git, so it was rotated
// to the new API-key format (sb_secret_...). Closing the leak means DISABLING
// the legacy JWT keys in the Supabase dashboard -- and the platform injects the
// legacy key as SUPABASE_SERVICE_ROLE_KEY, which all eight functions used to
// read directly. Reading it directly made every one of them depend on the very
// key we are trying to switch off.
//
// WHY THE NAME IS NOT SUPABASE_ANYTHING
// Supabase reserves the SUPABASE_ prefix for its own injected variables:
//
//   $ supabase secrets set --env-file <file>
//   Env name cannot start with SUPABASE_, skipping: SUPABASE_SECRET_KEY
//
// so a project secret by that name cannot exist. The key is therefore set as
// ADMIN_SECRET_KEY:
//
//   supabase secrets set ADMIN_SECRET_KEY=sb_secret_...
//
// FALLBACK ORDER
//   1. ADMIN_SECRET_KEY       explicitly set by us, and the only one whose
//                             value and format we control
//   2. SUPABASE_SECRET_KEYS   injected by the platform for the new key system.
//                             Note the plural: a project can hold several
//                             secret keys, and only a digest is visible from
//                             the CLI, so the exact encoding cannot be
//                             confirmed from outside a running function. It is
//                             parsed defensively below and used only if (1) is
//                             missing.
//   3. SUPABASE_SERVICE_ROLE_KEY  the legacy JWT. Last resort, and the thing
//                             this file exists to stop depending on.
//
// Every one of these carries full service-role authority and bypasses RLS.
// Nothing here relaxes that -- each caller must still authorise its own request.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Pulls a single usable key out of SUPABASE_SECRET_KEYS.
 *
 * The plural name means the value may hold more than one key, and the format is
 * not documented anywhere we can check without deploying a probe. So handle the
 * three plausible shapes rather than assume one: a bare key, a JSON array, and
 * a separated list. Anything unrecognised yields null and the next fallback is
 * used, which is safer than passing a malformed value to createClient and
 * getting an "invalid JWT" error far from the real cause.
 */
function firstSecretFromPlural(raw: string): string | null {
  const trimmed = raw.trim()
  if (!trimmed) return null

  // Shape 1: already a bare key.
  if (trimmed.startsWith('sb_secret_') || trimmed.startsWith('eyJ')) {
    // A separated list also starts this way, so still split it.
    const parts = trimmed.split(/[,\s]+/).filter(Boolean)
    return parts[0] ?? null
  }

  // Shape 2: JSON -- an array of strings, or of objects carrying the key.
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed)
      const list = Array.isArray(parsed) ? parsed : [parsed]
      for (const entry of list) {
        if (typeof entry === 'string' && entry.startsWith('sb_secret_')) return entry
        if (entry && typeof entry === 'object') {
          for (const field of ['api_key', 'secret', 'key', 'value']) {
            const v = (entry as any)[field]
            if (typeof v === 'string' && v.startsWith('sb_secret_')) return v
          }
        }
      }
    } catch {
      // fall through to the separated-list attempt
    }
  }

  // Shape 3: separated list of something we did not recognise above.
  const parts = trimmed.split(/[,\s]+/).filter(Boolean)
  const secret = parts.find((p) => p.startsWith('sb_secret_'))
  return secret ?? null
}

/** The admin key in use, newest format first. Throws rather than returning ''
 *  -- an empty key produces a confusing "invalid JWT" far from the cause. */
export function adminKey(): string {
  const explicit = (Deno.env.get('ADMIN_SECRET_KEY') || '').trim()
  if (explicit) return explicit

  const plural = Deno.env.get('SUPABASE_SECRET_KEYS') || ''
  const fromPlural = firstSecretFromPlural(plural)
  if (fromPlural) return fromPlural

  const legacy = (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '').trim()
  if (legacy) return legacy

  throw new Error(
    'No admin key configured. Run: supabase secrets set ADMIN_SECRET_KEY=sb_secret_...')
}

export function supabaseUrl(): string {
  const url = Deno.env.get('SUPABASE_URL') || ''
  if (!url) throw new Error('SUPABASE_URL is not set')
  return url
}

/** Service-role client. Bypasses RLS, so authorise the caller before using it. */
export function createAdminClient(): any {
  return createClient(supabaseUrl(), adminKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  })
}
