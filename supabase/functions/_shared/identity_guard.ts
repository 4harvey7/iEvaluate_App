// supabase/functions/_shared/identity_guard.ts
//
// Server-side duplicate prevention for every function that creates or renames
// an account: admin-create-user, admin-create-academic, admin-update-role.
//
// THE RULES
//   university_id  unique across all active accounts (case-insensitive)
//   email          unique across all active accounts (case-insensitive)
//   first + last   unique TOGETHER -- sharing only one half is allowed
//
// Three copies of the normalisation rule exist and must agree:
//   * public.norm_identity(text)          -- migration 20240130000008
//   * IdentityValidator.normalise         -- lib/core/services/identity_validator.dart
//   * normaliseIdentity below
// The database one is authoritative; it backs the unique indexes.

// deno-lint-ignore-file no-explicit-any

/** Lower-case, trim the ends, collapse runs of inner whitespace. */
export function normaliseIdentity(value: unknown): string {
  if (typeof value !== 'string') return ''
  return value.toLowerCase().replace(/\s+/g, ' ').trim()
}

/** Clean for storage: keeps the person's own capitalisation. */
export function cleanIdentity(value: unknown): string {
  if (typeof value !== 'string') return ''
  return value.replace(/\s+/g, ' ').trim()
}

/** Emails are lower-cased for storage so the login lookup stays consistent. */
export function cleanEmail(value: unknown): string {
  return cleanIdentity(value).toLowerCase()
}

export type ConflictField = 'university_id' | 'email' | 'name'

