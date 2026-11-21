-- ============================================================================
-- 20240130000036_rls_approval_gate.sql   (security review 2026-11-21, H1 / F1)
--
-- RUN THIS IN THE SUPABASE SQL EDITOR (same as every migration from 000002 on),
-- on a Supabase branch / local stack FIRST. Requires 000034 (is_sao(),
-- is_dept_head(), is_approved_sao_staff(), is_approved_sao_admin()).
--
-- PROBLEM (H1)
--   Permissive RLS policies are OR-ed. About 30 older policies granted access
--   from bare "Sao_users" / department_table membership or a role name, with no
--   account_status check. A freshly signed-up, still PENDING account (which the
--   signup triggers deliberately let pick SAO_STAFF or DEPARTMENT_HEAD) could
--   therefore read every result, intervention, AI summary, audit log, scan
--   image, insert survey rows and DELETE raw survey rows (authenticated has
--   column SELECT on id + table DELETE, so the delete half was reachable).
--   A DISABLED SAO admin kept admin powers through is_sao_admin(), including
--   re-approving their own account through protect_user_info_fields().
--
-- RULE APPLIED
--   Approved, non-disabled accounts keep EXACTLY the access they had.
--   Pending / disabled accounts keep only their own rows.
--   * Policies that only duplicated an approved policy (is_sao(), ...) are
--     dropped.
--   * Every other role-based policy is recreated with the same expression,
--     AND-ed with public.is_approved_user(), and scoped TO authenticated
--     (it never matched anon: auth.uid() is null for anon).
--   * is_sao_admin(), check_is_sao_admin(), is_admin_check() and
--     eval_is_sao_office() now require an approved, non-disabled account.
--   * protect_user_info_fields() also protects disabled / is_admin.
--
-- Safe to run more than once (drop if exists / create or replace). One
-- transaction: any error rolls everything back.
--
-- ROLLBACK
--   Re-create the old policy texts (saved verbatim in
--   supabase/verify/036_rollback_old_policies.sql, generated from live
--   pg_policies on 2026-11-21) and the old function bodies (same file).
--   Only do this if approved users lose access you cannot otherwise explain.
-- ============================================================================

begin;

-- ── 0. Preconditions ────────────────────────────────────────────────────────
do $pre$
begin
  if to_regprocedure('public.is_approved_sao_staff()') is null
     or to_regprocedure('public.is_approved_sao_admin()') is null
     or to_regprocedure('public.is_sao()') is null
     or to_regprocedure('public.is_dept_head()') is null then
    raise exception 'Apply 20240130000034_rls_lockdown_and_approved_roles.sql first.';
  end if;
end
$pre$;

-- ── 1. Helpers ──────────────────────────────────────────────────────────────
create or replace function public.is_approved_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_info ui
    where ui.id = auth.uid()
      and lower(btrim(coalesce(ui.account_status, ''))) = 'approved'
      and coalesce(ui.disabled, false) = false
  );
$$;
comment on function public.is_approved_user() is
  'True when the caller''s account is approved and not disabled (036).';
revoke all on function public.is_approved_user() from public, anon;
grant execute on function public.is_approved_user() to authenticated, service_role;

-- Admin helpers: approval + not disabled (were role-only).
create or replace function public.is_sao_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.is_approved_sao_admin(); $$;

create or replace function public.check_is_sao_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.is_approved_sao_admin(); $$;

create or replace function public.is_admin_check()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.is_approved_sao_admin(); $$;

-- eval_* tables and the eval_response_comments view.
create or replace function public.eval_is_sao_office()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.is_approved_sao_staff(); $$;

-- ── 2. Drop policies that only duplicate an approved policy ─────────────────
-- Each "Sao_users membership" read below has an is_sao() twin
-- ("ots: sao reads all", "perf: sao reads all", ...). is_sao() = membership
-- AND approved AND not disabled, so approved SAO users see the same rows.
drop policy if exists "SAO admins can view all overall surveys"          on public.overall_total_survey;
drop policy if exists "SAO admins can view all performance results"      on public.performance_results;
drop policy if exists "SAO admins can view all management results"       on public.management_results;
drop policy if exists "SAO admins can view all question means"           on public.overall_question_means;
drop policy if exists "SAO admins can view all intervention reports"     on public.intervention_reports;
drop policy if exists "SAO admins can view all AI suggestions"           on public.instructor_ai_suggestions;
drop policy if exists "SAO admins can view all wordclouds"               on public.instructor_wordcloud;
drop policy if exists "SAO admins can view all subjects"                 on public.subjects;          -- see "Admins and Deans can view all subjects"
drop policy if exists "SAO Admins can view audit logs"                   on public.audit_logs;        -- twin: "audit: sao reads all"
drop policy if exists "SAO personnel can view academic department table" on public.department_table;  -- twin: "department_table: sao reads all"
drop policy if exists "Staff and Admins can insert survey data"          on public.sast_all_raw_data_survey; -- twin: "raw: sao inserts" (is_sao())
-- Approved SAO staff already read every image through
-- "SAO office can read all scan images"; this one only added access for
-- non-SAO accounts that could point their own failed_scan_queue row at any
-- scan_image_id.
drop policy if exists "Gatherers can read own scan images"               on public.scan_error_images;

