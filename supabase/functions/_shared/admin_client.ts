// supabase/functions/_shared/admin_client.ts
//
// One place that decides which key the admin (service-role) client uses.
//
// WHY THIS EXISTS
// The project's original service_role JWT was public in git, so it was rotated
// to the new API-key format (sb_secret_...). Closing the leak means DISABLING
// the legacy JWT keys in the Supabase dashboard -- and the platform injects the
// legacy key as SUPABASE_SERVICE_ROLE_KEY, which every function here read
// directly. Reading it directly makes all eight functions depend on the very
// key we are trying to switch off.
//
// So: prefer an explicitly-set SUPABASE_SECRET_KEY, fall back to the injected
// legacy value. Set the secret once and the functions survive the cutover:
//
//   supabase secrets set SUPABASE_SECRET_KEY=sb_secret_...
//
// Both keys carry full service-role authority. Nothing here relaxes that --
// every caller must still authorise the request itself.

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/** The admin key in use, newest format first. Throws rather than returning ''
 *  -- an empty key produces a confusing "invalid JWT" far from the cause. */
export function adminKey(): string {
  const key = Deno.env.get('SUPABASE_SECRET_KEY') ||
              Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
  if (!key) {
    throw new Error(
      'No admin key configured. Set SUPABASE_SECRET_KEY on this project.')
  }
  return key
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
