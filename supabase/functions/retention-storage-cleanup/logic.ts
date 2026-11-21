// Pure helpers for retention-storage-cleanup (no Deno APIs, so Node can test
// them: node --test supabase/functions/retention-storage-cleanup/logic.test.ts).

export const DEFAULT_DAYS = 90
export const MIN_DAYS = 30
export const MIN_SECRET_LENGTH = 32

export type Plan = { dryRun: boolean; days: number }

/** Deletes only when the body says dry_run: false (boolean). Anything else is a dry run. */
export function parsePlan(body: unknown): Plan | { error: string } {
  const b = (body && typeof body === 'object' && !Array.isArray(body)) ? body as Record<string, unknown> : {}
  const dryRun = b.dry_run !== false
  if (b.days === undefined || b.days === null) return { dryRun, days: DEFAULT_DAYS }
  const days = b.days
  if (typeof days !== 'number' || !Number.isInteger(days) || days < MIN_DAYS || days > 3650) {
    return { error: `days must be a whole number from ${MIN_DAYS} to 3650` }
  }
  return { dryRun, days }
}

/** Constant-time comparison: both sides are hashed first, so length leaks nothing. */
export async function secretMatches(given: string | null, expected: string): Promise<boolean> {
  if (!given || expected.length < MIN_SECRET_LENGTH) return false
  const enc = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(given)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ])
  const x = new Uint8Array(a), y = new Uint8Array(b)
  let diff = 0
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i]
  return diff === 0
}