-- ── 3. Recreate role-based policies with the approval gate ──────────────────

-- 3a. Results tables: "Owners and Deans can view ..." (role names 'Dean' /
--     'Department Head' match no current role, but keep the logic, gated).
drop policy if exists "Owners and Deans can view overall survey" on public.overall_total_survey;
create policy "Owners and Deans can view overall survey" on public.overall_total_survey
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = overall_total_survey.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Owners and Deans can view performance results" on public.performance_results;
create policy "Owners and Deans can view performance results" on public.performance_results
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = performance_results.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Owners and Deans can view management results" on public.management_results;
create policy "Owners and Deans can view management results" on public.management_results
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = management_results.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Owners and Deans can view question means" on public.overall_question_means;
create policy "Owners and Deans can view question means" on public.overall_question_means
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = overall_question_means.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Owners and Deans can view AI suggestions" on public.instructor_ai_suggestions;
create policy "Owners and Deans can view AI suggestions" on public.instructor_ai_suggestions
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = instructor_ai_suggestions.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Owners and Deans can view wordcloud" on public.instructor_wordcloud;
create policy "Owners and Deans can view wordcloud" on public.instructor_wordcloud
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.department_table f_dept
    join public.department_table me on f_dept."Department_name_ID" = me."Department_name_ID"
    join public.roles r on me.roles = r.id
    where f_dept.user_id = instructor_wordcloud.instructor_id and me.user_id = auth.uid()
      and r."Roles" = any (array['Dean'::text, 'Department Head'::text]))));

drop policy if exists "Allow leadership to read wordclouds" on public.instructor_wordcloud;
create policy "Allow leadership to read wordclouds" on public.instructor_wordcloud
  for select to authenticated
  using ((select public.is_approved_user()) and (
    exists (select 1 from public.department_table dt join public.roles r on dt.roles = r.id
            where dt.user_id = auth.uid() and r."Roles" = 'Department Head'::text)
    or exists (select 1 from public."Sao_users" su join public.roles r on su.role_id = r.id
               where su.user_id = auth.uid() and r."Roles" = 'SAO Admin'::text)));

-- 3b. Department-head reads through get_user_dept_and_role() /
--     get_auth_user_dept_id() (these match DEPARTMENT_HEAD without approval).
drop policy if exists "Deans view department survey" on public.overall_total_survey;
create policy "Deans view department survey" on public.overall_total_survey
  for select to authenticated
  using ((select public.is_approved_user()) and instructor_id in (
    select department_table.user_id from public.department_table
    where department_table."Department_name_ID" in (
      select g.dept_id from public.get_user_dept_and_role() g(dept_id, role_name)
      where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text]))));

drop policy if exists "Deans can view department scores" on public.overall_total_survey;
create policy "Deans can view department scores" on public.overall_total_survey
  for select to authenticated
  using ((auth.uid() = instructor_id) or ((select public.is_approved_user()) and exists (
    select 1 from public.get_auth_user_dept_id() a(dept_id, is_admin)
    join public.department_table target_dept on target_dept.user_id = overall_total_survey.instructor_id
    where a.is_admin = true and a.dept_id = target_dept."Department_name_ID")));

drop policy if exists "Deans view department interventions" on public.intervention_reports;
create policy "Deans view department interventions" on public.intervention_reports
  for select to authenticated
  using ((dean_id = auth.uid()) or ((select public.is_approved_user()) and instructor_id in (
    select department_table.user_id from public.department_table
    where department_table."Department_name_ID" in (
      select g.dept_id from public.get_user_dept_and_role() g(dept_id, role_name)
      where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text])))));

drop policy if exists "Deans view dept roster" on public.department_table;
create policy "Deans view dept roster" on public.department_table
  for select to authenticated
  using ((select public.is_approved_user()) and "Department_name_ID" in (
    select g.dept_id from public.get_user_dept_and_role() g(dept_id, role_name)
    where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text])));

-- Any member could read their (self-chosen, while pending) department roster.
-- Approved members keep it; see the "decide separately" note in the report.
drop policy if exists "Deans can view department members" on public.department_table;
create policy "Deans can view department members" on public.department_table
  for select to authenticated
  using ((auth.uid() = user_id) or ((select public.is_approved_user()) and "Department_name_ID" = public.get_auth_dept_id()));

-- 3c. subjects
drop policy if exists "Admins and Deans can view all subjects" on public.subjects;
create policy "Admins and Deans can view all subjects" on public.subjects
  for select to authenticated
  using ((select public.is_approved_user()) and (
    exists (select 1 from public."Sao_users" su where su.user_id = auth.uid() and su.role_id = any (array[1::bigint, 2::bigint]))
    or exists (select 1 from public.department_table dt where dt.user_id = auth.uid() and dt.roles = 3)));

