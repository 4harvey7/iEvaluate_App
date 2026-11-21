-- ============================================================================
-- ROLLBACK for 20240130000036_rls_approval_gate.sql
-- Restores the 34 policies and 5 functions exactly as they were in live
-- pg_policies / pg_proc on 2026-11-21. RE-OPENS FINDING H1 (pending accounts
-- read results). Use only if 036 breaks access for APPROVED users and you
-- cannot fix it forward. Leaves public.is_approved_user() in place (harmless).
-- Run in the SQL editor as one transaction.
-- ============================================================================
begin;

drop policy if exists "SAO Admins can view audit logs" on public.audit_logs;
create policy "SAO Admins can view audit logs" on public.audit_logs for select to authenticated
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Allow SAO_ADMIN to insert departments" on public.department_name;
create policy "Allow SAO_ADMIN to insert departments" on public.department_name for insert to authenticated
  with check (exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and r."Roles" = 'SAO_ADMIN'::text));

drop policy if exists "Allow SAO_ADMIN to update departments" on public.department_name;
create policy "Allow SAO_ADMIN to update departments" on public.department_name for update to authenticated
  using (exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and r."Roles" = 'SAO_ADMIN'::text))
  with check (exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and r."Roles" = 'SAO_ADMIN'::text));

drop policy if exists "Deans can view department members" on public.department_table;
create policy "Deans can view department members" on public.department_table for select to public
  using (("Department_name_ID" = get_auth_dept_id()) or (auth.uid() = user_id));

drop policy if exists "Deans view dept roster" on public.department_table;
create policy "Deans view dept roster" on public.department_table for select to public
  using ("Department_name_ID" in (select g.dept_id from get_user_dept_and_role() g(dept_id, role_name)
         where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text])));

drop policy if exists "SAO personnel can view academic department table" on public.department_table;
create policy "SAO personnel can view academic department table" on public.department_table for select to authenticated
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Staff and Admins manage failed queue" on public.failed_scan_queue;
create policy "Staff and Admins manage failed queue" on public.failed_scan_queue for all to authenticated
  using ((user_id = auth.uid()) or exists (select 1 from "Sao_users" su join roles r on su.role_id = r.id where su.user_id = auth.uid() and r."Roles" = 'SAO_ADMIN'::text));

drop policy if exists fsq_own_rw on public.failed_scan_queue;
create policy fsq_own_rw on public.failed_scan_queue for all to public
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Owners and Deans can view AI suggestions" on public.instructor_ai_suggestions;
create policy "Owners and Deans can view AI suggestions" on public.instructor_ai_suggestions for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = instructor_ai_suggestions.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all AI suggestions" on public.instructor_ai_suggestions;
create policy "SAO admins can view all AI suggestions" on public.instructor_ai_suggestions for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "SAO Admin can manage instructor_subjects" on public.instructor_subjects;
create policy "SAO Admin can manage instructor_subjects" on public.instructor_subjects for all to authenticated
  using (exists (select 1 from "Sao_users" su where su.user_id = auth.uid() and su.role_id = 1))
  with check (exists (select 1 from "Sao_users" su where su.user_id = auth.uid() and su.role_id = 1));

drop policy if exists "Allow leadership to read wordclouds" on public.instructor_wordcloud;
create policy "Allow leadership to read wordclouds" on public.instructor_wordcloud for select to authenticated
  using (exists (select 1 from department_table dt join roles r on dt.roles = r.id where dt.user_id = auth.uid() and r."Roles" = 'Department Head'::text)
      or exists (select 1 from "Sao_users" su join roles r on su.role_id = r.id where su.user_id = auth.uid() and r."Roles" = 'SAO Admin'::text));

drop policy if exists "Owners and Deans can view wordcloud" on public.instructor_wordcloud;
create policy "Owners and Deans can view wordcloud" on public.instructor_wordcloud for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = instructor_wordcloud.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all wordclouds" on public.instructor_wordcloud;
create policy "SAO admins can view all wordclouds" on public.instructor_wordcloud for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Deans view department interventions" on public.intervention_reports;
create policy "Deans view department interventions" on public.intervention_reports for select to public
  using ((dean_id = auth.uid()) or instructor_id in (select department_table.user_id from department_table
    where department_table."Department_name_ID" in (select g.dept_id from get_user_dept_and_role() g(dept_id, role_name)
      where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text]))));

drop policy if exists "SAO admins can view all intervention reports" on public.intervention_reports;
create policy "SAO admins can view all intervention reports" on public.intervention_reports for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Owners and Deans can view management results" on public.management_results;
create policy "Owners and Deans can view management results" on public.management_results for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = management_results.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all management results" on public.management_results;
create policy "SAO admins can view all management results" on public.management_results for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Owners and Deans can view question means" on public.overall_question_means;
create policy "Owners and Deans can view question means" on public.overall_question_means for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = overall_question_means.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all question means" on public.overall_question_means;
create policy "SAO admins can view all question means" on public.overall_question_means for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Deans can view department scores" on public.overall_total_survey;
create policy "Deans can view department scores" on public.overall_total_survey for select to public
  using (exists (select 1 from get_auth_user_dept_id() a(dept_id, is_admin)
    join department_table target_dept on target_dept.user_id = overall_total_survey.instructor_id
    where ((a.is_admin = true) and (a.dept_id = target_dept."Department_name_ID")) or (auth.uid() = overall_total_survey.instructor_id)));

