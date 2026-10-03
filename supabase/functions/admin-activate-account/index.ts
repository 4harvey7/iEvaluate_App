// supabase/functions/admin-activate-account/index.ts
//
// SAO admin only: approve a pending account that cannot simply be approved,
// because it has no real login email yet. The admin supplies ONLY that email.
//
// WHO NEEDS THIS
// Instructors added during batch scanning (the website's "add instructor"
// step) get a placeholder login -- `placeholder-<uuid>@ievaluate.internal`,
// banned in Auth, account_status 'pending'. They show up in the dashboard's
// Pending Approvals like any other signup, and the one-tap approve
// (admin-accept-user) would leave them with an address nobody can receive mail
// at. A missing university_id / address is NOT collected here: the person is
// asked for it by the app's mandatory post-login "Complete your information"
// dialog, and the email below tells them so.
//
// WHAT IT DOES (same account id throughout, so every batch, scan and result
// already tied to this person stays theirs -- same rule as the website's
// /activate page, routers/instructors.py activate_instructor)
//   1. checks the caller is SAO_ADMIN
//   2. validates the real email with the shared identity rules and refuses
//      one that already belongs to another account
//   3. Auth: sets the real email (confirmed -- the admin verified the person)
//      and clears the placeholder's ban
//   4. user_info: email, account_status 'approved'
//      (and is_placeholder / disabled from the website migration, when those
//      columns exist), reverting Auth if this step fails
//   5. emails the person their login and how to set a password (Forgot
//      Password in the app, which emails them a one-time code)
//   6. writes an ACCOUNT_ACTIVATED audit row
//
// Service role is required: trg_protect_user_info_fields (migrations 26/27)
// refuses email changes from anyone else, and the Auth email can only be
// changed for another user with the admin API.

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'
import {
  cleanEmail,
  cleanIdentity,
  describeAuthEmailTaken,
  describeConflict,
  describeUniqueViolation,
  findIdentityConflict,
  validateIdentityFormat,
} from '../_shared/identity_guard.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** How delete-user / admin-accept-user lock an account in Auth. */
const BAN_DURATION = '87600h'

/** Prefix the app recognises as "someone already activated this account". */
const ALREADY_ACTIVE_PREFIX = 'Already activated'

/**
 * A login nobody can receive mail at: blank, or the website's
 * `placeholder-<uuid>@ievaluate.internal`. Must agree with
 * AccountActivationService.isPlaceholderEmail in the app.
 */
function isPlaceholderEmail(value: unknown): boolean {
  const email = cleanEmail(value)
  if (!email) return true
  const [local, domain = ''] = email.split('@')
  return local.startsWith('placeholder-') || domain === 'ievaluate.internal'
}

function isBlank(value: unknown): boolean {
  return value === null || value === undefined || cleanIdentity(String(value)) === ''
}

/** The to-one embed comes back as an object or a one-element array. */
function embedded(value: unknown): any {
  return Array.isArray(value) ? value[0] : value
}

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

