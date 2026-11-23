// Pure helpers for admin-update-role (no Deno APIs, so Node can test them:
// node --test supabase/functions/admin-update-role/logic.test.ts).

export const ADMIN_ROLE = 'SAO_ADMIN'

/**
 * A code is needed when the caller says it is a promotion (e.g. to department
 * head), or when the change moves anyone into or out of SAO_ADMIN. The second
 * part is decided from the roles on record, never from the request, so a
 * demotion (own or another admin's) cannot skip the code.
 */
export function roleChangeNeedsCode(opts: {
  currentRole: string | null
  newRole: string | null
  isPromotion: unknown
}): boolean {
  if (opts.isPromotion === true) return true
  const touchesAdmin = opts.currentRole === ADMIN_ROLE || opts.newRole === ADMIN_ROLE
  return touchesAdmin && opts.currentRole !== opts.newRole
}

/** Active means the same gate admin-accept-user applies: approved and not disabled. */
export function isActiveAccount(info: { account_status?: unknown; disabled?: unknown } | null): boolean {
  return String(info?.account_status ?? '').trim().toLowerCase() === 'approved' && info?.disabled !== true
}

/** True when an admin is being demoted and no other active admin would remain. */
export function removesLastAdmin(opts: {
  currentRole: string | null
  newRole: string | null
  otherActiveAdmins: number
}): boolean {
  return opts.currentRole === ADMIN_ROLE && opts.newRole !== ADMIN_ROLE && opts.otherActiveAdmins < 1
}