drop policy if exists "Deans view department survey" on public.overall_total_survey;
create policy "Deans view department survey" on public.overall_total_survey for select to public
  using (instructor_id in (select department_table.user_id from department_table
    where department_table."Department_name_ID" in (select g.dept_id from get_user_dept_and_role() g(dept_id, role_name)
      where upper(g.role_name) = any (array['DEAN'::text, 'DEPARTMENT HEAD'::text, 'DEPARTMENT_HEAD'::text]))));

drop policy if exists "Owners and Deans can view overall survey" on public.overall_total_survey;
create policy "Owners and Deans can view overall survey" on public.overall_total_survey for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = overall_total_survey.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all overall surveys" on public.overall_total_survey;
create policy "SAO admins can view all overall surveys" on public.overall_total_survey for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Owners and Deans can view performance results" on public.performance_results;
create policy "Owners and Deans can view performance results" on public.performance_results for select to authenticated
  using ((auth.uid() = instructor_id) or exists (select 1 from department_table f_dept
    join department_table me on f_dept."Department_name_ID" = me."Department_name_ID" join roles r on me.roles = r.id
    where f_dept.user_id = performance_results.instructor_id and me.user_id = auth.uid() and r."Roles" = any (array['Dean'::text, 'Department Head'::text])));

drop policy if exists "SAO admins can view all performance results" on public.performance_results;
create policy "SAO admins can view all performance results" on public.performance_results for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

drop policy if exists "Admins view all, Staff view own" on public.sast_all_raw_data_survey;
create policy "Admins view all, Staff view own" on public.sast_all_raw_data_survey for select to authenticated
  using ((sao_staff_id = auth.uid()) or exists (select 1 from "Sao_users" su join roles r on su.role_id = r.id where su.user_id = auth.uid() and r."Roles" = 'SAO_ADMIN'::text));

drop policy if exists "SAO office and gatherers can delete raw results" on public.sast_all_raw_data_survey;
create policy "SAO office and gatherers can delete raw results" on public.sast_all_raw_data_survey for delete to authenticated
  using ((auth.uid() = sao_staff_id) or exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and r."Roles" = any (array['SAO_ADMIN'::text, 'SAO_STAFF'::text])));

drop policy if exists "Staff and Admins can insert survey data" on public.sast_all_raw_data_survey;
create policy "Staff and Admins can insert survey data" on public.sast_all_raw_data_survey for insert to authenticated
  with check (exists (select 1 from "Sao_users" su join roles r on su.role_id = r.id where su.user_id = auth.uid() and r."Roles" = any (array['SAO_STAFF'::text, 'SAO_ADMIN'::text])));

drop policy if exists "Gatherers can read own scan images" on public.scan_error_images;
create policy "Gatherers can read own scan images" on public.scan_error_images for select to authenticated
  using (exists (select 1 from failed_scan_queue fsq where fsq.scan_image_id = scan_error_images.id and fsq.user_id = auth.uid()));

drop policy if exists "SAO office can read all scan images" on public.scan_error_images;
create policy "SAO office can read all scan images" on public.scan_error_images for select to authenticated
  using (exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and r."Roles" = any (array['SAO_ADMIN'::text, 'SAO_STAFF'::text])));

drop policy if exists "SAO office reads sheet import jobs" on public.sheet_import_jobs;
create policy "SAO office reads sheet import jobs" on public.sheet_import_jobs for select to authenticated
  using ((requested_by = auth.uid()) or exists (select 1 from "Sao_users" su join roles r on r.id = su.role_id where su.user_id = auth.uid() and upper(btrim(r."Roles")) = any (array['SAO_ADMIN'::text, 'SAO_STAFF'::text])));

drop policy if exists "Admins and Deans can view all subjects" on public.subjects;
create policy "Admins and Deans can view all subjects" on public.subjects for select to authenticated
  using (exists (select 1 from "Sao_users" su where su.user_id = auth.uid() and su.role_id = any (array[(1)::bigint, (2)::bigint]))
      or exists (select 1 from department_table dt where dt.user_id = auth.uid() and dt.roles = 3));

drop policy if exists "SAO admins can view all subjects" on public.subjects;
create policy "SAO admins can view all subjects" on public.subjects for select to public
  using (exists (select 1 from "Sao_users" where "Sao_users".user_id = auth.uid()));

-- Functions, as live on 2026-11-21 (role-only checks).
create or replace function public.is_sao_admin() returns boolean
language plpgsql security definer set search_path to 'public' as $f$
DECLARE is_admin BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM "Sao_users" su JOIN "roles" r ON su."role_id" = r."id"
                 WHERE su."user_id" = auth.uid() AND r."Roles" ILIKE 'SAO_ADMIN') INTO is_admin;
  RETURN is_admin;
END; $f$;

create or replace function public.check_is_sao_admin() returns boolean
language plpgsql security definer as $f$
BEGIN
  RETURN EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid() AND role_id = 1);
END; $f$;

create or replace function public.is_admin_check() returns boolean
language plpgsql security definer as $f$
BEGIN
  RETURN EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid() AND role_id = 1);
END; $f$;

create or replace function public.eval_is_sao_office() returns boolean
language sql stable security definer set search_path to 'public' as $f$
  select exists (select 1 from public."Sao_users" su join public.roles r on r.id = su.role_id
                 where su.user_id = auth.uid() and upper(btrim(r."Roles")) in ('SAO_ADMIN', 'SAO_STAFF'));
$f$;

-- protect_user_info_fields(): re-run its definition from
-- 20240130000027_allow_fill_missing_university_id.sql (the live body on
-- 2026-11-21 matched it: service-role bypass, then account_status /
-- university_id fill-once / email / id checks under NOT is_sao_admin()).

commit;