/** Auth's own "that is not an email" rejection, reworded for the admin. */
function describeAuthEmailInvalid(error: any): string | null {
  const raw = `${error?.code ?? ''} ${error?.message ?? ''}`.toLowerCase()
  if (raw.includes('email_address_invalid') || raw.includes('invalid email') ||
      raw.includes('unable to validate email')) {
    return 'Invalid input: Enter a valid email address'
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    // ── Authenticate the caller ─────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── SAO admin only ──────────────────────────────────────────────────────
    // maybeSingle: a caller absent from Sao_users is a refusal, not a crash.
    const { data: adminRow } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .maybeSingle()
    if (embedded(adminRow?.roles)?.Roles !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

    const {
      targetUserId,
      email: rawEmail,
    } = await req.json()

    if (!targetUserId || typeof targetUserId !== 'string') {
      throw new Error('Invalid input: missing target user')
    }
    if (targetUserId === caller.id) {
      throw new Error('Invalid input: you cannot activate your own account.')
    }

    // ── Format ──────────────────────────────────────────────────────────────
    const formatError = validateIdentityFormat({ email: rawEmail })
    if (formatError) throw new Error(`Invalid input: ${formatError}`)

    const newEmail = cleanEmail(rawEmail)
    if (isPlaceholderEmail(newEmail)) {
      throw new Error("Invalid input: enter the person's real email address, not the placeholder.")
    }

    // ── The account being activated ─────────────────────────────────────────
    // select('*') rather than a column list: is_placeholder / disabled come
    // from the website's migration and may not exist on this project. Naming
    // them would fail the whole read; '*' tells us whether they are there.
    const { data: target, error: targetError } = await supabaseAdmin
      .from('user_info')
      .select('*')
      .eq('id', targetUserId)
      .maybeSingle()
    if (targetError) throw targetError
    if (!target) throw new Error('Invalid input: user not found')

    const status = String(target.account_status ?? '').toLowerCase()
    if (status === 'deleted') {
      throw new Error('Invalid input: this account was removed and cannot be activated.')
    }

    const oldEmail: string | null = target.email ?? null
    const wasPlaceholder = target.is_placeholder === true || isPlaceholderEmail(oldEmail)
    // Only used for the email wording: the person fills these in after login.
    const missingId = isBlank(target.university_id)
    const missingAddress = isBlank(target.address)

    // Already activated: approved with a real email. Two admins working the
    // same list, or a stale screen.
    if (status === 'approved' && !wasPlaceholder) {
      throw new Error(`${ALREADY_ACTIVE_PREFIX}: this account already has its own login and is approved. Refresh the list.`)
    }

    const emailChanged = newEmail !== cleanEmail(oldEmail ?? '')

    // ── Duplicates, before Auth is touched ──────────────────────────────────
    const conflict = await findIdentityConflict(supabaseAdmin, {
      ...(emailChanged ? { email: newEmail } : {}),
      excludeUserId: targetUserId,
    })
    if (conflict) throw new Error(describeConflict(conflict))

    // ── Auth: real email + clear the placeholder ban ────────────────────────
    // Read first so a failure further down can put the ban back exactly as it
    // was, rather than guessing.
    const { data: authBefore, error: authReadError } =
      await supabaseAdmin.auth.admin.getUserById(targetUserId)
    if (authReadError || !authBefore?.user) {
      console.error('[admin-activate-account] Auth user not found:', authReadError)
      throw new Error('Invalid input: this account has no login record. Please contact support.')
    }
    const authEmailBefore: string | null = authBefore.user.email ?? oldEmail
    const bannedUntil = authBefore.user.banned_until
    const wasBanned = !!bannedUntil && new Date(bannedUntil) > new Date()

    const authUpdate: Record<string, unknown> = { ban_duration: 'none' }
    if (emailChanged || cleanEmail(authEmailBefore ?? '') !== newEmail) {
      // email_confirm: the admin verified the person and the address in person.
      authUpdate.email = newEmail
      authUpdate.email_confirm = true
    }
    const { error: authError } =
      await supabaseAdmin.auth.admin.updateUserById(targetUserId, authUpdate)
    if (authError) {
      const msg = describeAuthEmailTaken(authError) ?? describeAuthEmailInvalid(authError)
      if (msg) throw new Error(msg)
      console.error('[admin-activate-account] Auth update failed:', authError)
      throw new Error('Operation failed: could not update the login account.')
    }

    /** Puts Auth back the way it was. Logged and swallowed. */
    const revertAuth = async (emailToRestore: string | null) => {
      const revert: Record<string, unknown> = {}
      if (authUpdate.email && emailToRestore) {
        revert.email = emailToRestore
        revert.email_confirm = true
      }
      if (wasBanned) revert.ban_duration = BAN_DURATION
      if (Object.keys(revert).length === 0) return
      const { error } = await supabaseAdmin.auth.admin.updateUserById(targetUserId, revert)
      if (error) console.error('[admin-activate-account] Could not revert Auth:', error)
    }

    // ── user_info ───────────────────────────────────────────────────────────
    const profileUpdate: Record<string, unknown> = { account_status: 'approved' }
    if (emailChanged) profileUpdate.email = newEmail
    if ('is_placeholder' in target) profileUpdate.is_placeholder = false
    if ('disabled' in target) profileUpdate.disabled = false

    // Conditional on the status read above, so a second admin activating the
    // same person at the same moment matches zero rows instead of overwriting.
    let profileQuery = supabaseAdmin.from('user_info').update(profileUpdate).eq('id', targetUserId)
    profileQuery = target.account_status === null || target.account_status === undefined
      ? profileQuery.is('account_status', null)
      : profileQuery.eq('account_status', target.account_status)
    const { data: updatedRows, error: updateError } = await profileQuery.select('id')

    if (updateError) {
      await revertAuth(authEmailBefore)
      const dup = describeUniqueViolation(updateError)
      throw dup ? new Error(dup) : updateError
    }
    if (!updatedRows || updatedRows.length === 0) {
      // Lost the race. Keep Auth agreeing with whatever user_info now says.
      const { data: current } = await supabaseAdmin
        .from('user_info').select('email').eq('id', targetUserId).maybeSingle()
      await revertAuth(current?.email ?? authEmailBefore)
      throw new Error(`${ALREADY_ACTIVE_PREFIX}: another admin changed this account a moment ago. Refresh the list.`)
    }

    // ── 📧 Notify User via Brevo ────────────────────────────────────────────
    // Same conventions as the other account emails (admin-accept-user,
    // admin-update-role, admin-create-*): Brevo's SMTP API, secrets
    // BREVO_API_KEY + BREVO_SENDER_EMAIL, sender "SAO Management", and the
    // plain "Hello, <name>!" / "Best regards, SAO Management Team" template.
    //
    //   * real email already on file (the app does not route these here, but
    //     the endpoint accepts them): exactly the "Account Approved!" email
    //     admin-accept-user sends, since this IS that approval.
    //   * placeholder login: the same template, saying the SAO admin activated
    //     the account and how to set a password. Steps rather than a link:
    //     admin-create-user's generateLink('recovery') link opens a browser,
    //     while the app's reset is deliberately in-app (Forgot Password? ->
    //     emailed code, auth_service.sendPasswordResetCode) and never expires.
    //
    // ONE DELIBERATE DIFFERENCE: the other functions throw when the sender is
    // not configured and never check Brevo's reply. Here the account has
    // already been activated by this point, so a mail failure is logged the way
    // send-admin-code logs it and reported back (emailSent: false) for the
    // admin to pass the steps on in person -- it does not turn a completed
    // activation into a red error.
    const needsPasswordSetup = wasPlaceholder || emailChanged
    const firstName = escapeHtml(cleanIdentity(target.first_name) || 'there')
    const loginEmail = escapeHtml(newEmail)
    const missingDetails = [
      missingId ? 'ID' : null,
      missingAddress ? 'address' : null,
    ].filter(Boolean).join(' and ')
    const completeNote = missingDetails
      ? `<p>After you sign in, the app will ask you to complete your ${missingDetails}.</p>`
      : ''

    const subject = needsPasswordSetup
      ? 'Account Activated — Set Your Password'
      : 'Account Approved!'
    const htmlContent = needsPasswordSetup
      ? `
          <h3>Hello, ${firstName}!</h3>
          <p>Your iEvaluate account has been <b>activated by the SAO admin</b>. Your evaluation records are already linked to it.</p>
          <p><b>Your login email:</b> ${loginEmail}</p>
          <p><b>To set your password:</b></p>
          <ol>
            <li>Open the iEvaluate app.</li>
            <li>Tap <b>Forgot Password?</b> on the login screen.</li>
            <li>Enter <b>${loginEmail}</b> and tap <b>Send Code</b>.</li>
            <li>Type the code we email you, then choose your new password.</li>
          </ol>
          ${completeNote}
          <p>If you did not expect this email, please contact the SAO office immediately.</p>
          <p>Best regards,<br>SAO Management Team</p>
        `
      // Wording copied from admin-accept-user's approval email.
      : `
          <h3>Hello, ${firstName}!</h3>
          <p>Your account status has been updated to: <b>APPROVED</b>.</p>
          <p>Your registration has been approved. You can now log in to the iEvaluate app.</p>
          ${completeNote}
          <p>Best regards,<br>SAO Management Team</p>
        `

    let emailSent = false
    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!BREVO_KEY || !SENDER_EMAIL) {
      console.error('[admin-activate-account] BREVO_API_KEY / BREVO_SENDER_EMAIL is not set in Supabase secrets')
    } else {
      try {
        const res = await fetch('https://api.brevo.com/v3/smtp/email', {
          method: 'POST',
          headers: {
            'api-key': BREVO_KEY,
            'content-type': 'application/json',
            'accept': 'application/json',
          },
          body: JSON.stringify({
            sender: { name: 'SAO Management', email: SENDER_EMAIL },
            to: [{ email: newEmail }],
            subject,
            htmlContent,
          }),
        })
        emailSent = res.ok
        if (!res.ok) {
          const resData = await res.json().catch(() => null)
          console.error('Brevo API Error:', resData)
        }
      } catch (mailError) {
        console.error('Brevo API Error:', mailError)
      }
    }

    // ── Audit ───────────────────────────────────────────────────────────────
    const { error: auditError } = await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'ACCOUNT_ACTIVATED',
      // instructor_id / new_email are the keys the website's
      // instructor_account_activated entry uses, so one query finds both.
      metadata: {
        target_user: targetUserId,
        instructor_id: targetUserId,
        new_email: newEmail,
        previous_status: target.account_status ?? null,
        new_status: 'approved',
        was_placeholder: wasPlaceholder,
        email_changed: emailChanged,
        ...(emailChanged ? { old_email: oldEmail } : {}),
        auth_action: 'unbanned',
        // Same key admin-accept-user records; only an SAO admin reaches here.
        caller_role: 'sao_admin',
        email_sent: emailSent,
      },
    })
    if (auditError) console.error('[admin-activate-account] Audit insert failed:', auditError)

    return new Response(JSON.stringify({
      message: 'Account activated',
      email: newEmail,
      emailChanged,
      wasPlaceholder,
      passwordSetupRequired: needsPasswordSetup,
      emailSent,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    // Only known-safe messages reach the admin verbatim.
    const safePrefixes = [
      'Unauthorized', 'Forbidden', 'Invalid input', 'Duplicate',
      ALREADY_ACTIVE_PREFIX, 'Operation failed:',
    ]
    const message = (error as any)?.message as string | undefined
    const safeMessage = safePrefixes.some(p => message?.startsWith(p))
      ? message
      : 'Operation failed. Please try again.'
    const status = message?.startsWith('Unauthorized') ? 401
      : message?.startsWith('Forbidden') ? 403
      : message?.startsWith(ALREADY_ACTIVE_PREFIX) || message?.startsWith('Duplicate') ? 409
      : 400
    return new Response(JSON.stringify({ error: safeMessage }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status,
    })
  }
})
