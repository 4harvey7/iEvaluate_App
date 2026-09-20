// supabase/functions/_shared/department_head_guard.ts
//
// One department head per department, server side.
//
// The guarantee is the trigger `department_table_one_head` from migration
// 20240130000016 -- it holds for every write, including a REST call made with
// the publishable key. This module exists so the two admin functions can say
// WHO is already sitting in the chair before they create an account, send an
// OTP or fire a notification email, instead of surfacing a failed insert.
//
// Four names count as a head, matching role_nav_config.roleFromString: all of
// them route to the same dept-head dashboard, so two of them over one
// department is exactly the collision being prevented.
//
// Three copies of this rule exist and must agree:
//   * public.is_department_head_role(bigint)  -- migration 20240130000016
//   * isDepartmentHeadRole below
//   * kDepartmentHeadRoles -- lib/core/services/department_head_guard.dart
// The database one is authoritative; it backs the trigger.

// deno-lint-ignore-file no-explicit-any

/**
 * Prefix every head-conflict message starts with.
 *
 * Both functions list it in their `safePrefixes`, so the sentence reaches the
 * admin verbatim instead of being flattened to "Operation failed". The
 * trigger's own exception message starts with the same words, which is what
 * lets a message raised by the database pass the same filter.
 */
export const HEAD_CONFLICT_PREFIX = 'Department head already assigned'

/** Is this role name one that lands on the department-head dashboard? */
export function isDepartmentHeadRole(roleName: unknown): boolean {
  const normalised = String(roleName ?? '')
    .trim()
    .toUpperCase()
    .replace(/[\s_-]+/g, '-')
  return normalised === 'DEPARTMENT-HEAD' || normalised === 'DEAN'
}

/**
 * The head currently sitting for [deptId], or null when the chair is free.
 *
 * [excludeUserId] is the account being edited, so re-saving the sitting head
 * does not report them as blocking themselves.
 */
export async function findDepartmentHead(
  client: any,
  deptId: number | string,
  excludeUserId?: string | null,
): Promise<{ userId: string | null; name: string } | null> {
  const { data, error } = await client
    .from('department_table')
    .select('user_id, roles:roles(id, Roles), user_info!user_id(first_name, last_name, account_status)')
    .eq('Department_name_ID', deptId)
  if (error) throw error

  for (const row of (data ?? [])) {
    if (excludeUserId && row.user_id === excludeUserId) continue

    // The embed comes back as an object for a to-one relationship and as an
    // array when PostgREST cannot prove it is to-one. Both shapes appear in
    // this project already, so both are handled.
    const roleRaw = Array.isArray(row.roles) ? row.roles[0] : row.roles
    if (!isDepartmentHeadRole(roleRaw?.Roles)) continue

    const info = Array.isArray(row.user_info) ? row.user_info[0] : row.user_info
    // A deleted account is not sitting in the chair.
    if (String(info?.account_status ?? '').toLowerCase() === 'deleted') continue

    const name = [info?.first_name, info?.last_name]
      .filter((part: unknown) => typeof part === 'string' && part.trim() !== '')
      .join(' ')
      .trim()

    return { userId: row.user_id ?? null, name: name || 'another account' }
  }

  return null
}

/** The sentence shown to the admin. Starts with [HEAD_CONFLICT_PREFIX]. */
export function describeHeadConflict(headName: string, deptName?: string | null): string {
  const where = deptName && deptName.trim() !== '' ? deptName : 'that department'
  return `${HEAD_CONFLICT_PREFIX}: ${headName} already holds the department head ` +
    `role for ${where}. A department can only have one head -- change that ` +
    `person's role first, or choose a different department.`
}

/**
 * Throws the readable conflict when [deptId] already has a head and
 * [roleName] would add another. No-op for every other role.
 */
export async function assertDepartmentHeadVacant(
  client: any,
  opts: {
    roleName: unknown
    deptId: number | string | null | undefined
    excludeUserId?: string | null
  },
): Promise<void> {
  if (!isDepartmentHeadRole(opts.roleName)) return
  if (opts.deptId === null || opts.deptId === undefined) return

  const head = await findDepartmentHead(client, opts.deptId, opts.excludeUserId)
  if (!head) return

  const { data: deptRow } = await client
    .from('department_name').select('d_name').eq('id', opts.deptId).limit(1)
  const deptName = deptRow && deptRow.length > 0 ? deptRow[0].d_name : null

  throw new Error(describeHeadConflict(head.name, deptName))
}
