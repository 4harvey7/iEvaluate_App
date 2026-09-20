// supabase/functions/admin-reject-pending/index.ts
//
// Fully deletes a PENDING account: auth.users + all DB rows.
// Only SAO_ADMIN can call this. The auth user is deleted (not banned)
// so the email is freed and the person can sign up again if needed.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createAdminClient } from '../_shared/admin_client.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createAdminClient()

    // ── Authenticate caller ──────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } =
      await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    // ── Verify caller is SAO_ADMIN ───────────────────────────────────────────
    const { data: adminRow } = await supabaseAdmin
      .from('Sao_users')
      .select('roles!inner(Roles)')
      .eq('user_id', caller.id)
      .maybeSingle()

    const role = Array.isArray(adminRow?.roles)
      ? adminRow?.roles[0]?.Roles
      : adminRow?.roles?.Roles
    if (role !== 'SAO_ADMIN') {
      throw new Error('Forbidden: Admin access required')
    }

    // ── Get target user ──────────────────────────────────────────────────────
    const { targetUserId } = await req.json()
    if (!targetUserId || typeof targetUserId !== 'string') {
      throw new Error('Invalid input: missing target user')
    }

    // ── Verify target is actually pending ─────────────────────────────────────
    const { data: targetUser, error: lookupError } = await supabaseAdmin
      .from('user_info')
      .select('account_status, first_name, last_name, email')
      .eq('id', targetUserId)
      .maybeSingle()

    if (lookupError) throw lookupError
    if (!targetUser) throw new Error('User not found')
    if (targetUser.account_status !== 'pending') {
      throw new Error('This action is only allowed for pending accounts. Use the status toggle for active accounts.')
    }

    // ── Step 1: Delete all DB rows (service role bypasses RLS) ───────────────
    // Order matters: FK children first, then the parent.
    try { await supabaseAdmin.from('instructor_departments').delete().eq('instructor_id', targetUserId) } catch (_) {}
    try { await supabaseAdmin.from('department_table').delete().eq('user_id', targetUserId) } catch (_) {}
    try { await supabaseAdmin.from('Sao_users').delete().eq('user_id', targetUserId) } catch (_) {}
    await supabaseAdmin.from('user_info').delete().eq('id', targetUserId)

    // ── Step 2: Fully delete from auth.users ─────────────────────────────────
    // This frees the email so the person can sign up again if they want to.
    const { error: authDeleteError } = await supabaseAdmin.auth.admin.deleteUser(targetUserId)
    if (authDeleteError) {
      // DB rows are already gone; log the auth failure but don't fail the whole operation
      console.error(`[admin-reject-pending] auth.admin.deleteUser failed: ${authDeleteError.message}`)
    }

    // ── Step 3: Audit log ────────────────────────────────────────────────────
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'PENDING_ACCOUNT_REJECTED',
      metadata: {
        rejected_user: targetUserId,
        rejected_name: `${targetUser.first_name} ${targetUser.last_name}`,
        rejected_email: targetUser.email,
        auth_deleted: !authDeleteError,
      },
    })

    return new Response(JSON.stringify({
      message: 'Pending account fully deleted',
      auth_deleted: !authDeleteError,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    const safeMessages = ['Unauthorized', 'Forbidden', 'Invalid input', 'User not found', 'This action is only']
    const msg = safeMessages.some(m => error.message?.startsWith(m))
      ? error.message
      : 'Operation failed. Please try again.'

    return new Response(JSON.stringify({ error: msg }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: error.message?.startsWith('Unauthorized') ? 401 : 400,
    })
  }
})