const NAME_RE = /^\p{L}[\p{L}\p{M}\s'\-.]*$/u
const UNIVERSITY_ID_RE = /^[a-zA-Z0-9\-]+$/
const EMAIL_RE = /^[\w\-.]+@([\w-]+\.)+[\w-]{2,}$/

/**
 * Rejects malformed input before it reaches the database.
 *
 * The client screens validate too, but a function is a public HTTP endpoint --
 * anything reaching it may not have come from the app. Returns an error string
 * or null. Only fields that are `undefined` are skipped.
 */
export function validateIdentityFormat(input: {
  firstName?: unknown
  lastName?: unknown
  email?: unknown
  universityId?: unknown
}): string | null {
  const checkName = (raw: unknown, label: string): string | null => {
    const v = cleanIdentity(raw)
    if (!v) return `${label} is required`
    if (v.length < 2) return `${label} must be at least 2 characters`
    if (v.length > 60) return `${label} is too long`
    if (!NAME_RE.test(v)) return `${label} contains invalid characters`
    return null
  }

  if (input.firstName !== undefined) {
    const e = checkName(input.firstName, 'First name')
    if (e) return e
  }
  if (input.lastName !== undefined) {
    const e = checkName(input.lastName, 'Last name')
    if (e) return e
  }
  if (input.email !== undefined) {
    const v = cleanEmail(input.email)
    if (!v) return 'Email is required'
    if (v.length > 254 || !EMAIL_RE.test(v)) return 'Enter a valid email address'
  }
  if (input.universityId !== undefined) {
    const v = cleanIdentity(input.universityId)
    if (!v) return 'University ID is required'
    if (v.length < 4) return 'University ID must be at least 4 characters'
    if (v.length > 30) return 'University ID is too long'
    if (!UNIVERSITY_ID_RE.test(v)) {
      return 'University ID must be letters, numbers, or hyphens only'
    }
  }
  return null
}

/**
 * Returns which field already belongs to somebody else, or null if all clear.
 *
 * Prefers the `check_identity_conflict` RPC -- indexed, and the same code path
 * the app uses. Falls back to comparing normalised values in memory if that
 * function is missing, so these endpoints keep working on a project where
 * migration 20240130000008 has not been applied yet. Note that on such a
 * project this check is ALL there is: without the migration there are no unique
 * indexes, so a simultaneous double submission can still slip through.
 *
 * `excludeUserId` is the account being edited, so a rename does not collide
 * with itself.
 */
export async function findIdentityConflict(
  supabaseAdmin: any,
  input: {
    firstName?: string
    lastName?: string
    email?: string
    universityId?: string
    excludeUserId?: string | null
  },
): Promise<ConflictField | null> {
  const first = input.firstName === undefined ? null : cleanIdentity(input.firstName)
  const last = input.lastName === undefined ? null : cleanIdentity(input.lastName)
  const mail = input.email === undefined ? null : cleanEmail(input.email)
  const uid = input.universityId === undefined ? null : cleanIdentity(input.universityId)
  const exclude = input.excludeUserId ?? null

  const { data, error } = await supabaseAdmin.rpc('check_identity_conflict', {
    p_first_name: first,
    p_last_name: last,
    p_email: mail,
    p_university_id: uid,
    p_exclude_id: exclude,
  })

  if (!error) return (data as ConflictField | null) ?? null

  console.warn('[identity_guard] RPC unavailable, using in-memory scan:', error.message)

  // Fallback. The table holds university staff, so selecting four columns is
  // cheap; doing it in memory avoids having to escape LIKE wildcards, which
  // matters because '_' is legal in an email address and is a LIKE wildcard.
  const { data: rows, error: scanError } = await supabaseAdmin
    .from('user_info')
    .select('id, first_name, last_name, email, university_id, account_status')

  if (scanError) throw scanError

  const active = (rows ?? []).filter(
    (r: any) => (r.account_status ?? '') !== 'deleted' && r.id !== exclude,
  )

  if (uid && active.some((r: any) => normaliseIdentity(r.university_id) === normaliseIdentity(uid))) {
    return 'university_id'
  }
  if (mail && active.some((r: any) => normaliseIdentity(r.email) === normaliseIdentity(mail))) {
    return 'email'
  }
  if (
    first && last &&
    active.some(
      (r: any) =>
        normaliseIdentity(r.first_name) === normaliseIdentity(first) &&
        normaliseIdentity(r.last_name) === normaliseIdentity(last),
    )
  ) {
    return 'name'
  }
  return null
}

/** Message for the admin who hit the duplicate. Safe to return to the client. */
export function describeConflict(
  field: ConflictField,
  firstName?: string,
  lastName?: string,
): string {
  switch (field) {
    case 'university_id':
      return 'Duplicate: this University ID already belongs to another account.'
    case 'email':
      return 'Duplicate: this email address already belongs to another account.'
    case 'name': {
      const full = `${cleanIdentity(firstName)} ${cleanIdentity(lastName)}`.trim()
      return full
        ? `Duplicate: an account for "${full}" already exists. A first name or a ` +
          `last name may be shared, but not both.`
        : 'Duplicate: an account with that exact first and last name already exists.'
    }
  }
}

/**
 * Recognises a unique-index violation raised by the database and returns the
 * matching message, or null if the error is something else.
 *
 * This is the race path: two admins submit the same person at the same instant,
 * both pre-flight checks pass, and the database rejects the second insert.
 */
export function describeUniqueViolation(error: any): string | null {
  const raw = `${error?.code ?? ''} ${error?.message ?? ''} ${error?.details ?? ''}`
  if (!raw.includes('23505') && !raw.includes('duplicate key value')) return null

  if (raw.includes('user_info_university_id_unique_idx')) return describeConflict('university_id')
  if (raw.includes('user_info_email_unique_idx')) return describeConflict('email')
  if (raw.includes('user_info_full_name_unique_idx')) return describeConflict('name')
  return null
}

/**
 * Recognises "that email already has an auth account".
 *
 * Supabase Auth keeps its own unique index on auth.users.email, and it is never
 * released -- not even by the soft delete in the delete-user function, which
 * only bans the account. So an email can be free in user_info yet still taken
 * here, and the raw error ("A user with this email address has already been
 * registered") is not something to show an admin verbatim.
 */
export function describeAuthEmailTaken(error: any): string | null {
  const raw = `${error?.code ?? ''} ${error?.message ?? ''}`.toLowerCase()
  const taken =
    raw.includes('already been registered') ||
    raw.includes('already registered') ||
    raw.includes('email_exists') ||
    (raw.includes('duplicate') && raw.includes('email'))
  if (!taken) return null
  return 'Duplicate: this email address already has an account. If the person ' +
    'was previously removed, their login still holds that address -- restore ' +
    'that account instead of creating a new one.'
}

/**
 * Deletes a just-created auth user after a later step failed.
 *
 * Without this, a failed user_info insert leaves an account in auth.users with
 * no profile row: invisible in every admin list, yet still holding that email,
 * so nobody can ever register it again. Failures here are logged and swallowed
 * -- the caller is already reporting a more useful error.
 */
export async function rollbackAuthUser(supabaseAdmin: any, userId: string): Promise<void> {
  try {
    await supabaseAdmin.auth.admin.deleteUser(userId)
    console.log(`[identity_guard] Rolled back orphaned auth user ${userId}`)
  } catch (e) {
    console.error(`[identity_guard] Could not roll back auth user ${userId}:`, e)
  }
}
