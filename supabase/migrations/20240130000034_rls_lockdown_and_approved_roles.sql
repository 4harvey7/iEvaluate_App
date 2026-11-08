-- ============================================================================
-- 20240130000034_rls_lockdown_and_approved_roles.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`
-- (same as every migration from 000002 on).
--
-- REQUIRES (applied first):
--   * 20240130000028_intervention_reports_rls_and_emailed_at.sql
--     It drops the five dashboard-made intervention_reports write policies
--     ("Deans create interventions", "interventions: dean can update status",
--     "Deans manage interventions", "Deans can manage department reports",
--     "interventions: dean can insert") and adds emailed_at, which
--     send-intervention-email needs. Step 0 below aborts if it is missing.
--
-- SUPERSEDES (do NOT apply these separately):
--   * 20240130000023_user_info_read_scope.sql -- its STEP 0 (drop the open
--     policy) is done here by name; its STEP 2 (heads read via
--     instructor_departments) is recreated here with the approval check; its
--     STEP 1 ("SAO office reads all profiles") is NOT wanted: it would give a
--     pending SAO_STAFF read-all. "user_info: sao reads all" (is_sao()) covers
--     the SAO screens.
--   * The "should be narrowed" note in 20240130000008 section 4.
--
-- WHAT IT DOES
--   1. user_info: drops every unscoped / unapproved SELECT policy, adds the
--      login RPC get_login_email(text), revokes anon writes.
--   2. instructor_ai_suggestions, instructor_summaries, instructor_wordcloud,
--      student_remarks: drops the USING/WITH CHECK (true) write policies and
--      the open summaries read. The app only reads these tables; n8n writes
--      them through its Postgres connection, which bypasses RLS.
--   3. is_sao(), is_dean(), is_dept_head(): also require an approved account.
--
-- Safe to run more than once. One transaction.
-- ============================================================================

begin;

-- ── 0. Preconditions ────────────────────────────────────────────────────────
do $pre$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'intervention_reports'
      and column_name = 'emailed_at'
  ) or exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'intervention_reports'
      and policyname in ('Deans can manage department reports',
                         'Deans manage interventions',
                         'Deans create interventions',
                         'interventions: dean can insert',
                         'interventions: dean can update status')
  ) then
    raise exception 'Apply migration 20240130000028 first.';
  end if;
end
$pre$;


-- ── 1. Role helpers: a role row is not enough, the account must be approved ─
-- A pending registration can self-insert into Sao_users (SAO_STAFF) or
-- department_table (DEPARTMENT_HEAD) -- see protect_sao_users_insert and
-- guard_department_table_self_insert. Before, these helpers handed that
-- pending account the role's RLS powers; only Dart signIn() stood in the way.
-- Same approval test as is_approved_sao_admin().
create or replace function public.is_sao()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public."Sao_users" su
    join public.user_info ui on ui.id = su.user_id
    where su.user_id = auth.uid()
      and lower(btrim(coalesce(ui.account_status, ''))) = 'approved'
      and coalesce(ui.disabled, false) = false
  );
$$;

create or replace function public.is_dean()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.department_table dt
    join public.roles r      on r.id = dt.roles
    join public.user_info ui on ui.id = dt.user_id
    where dt.user_id = auth.uid()
      and upper(r."Roles") in ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
      and lower(btrim(coalesce(ui.account_status, ''))) = 'approved'
      and coalesce(ui.disabled, false) = false
  );
$$;

create or replace function public.is_dept_head()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.department_table dt
    join public.roles r      on r.id = dt.roles
    join public.user_info ui on ui.id = dt.user_id
    where dt.user_id = auth.uid()
      and upper(r."Roles") in ('DEPARTMENT-HEAD', 'DEPARTMENT_HEAD', 'DEAN')
      and lower(btrim(coalesce(ui.account_status, ''))) = 'approved'
      and coalesce(ui.disabled, false) = false
  );
$$;


-- ── 2. user_info: login lookup without reading the table ────────────────────
-- Login by university ID has to turn the ID into an email before
-- signInWithPassword. That was a direct anon SELECT, allowed by
-- "Allow anonymous email lookup" USING (true) -- which exposed every row.
-- This returns the email for one exact ID (case-insensitive, oldest account
-- first, as the old query did) and nothing else.
-- It cannot be a boolean: signInWithPassword needs the address itself.
create or replace function public.get_login_email(p_university_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select ui.email
  from public.user_info ui
  where nullif(btrim(p_university_id), '') is not null
    and lower(btrim(ui.university_id)) = lower(btrim(p_university_id))
  order by ui.created_at asc
  limit 1;
$$;

comment on function public.get_login_email(text) is
  'Login-by-ID: email for one exact university ID, or NULL. Replaces the anon '
  'USING (true) SELECT on user_info.';

revoke all on function public.get_login_email(text) from public;
grant execute on function public.get_login_email(text) to anon, authenticated, service_role;


-- ── 3. user_info: SELECT policies ───────────────────────────────────────────
-- Dropped: readable by anyone / any signed-in user.
drop policy if exists "Allow anonymous email lookup"          on public.user_info;
drop policy if exists "Authenticated users can view profiles" on public.user_info;
-- Dropped: any member of a department (instructors included, no role check)
-- could read every profile in it.
drop policy if exists "Deans can view faculty profiles"       on public.user_info;
-- Dropped: role checked without approval. Replaced by the is_sao() /
-- is_dept_head() policies, which now require an approved account.
drop policy if exists "Deans view department faculty"         on public.user_info;
drop policy if exists "Admins can view all profiles"          on public.user_info;
drop policy if exists "SAO office reads all profiles"         on public.user_info;  -- migration 23 step 1

-- Kept as they are: the own-row policies, "user_info: sao reads all"
-- (is_sao()), "user_info: dept head reads dept members" (is_dept_head() +
-- department_table).

-- The faculty roster lists instructors through instructor_departments, which
-- can disagree with department_table (migration 06). From migration 23 step 2.
drop policy if exists "Heads read their department profiles" on public.user_info;
create policy "Heads read their department profiles"
  on public.user_info for select to authenticated
  using (
    public.is_dept_head()
    and exists (
      select 1
      from public.instructor_departments target
      join public.department_table caller
        on caller."Department_name_ID" = target.department_id
      where target.instructor_id = user_info.id
        and caller.user_id = auth.uid()
    )
  );

-- Instructor dashboard shows the name of the head who filed an intervention
-- (instructor_dashboard.dart, user_info!dean_id join).
drop policy if exists "Instructors read the head who filed their report" on public.user_info;
create policy "Instructors read the head who filed their report"
  on public.user_info for select to authenticated
  using (
    exists (
      select 1 from public.intervention_reports ir
      where ir.dean_id = user_info.id
        and ir.instructor_id = auth.uid()
    )
  );

-- anon never writes user_info (signup inserts with the new user's session).
revoke insert, update, delete, truncate on public.user_info from anon;


-- ── 4. AI output tables: no client writes ───────────────────────────────────
drop policy if exists "allow_insert_ai_suggestions" on public.instructor_ai_suggestions;
drop policy if exists "allow_update_ai_suggestions" on public.instructor_ai_suggestions;
drop policy if exists "allow_insert_summaries"      on public.instructor_summaries;
drop policy if exists "allow_update_summaries"      on public.instructor_summaries;
-- No screen reads instructor_summaries, so no replacement SELECT policy.
drop policy if exists "allow_view_summaries"        on public.instructor_summaries;
drop policy if exists "allow_insert"                on public.instructor_wordcloud;
drop policy if exists "allow_update"                on public.instructor_wordcloud;
drop policy if exists "allow_insert_remarks"        on public.student_remarks;

revoke insert, update, delete, truncate on public.instructor_ai_suggestions from anon;
revoke insert, update, delete, truncate on public.instructor_summaries      from anon;
revoke insert, update, delete, truncate on public.instructor_wordcloud      from anon;
revoke insert, update, delete, truncate on public.student_remarks           from anon;


-- ── 5. Final check: no open policy left on these tables ─────────────────────
do $chk$
declare
  v_open text;
begin
  select string_agg(format('%s."%s" (%s)', tablename, policyname, cmd), ', ')
    into v_open
  from pg_policies
  where schemaname = 'public'
    and tablename in ('user_info', 'instructor_ai_suggestions',
                      'instructor_summaries', 'instructor_wordcloud',
                      'student_remarks')
    and (coalesce(qual, '') = 'true' or coalesce(with_check, '') = 'true');

  if v_open is not null then
    raise exception 'Not applied: open policies remain: %', v_open;
  end if;
end
$chk$;

commit;


-- == Verification (run afterwards) ===========================================
-- 1. As anon (no session):  select count(*) from user_info;        -> 0
--    select get_login_email('<a real ID>');                        -> its email
-- 2. As an ordinary instructor:  select count(*) from user_info;   -> 1 (+ the
--    head who filed a report on them, if any)
-- 3. SAO admin: User Management lists everyone. Head: faculty roster loads.
-- 4. A pending SAO_STAFF / head:  select is_sao(), is_dept_head(); -> false
-- ============================================================================
