// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'
import { isDepartmentHeadRole } from '../_shared/department_head_guard.ts'
import { escapeHtml, escapeMultiline } from '../_shared/html.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// WHO MAY CALL THIS
//
// The only caller is EvaluationService.createIntervention, reached only from
// InterventionReportsScreen, which role_nav_config puts in the dept-head
// navigation alone (DEPARTMENT_HEAD / DEPARTMENT-HEAD / DEAN). SAO_ADMIN has
// no route to it, so SAO_ADMIN is NOT allowed here either.
//
// This used to run with verify_jwt = false and no check at all, trusting the
// request body for the recipient, the dean's name and the email's text. Anyone
// with the publishable key and an instructor's UUID could send an "Official
// Intervention Notice" in any dean's name with arbitrary HTML. Now:
//   1. the caller must be a signed-in user (the bare anon key has no user),
//   2. the caller must be an approved department head,
//   3. the instructor must be in the caller's department (same rule the faculty
//      roster and the alert list use: instructor_departments, is_primary),
//   4. the email is built only from the intervention_reports row in the
//      database, which must belong to the caller (dean_id), be 'Pending', and
//      be less than RECENT_WINDOW_MS old,
//   5. each report is emailed at most once: the send is claimed atomically by
//      setting intervention_reports.emailed_at (migration 000028). audit_logs
//      still gets a row, but only as a record.

/** Only reports created this recently can trigger an email. */
const RECENT_WINDOW_MS = 10 * 60 * 1000

/** audit_logs action recorded after a report is emailed (record only, not the lock). */
const SENT_ACTION = 'INTERVENTION_EMAIL_SENT'

/** A PostgREST embed is an object for to-one, an array when it cannot tell. */
function embedded(value: unknown): any {
  return Array.isArray(value) ? value[0] : value
}