-- 3d. Raw survey rows (read + delete; insert twin dropped above)
drop policy if exists "Admins view all, Staff view own" on public.sast_all_raw_data_survey;
create policy "Admins view all, Staff view own" on public.sast_all_raw_data_survey
  for select to authenticated
  using (((sao_staff_id = auth.uid()) and (select public.is_approved_user()))
         or (select public.is_approved_sao_admin()));

drop policy if exists "SAO office and gatherers can delete raw results" on public.sast_all_raw_data_survey;
create policy "SAO office and gatherers can delete raw results" on public.sast_all_raw_data_survey
  for delete to authenticated
  using (((auth.uid() = sao_staff_id) and (select public.is_approved_user()))
         or (select public.is_approved_sao_staff()));

-- 3e. Scan images (full page images with student IDs)
drop policy if exists "SAO office can read all scan images" on public.scan_error_images;
create policy "SAO office can read all scan images" on public.scan_error_images
  for select to authenticated
  using ((select public.is_approved_sao_staff()));

-- 3f. Sheet import jobs
drop policy if exists "SAO office reads sheet import jobs" on public.sheet_import_jobs;
create policy "SAO office reads sheet import jobs" on public.sheet_import_jobs
  for select to authenticated
  using (((requested_by = auth.uid()) and (select public.is_approved_user()))
         or (select public.is_approved_sao_staff()));

-- 3g. failed_scan_queue (holds partial OCR data incl. student IDs)
drop policy if exists "Staff and Admins manage failed queue" on public.failed_scan_queue;
create policy "Staff and Admins manage failed queue" on public.failed_scan_queue
  for all to authenticated
  using (((user_id = auth.uid()) and (select public.is_approved_user()))
         or (select public.is_approved_sao_admin()));

drop policy if exists "fsq_own_rw" on public.failed_scan_queue;
create policy "fsq_own_rw" on public.failed_scan_queue
  for all to authenticated
  using ((user_id = auth.uid()) and (select public.is_approved_user()))
  with check ((user_id = auth.uid()) and (select public.is_approved_user()));

-- 3h. Admin writes that tested the role only
drop policy if exists "SAO Admin can manage instructor_subjects" on public.instructor_subjects;
create policy "SAO Admin can manage instructor_subjects" on public.instructor_subjects
  for all to authenticated
  using ((select public.is_approved_sao_admin()))
  with check ((select public.is_approved_sao_admin()));

drop policy if exists "Allow SAO_ADMIN to insert departments" on public.department_name;
create policy "Allow SAO_ADMIN to insert departments" on public.department_name
  for insert to authenticated
  with check ((select public.is_approved_sao_admin()));

drop policy if exists "Allow SAO_ADMIN to update departments" on public.department_name;
create policy "Allow SAO_ADMIN to update departments" on public.department_name
  for update to authenticated
  using ((select public.is_approved_sao_admin()))
  with check ((select public.is_approved_sao_admin()));

-- ── 4. Sign-up / self-service hardening ─────────────────────────────────────
-- Checked 2026-11-21: enforce_user_info_insert_defaults() forces
-- account_status='pending', disabled/is_admin/is_placeholder=false on a self
-- insert; protect_sao_users_insert() blocks self SAO_ADMIN and role changes;
-- guard_department_table_self_insert() only lets a pending account pick a
-- non-SAO role once; there is no self UPDATE policy on department_table.
-- Gaps closed here: a user could flip their own user_info.disabled / is_admin,
-- and the "admin" test was role-only (a disabled admin could re-approve
-- themselves). Body below = the live body + the two new checks.
create or replace function public.protect_user_info_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
BEGIN
  -- Service role always allowed
  IF current_user = 'service_role' OR auth.role() = 'service_role'
     OR public.is_trusted_db_caller() THEN  -- 036: SQL editor / n8n Postgres
    RETURN NEW;
  END IF;

  -- If caller is not an (approved) SAO admin, prevent mutating governance fields
  IF NOT public.is_sao_admin() THEN
    IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
      RAISE EXCEPTION 'Forbidden: You cannot modify your own account status.';
    END IF;

    IF NEW.disabled IS DISTINCT FROM OLD.disabled
       OR NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
      RAISE EXCEPTION 'Forbidden: You cannot modify account flags.';
    END IF;

    -- Fill-once: allowed only when there was no ID before, and only by the
    -- account owner.
    IF NEW.university_id IS DISTINCT FROM OLD.university_id THEN
      IF NOT (
        NULLIF(btrim(COALESCE(OLD.university_id, '')), '') IS NULL
        AND NULLIF(btrim(COALESCE(NEW.university_id, '')), '') IS NOT NULL
        AND auth.uid() = OLD.id
      ) THEN
        RAISE EXCEPTION 'Forbidden: You cannot modify your university ID.';
      END IF;
    END IF;

    IF NEW.email IS DISTINCT FROM OLD.email THEN
      RAISE EXCEPTION 'Forbidden: Primary email address cannot be changed directly.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'Forbidden: User ID is immutable.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

commit;
