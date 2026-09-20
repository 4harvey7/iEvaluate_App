-- 20240130000014_no_delete_departments_subjects.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- supabase_migrations.schema_migrations is empty on this project, so a push
-- would try to replay every earlier migration.
--
-- Departments and subjects become add/edit only. The SAO admin keeps every
-- other power over them.
--
-- WHY, FOR DEPARTMENTS
-- The screen's own guard only counted department_table members
-- (manage_departments_screen.dart, before this change), but three other foreign
-- keys point at department_name. The live ON DELETE actions are:
--
--   department_table.Department_name_ID       -> SET DEFAULT  (the default is NULL)
--   instructor_department_terms.department_id -> CASCADE
--   instructor_departments.department_id      -> CASCADE
--   subjects.department_id                    -> NO ACTION
--
-- So a department with no *current* members but with history would take its
-- instructor_department_terms rows with it -- 49 rows exist today. That table
-- was added by 20240130000010 for the express purpose of keeping closed terms
-- reproducible, so losing it silently rewrites past reports. And SET DEFAULT
-- nulls the column that role resolution reads (auth_service.dart), which can
-- leave a surviving member with no resolvable role and no way to log in.
--
-- The dialog that used to sit in front of this claimed the opposite: "Linked
-- users and subjects won't be deleted but will lose their department
-- association." That was only accidentally true, and only when the department
-- happened to have subjects attached to block it.
--
-- WHY, FOR SUBJECTS
-- No UI path ever deleted a subject, but the live policy was FOR ALL, which
-- silently included DELETE -- so an SAO admin with a session and the
-- publishable key could delete one straight through the REST API. Five tables
-- reference subjects (sast_all_raw_data_survey, management_results,
-- performance_results, student_remarks, instructor_subjects), and
-- instructor_subjects.subject_id is ON DELETE CASCADE.
--
-- BOTH LAYERS
-- Removing the button is not enough: the REST API is reachable directly with
-- the publishable key, so anything enforced only in Dart is advisory. Policies
-- withdraw the grant; the triggers are the backstop if a policy is ever re-added
-- by hand, and they carry the reason so whoever hits one understands why.


-- ── Departments: add and edit, never delete ──────────────────────────────────
drop policy if exists "Allow SAO_ADMIN to delete departments" on public.department_name;

create or replace function public.forbid_department_delete()
returns trigger language plpgsql as $$
begin
  raise exception
    'Departments cannot be deleted. Editing is allowed; deletion would cascade '
    'into instructor_department_terms and destroy frozen per-term history. '
    'Rename the department instead.'
    using errcode = 'restrict_violation';
end $$;

drop trigger if exists department_name_no_delete on public.department_name;
create trigger department_name_no_delete
  before delete on public.department_name
  for each row execute function public.forbid_department_delete();


-- ── Subjects: add and edit, never delete ─────────────────────────────────────
-- Split the FOR ALL policy into INSERT and UPDATE and leave DELETE ungranted.
--
-- The old policy also hardcoded `su.role_id = 1`. is_sao_admin() resolves the
-- role by name, so a reordered roles table cannot silently widen this grant to
-- the wrong role or revoke it from the right one.
drop policy if exists "SAO Admin can manage subjects" on public.subjects;

create policy "subjects: sao admin can insert"
  on public.subjects for insert to authenticated
  with check (public.is_sao_admin());

create policy "subjects: sao admin can update"
  on public.subjects for update to authenticated
  using (public.is_sao_admin())
  with check (public.is_sao_admin());

create policy "subjects: sao admin can read"
  on public.subjects for select to authenticated
  using (public.is_sao_admin());

create or replace function public.forbid_subject_delete()
returns trigger language plpgsql as $$
begin
  raise exception
    'Subjects cannot be deleted. Evaluation results, raw survey rows and '
    'student remarks all reference subjects; removing one would orphan or '
    'destroy collected data. Edit the subject instead, or remove the '
    'instructor assignment.'
    using errcode = 'restrict_violation';
end $$;

drop trigger if exists subjects_no_delete on public.subjects;
create trigger subjects_no_delete
  before delete on public.subjects
  for each row execute function public.forbid_subject_delete();

-- instructor_subjects is intentionally left deletable. Removing an instructor's
-- assignment from a subject is a normal correction and destroys no evaluation
-- data -- results reference the subject, not the assignment. It is also the
-- only way to undo a mis-assignment, since the subject itself now cannot go.

-- If a genuine one-off removal is ever required (a department created by
-- mistake, before anyone was assigned to it), the owner can lift the guard for
-- the length of one transaction rather than dropping it:
--
--   begin;
--   alter table public.department_name disable trigger department_name_no_delete;
--   delete from public.department_name where id = <id>;
--   alter table public.department_name enable trigger department_name_no_delete;
--   commit;
--
-- Check instructor_department_terms for that department first. The CASCADE is
-- still there; the trigger is only what stops you reaching it by accident.


-- ── Verification ─────────────────────────────────────────────────────────────
-- 1. Expect NO row with cmd = 'DELETE' or 'ALL' for either table.
--    select tablename, policyname, cmd from pg_policies
--     where schemaname = 'public' and tablename in ('department_name','subjects')
--     order by tablename, cmd;
--
-- 2. Expect both triggers present.
--    select c.relname, t.tgname from pg_trigger t
--      join pg_class c on c.oid = t.tgrelid
--     where not t.tgisinternal
--       and t.tgname in ('department_name_no_delete','subjects_no_delete');
--
-- 3. Expect both to raise restrict_violation and roll back, proving the guard
--    fires even for the table owner. Neither row exists, so nothing is at risk.
--    begin; delete from public.department_name where id = -1; rollback;
--    begin; delete from public.subjects where id = '00000000-0000-0000-0000-000000000000'; rollback;