/** A thrown error that maps to a fixed HTTP status and a generic message. */
class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    if (req.method !== 'POST') throw new HttpError(405, 'Method not allowed')

    const supabaseAdmin = createAdminClient()

    // ── 1. Authenticate ────────────────────────────────────────────────────
    // getUser() resolves a real user session only. The publishable/anon key is
    // also a JWT, but it carries no user, so it fails here.
    const authHeader = req.headers.get('Authorization') ?? ''
    const token = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!token) throw new HttpError(401, 'Unauthorized')

    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token)
    const caller = userData?.user
    if (userError || !caller?.id) throw new HttpError(401, 'Unauthorized')

    // ── 2. Authorise: approved department head ─────────────────────────────
    const { data: callerInfo } = await supabaseAdmin
      .from('user_info')
      .select('first_name, last_name, account_status')
      .eq('id', caller.id)
      .maybeSingle()
    // Same gate signIn() applies: only 'approved' accounts may use the app.
    if (String(callerInfo?.account_status ?? '').toLowerCase() !== 'approved') {
      throw new HttpError(403, 'Forbidden')
    }

    const { data: callerDept } = await supabaseAdmin
      .from('department_table')
      .select('Department_name_ID, roles:roles(Roles)')
      .eq('user_id', caller.id)
      .maybeSingle()
    const callerDeptId = callerDept?.Department_name_ID
    if (
      !isDepartmentHeadRole(embedded(callerDept?.roles)?.Roles) ||
      callerDeptId === null || callerDeptId === undefined
    ) {
      throw new HttpError(403, 'Forbidden')
    }

    // ── 3. Load the real report row; never trust the body's content ────────
    let body: any = {}
    try {
      body = await req.json()
    } catch {
      throw new HttpError(400, 'Invalid request')
    }

    const cutoff = new Date(Date.now() - RECENT_WINDOW_MS).toISOString()
    const columns = 'id, instructor_id, dean_id, action_type, notes, status, created_at'
    let report: any = null

    const reportId = body?.report_id
    if (reportId !== undefined && reportId !== null && reportId !== '') {
      // Current app: the id of the row it just inserted.
      if (!/^\d+$/.test(String(reportId))) throw new HttpError(400, 'Invalid request')
      const { data, error } = await supabaseAdmin
        .from('intervention_reports')
        .select(columns)
        .eq('id', String(reportId))
        .maybeSingle()
      if (error) throw error
      report = data
    } else {
      // Older app versions send only { record: {...} }. Use it as a lookup key
      // only: the newest matching row this caller filed in the last few minutes.
      const record = body?.record
      const instructorId = typeof record?.instructor_id === 'string' ? record.instructor_id : ''
      if (!instructorId) throw new HttpError(400, 'Invalid request')
      if (record?.dean_id && record.dean_id !== caller.id) throw new HttpError(403, 'Forbidden')

      const { data, error } = await supabaseAdmin
        .from('intervention_reports')
        .select(columns)
        .eq('instructor_id', instructorId)
        .eq('dean_id', caller.id)
        .eq('status', 'Pending')
        .gte('created_at', cutoff)
        .order('created_at', { ascending: false })
        .limit(1)
      if (error) throw error
      report = data && data.length > 0 ? data[0] : null
    }

    if (!report) throw new HttpError(404, 'Not found')

    // Only the dean who filed it, only while Pending, only while fresh.
    if (report.dean_id !== caller.id) throw new HttpError(403, 'Forbidden')
    if (report.status !== 'Pending') throw new HttpError(404, 'Not found')
    const createdAt = Date.parse(report.created_at ?? '')
    if (!Number.isFinite(createdAt) || createdAt < Date.parse(cutoff)) {
      throw new HttpError(404, 'Not found')
    }
    if (report.instructor_id === caller.id) throw new HttpError(403, 'Forbidden')

    // ── 4. The instructor must be in the caller's department ───────────────
    // The RLS insert policy (migration 000028) enforces the same rule; this is
    // kept as defence in depth, since the function runs with the service role.
    const { data: memberRows, error: memberError } = await supabaseAdmin
      .from('instructor_departments')
      .select('department_id')
      .eq('instructor_id', report.instructor_id)
      .eq('is_primary', true)
    if (memberError) throw memberError
    const sameDepartment = (memberRows ?? []).some(
      (row: any) => String(row.department_id) === String(callerDeptId),
    )
    if (!sameDepartment) throw new HttpError(403, 'Forbidden')

    // ── 5. Recipient and names from the database ───────────────────────────
    // Everything that can fail without sending is done BEFORE the claim, so a
    // missing email address or missing secret never leaves a report marked as
    // emailed.
    const { data: instructor } = await supabaseAdmin
      .from('user_info')
      .select('email, first_name, last_name')
      .eq('id', report.instructor_id)
      .maybeSingle()

    if (!instructor?.email) throw new HttpError(404, 'Not found')

    const deanFullName = `${callerInfo?.first_name ?? ''} ${callerInfo?.last_name ?? ''}`.trim()
    const deanName = escapeHtml(deanFullName || 'Your Department Head')
    const instructorFirstName = escapeHtml(instructor.first_name || 'Instructor')
    const actionType = escapeHtml(report.action_type || 'N/A')
    const notes = report.notes
      ? escapeMultiline(report.notes)
      : 'No additional notes provided.'
    const status = escapeHtml(report.status || 'Active Tracking')

    const BREVO_KEY = Deno.env.get('BREVO_API_KEY')
    const SENDER_EMAIL = Deno.env.get('BREVO_SENDER_EMAIL')
    if (!BREVO_KEY || !SENDER_EMAIL) {
      throw new Error('BREVO_API_KEY / BREVO_SENDER_EMAIL is not set in Supabase secrets')
    }

    // ── 6. Claim the send: at most one email per report ────────────────────
    // One conditional UPDATE. Postgres runs it atomically, so when two
    // requests for the same report arrive together only one finds emailed_at
    // still null and gets the row back; the other gets nothing and stops.
    const { data: claimed, error: claimError } = await supabaseAdmin
      .from('intervention_reports')
      .update({ emailed_at: new Date().toISOString() })
      .eq('id', report.id)
      .is('emailed_at', null)
      .select('id')
    if (claimError) throw claimError
    if (!claimed || claimed.length === 0) {
      return json({ message: 'Email already sent' }, 200)
    }

    // ── 7. Send via Brevo; give the claim back if it fails ─────────────────
    try {
      const res = await fetch('https://api.brevo.com/v3/smtp/email', {
        method: 'POST',
        headers: {
          'api-key': BREVO_KEY,
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: JSON.stringify({
          sender: { name: 'iEvaluate System', email: SENDER_EMAIL },
          to: [{ email: instructor.email }],
          subject: '⚠️ Official Notice: Intervention Report Issued',
          htmlContent: `
            <div style="font-family: sans-serif; max-width: 600px; margin: auto; padding: 24px; border: 1px solid #f0f0f0; border-radius: 12px;">
              <div style="background: #e53e3e; border-radius: 8px; padding: 16px; text-align: center; margin-bottom: 24px;">
                <h2 style="color: white; margin: 0;">⚠️ Official Intervention Notice</h2>
              </div>

              <p style="color: #333;">Dear <strong>${instructorFirstName}</strong>,</p>

              <p style="color: #333;">
                Your department head, <strong>${deanName}</strong>, has issued an official intervention report
                regarding your recent evaluation results. This is an action that requires your attention.
              </p>

              <div style="background: #fff5f5; border-left: 4px solid #e53e3e; padding: 16px; border-radius: 4px; margin: 20px 0;">
                <p style="margin: 0 0 8px 0;"><strong>Action Required:</strong> ${actionType}</p>
                <p style="margin: 0 0 8px 0;"><strong>Notes:</strong> ${notes}</p>
                <p style="margin: 0; color: #666; font-size: 13px;">Status: ${status}</p>
              </div>

              <p style="color: #333;">
                Please log in to the <strong>iEvaluate app</strong> to view the full details of this notice
                on your dashboard.
              </p>

              <p style="color: #999; font-size: 12px; margin-top: 32px; border-top: 1px solid #f0f0f0; padding-top: 16px;">
                This is an automated message from the iEvaluate System.
                This notice can only be removed by your department head once resolved.
              </p>
            </div>
          `,
        }),
      })

      if (!res.ok) {
        const resData = await res.json().catch(() => ({}))
        console.error('Brevo API Error:', res.status, resData)
        throw new Error('Email provider rejected the request')
      }
    } catch (sendError) {
      // Release the claim so a later call can retry. Only this request holds
      // the claim right now, so clearing by id is safe.
      const { error: releaseError } = await supabaseAdmin
        .from('intervention_reports')
        .update({ emailed_at: null })
        .eq('id', report.id)
      if (releaseError) {
        console.error('send-intervention-email: could not release claim:', releaseError)
      }
      throw sendError
    }

    // Record only. The lock is emailed_at above, not this row.
    const { error: logError } = await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: SENT_ACTION,
      metadata: { report_id: String(report.id), instructor_id: report.instructor_id },
    })
    if (logError) console.error('send-intervention-email audit log failed:', logError)

    console.log(`Intervention email sent for report ${report.id}`)
    return json({ message: 'Email sent successfully' }, 200)

  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status)
    }
    // Details stay in the function log; the client gets a generic message.
    console.error('send-intervention-email error:', error)
    return json({ error: 'Could not send the notification email' }, 500)
  }
})
