-- ============================================================================
-- 20240130000028_intervention_reports_rls_and_emailed_at.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`
-- (20240130000000_initial_schema.sql is a schema dump, not a runnable
-- migration -- same as every migration from 000002 on).
--
-- WHAT IT DOES
--   1. Adds intervention_reports.emailed_at. send-intervention-email claims a
--      report by setting it (UPDATE ... WHERE emailed_at IS NULL), so a report
--      is emailed at most once even when two requests race.
--   2. INSERT: a department head may file a report only for an instructor
--      whose primary department is the head's own, never for themselves, and
--      only as 'Pending'. Before, any head could file against anyone.
--   3. UPDATE: the filing head may only change status, and only to
--      'Resolved'. Every other column (instructor_id, dean_id, created_at,
--      action_type, notes, emailed_at, instructor_name, term_id, ...) is
--      locked by a trigger. Before, the head could rewrite any column.
--   4. SELECT policies and the SAO_ADMIN read-all policy are NOT touched.
--   5b. Drops five dashboard-made write policies (not in the repo) that would
--      otherwise keep the old, looser rules alive (policies are OR'ed).
--
-- Edge functions use the service role; the trigger lets it (and the SQL
-- editor's postgres role) through, so send-intervention-email can set and
-- clear emailed_at.
--
-- Safe to run more than once. Runs as one transaction: if the final check
-- fails, nothing is changed.
-- ============================================================================

begin;

-- ── 0. Preconditions ────────────────────────────────────────────────────────
do $pre$
begin
  if to_regprocedure('public.is_department_head_role(bigint)') is null then
    raise exception 'public.is_department_head_role(bigint) is missing. Apply migration 20240130000016 first.';
  end if;
  if to_regclass('public.instructor_departments') is null then
    raise exception 'public.instructor_departments is missing. Apply migration 20240130000006 first.';
  end if;
end
$pre$;


-- ── 1. emailed_at (used by send-intervention-email as its lock) ─────────────
alter table public.intervention_reports
  add column if not exists emailed_at timestamptz;

comment on column public.intervention_reports.emailed_at is
  'When send-intervention-email claimed this report for sending. NULL = not '
  'emailed yet. Set and cleared by the service role only.';


-- ── 2. Who may file a report for whom ───────────────────────────────────────
-- Same rule as the alert list (getDepartmentAlerts) and send-intervention-email:
-- the caller is an approved department head, and the instructor's primary
-- instructor_departments row is in the caller's department.
--
-- SECURITY DEFINER so it can read department_table, user_info, roles and
-- instructor_departments whatever their own RLS says. It always uses
-- auth.uid() and returns only true/false, so it cannot be used to ask about
-- anyone else. Role names go through is_department_head_role (migration 16),
-- which accepts DEPARTMENT_HEAD, DEPARTMENT-HEAD, DEPARTMENT HEAD and DEAN.
create or replace function public.can_file_intervention_for(p_instructor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and p_instructor_id is not null
     and p_instructor_id <> auth.uid()
     and exists (
       select 1
       from public.department_table caller
       join public.user_info caller_info
         on caller_info.id = caller.user_id
       join public.instructor_departments target
         on target.department_id = caller."Department_name_ID"
       where caller.user_id = auth.uid()
         and public.is_department_head_role(caller.roles)
         and lower(coalesce(caller_info.account_status, '')) = 'approved'
         and target.instructor_id = p_instructor_id
         and target.is_primary
     );
$$;

comment on function public.can_file_intervention_for(uuid) is
  'True when the signed-in user is an approved department head and the given '
  'instructor''s primary department is theirs. Used by the intervention_reports '
  'INSERT policy.';

revoke all on function public.can_file_intervention_for(uuid) from public;
grant execute on function public.can_file_intervention_for(uuid)
  to authenticated, service_role;


-- ── 3. INSERT policy ────────────────────────────────────────────────────────
drop policy if exists "Deans can create intervention reports"
  on public.intervention_reports;
drop policy if exists "Heads can create intervention reports for own department"
  on public.intervention_reports;

create policy "Heads can create intervention reports for own department"
  on public.intervention_reports
  for insert
  to authenticated
  with check (
    dean_id = auth.uid()
    and instructor_id <> auth.uid()
    and status = 'Pending'
    and emailed_at is null
    and public.can_file_intervention_for(instructor_id)
  );


-- ── 4. UPDATE policy ────────────────────────────────────────────────────────
-- Row access only: the filer, and the result must be Resolved. Which columns
-- may change is enforced by the trigger in step 5 (a policy cannot see OLD).
drop policy if exists "Deans can update their department intervention reports"
  on public.intervention_reports;
drop policy if exists "Heads can resolve own intervention reports"
  on public.intervention_reports;

create policy "Heads can resolve own intervention reports"
  on public.intervention_reports
  for update
  to authenticated
  using (dean_id = auth.uid())
  with check (dean_id = auth.uid() and status = 'Resolved');


-- ── 5. Column lock ──────────────────────────────────────────────────────────
-- SECURITY INVOKER on purpose: inside the trigger, current_user is the
-- caller's role -- 'authenticated' for the app, 'service_role' for edge
-- functions, 'postgres' in the SQL editor. Only app users are restricted.
--
-- The UPDATE check compares the whole row minus status (and minus updated_at,
-- in case the live table has an auto-updated one), so any column -- including
-- ones not in the migration files, like instructor_name -- is locked.
create or replace function public.intervention_reports_lock_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- The app never sends created_at; nobody may backdate or future-date one.
    new.created_at := now();
    return new;
  end if;

  if (to_jsonb(new) - 'status' - 'updated_at')
     is distinct from (to_jsonb(old) - 'status' - 'updated_at') then
    raise exception 'Only the status of an intervention report can be changed.'
      using errcode = '42501';
  end if;

  -- Any open status (Pending, or the old default 'Active Tracking') may become
  -- Resolved. Nothing else, and a Resolved report cannot be reopened.
  if new.status is distinct from old.status
     and new.status is distinct from 'Resolved' then
    raise exception 'An intervention report can only be marked as Resolved.'
      using errcode = '42501';
  end if;

  return new;
end
$$;

drop trigger if exists intervention_reports_lock_columns on public.intervention_reports;
create trigger intervention_reports_lock_columns
  before insert or update on public.intervention_reports
  for each row execute function public.intervention_reports_lock_columns();

-- ── 5b. Drop dashboard-made write policies (not in the repo) ────────────────
-- Policies are OR'ed, so each of these would keep the old, looser rules alive:
--   * the two ALL policies let any head of the instructor's department
--     insert with any dean_id, rewrite any column and DELETE any report;
--   * "Deans create interventions" let ANY signed-in user file a report;
--   * "interventions: dean can insert" let any head file against anyone;
--   * "interventions: dean can update status" let the filer rewrite any column.
-- Read access is unaffected: the live SELECT policies "Deans view department
-- interventions", "interventions: dean reads own", "interventions: instructor
-- reads own", "SAO admins can view all intervention reports" and
-- "interventions: sao reads all" already cover every app read.
drop policy if exists "Deans can manage department reports"     on public.intervention_reports;
drop policy if exists "Deans manage interventions"              on public.intervention_reports;
drop policy if exists "Deans create interventions"              on public.intervention_reports;
drop policy if exists "interventions: dean can insert"          on public.intervention_reports;
drop policy if exists "interventions: dean can update status"   on public.intervention_reports;


-- ── 6. Final check: no other write policy may survive ───────────────────────
-- Policies are OR'ed together. If the live database holds an extra INSERT /
-- UPDATE / ALL policy added from the dashboard (this happened on user_info,
-- see migration 23), the old behaviour would silently remain. Abort instead.
do $chk$
declare
  v_extra text;
begin
  select string_agg(format('"%s" (%s)', policyname, cmd), ', ')
    into v_extra
  from pg_policies
  where schemaname = 'public'
    and tablename  = 'intervention_reports'
    and permissive = 'PERMISSIVE'
    and cmd in ('INSERT', 'UPDATE', 'ALL')
    and policyname not in (
      'Heads can create intervention reports for own department',
      'Heads can resolve own intervention reports'
    );

  if v_extra is not null then
    raise exception 'Not applied: intervention_reports still has other write policies: %. Add a DROP POLICY line for each one above step 6 and run the file again.', v_extra;
  end if;
end
$chk$;

commit;


-- == Verification (run afterwards) ===========================================
-- 1. Expect: the five existing SELECT policies (3 head/instructor, 2 SAO)
--    and the two new write policies above.
--      select policyname, cmd, roles, qual, with_check
--        from pg_policies where tablename = 'intervention_reports';
-- 2. Expect the trigger:
--      select tgname from pg_trigger
--       where tgrelid = 'public.intervention_reports'::regclass and not tgisinternal;
-- 3. Expect the column:
--      select column_name from information_schema.columns
--       where table_schema = 'public' and table_name = 'intervention_reports'
--         and column_name = 'emailed_at';
