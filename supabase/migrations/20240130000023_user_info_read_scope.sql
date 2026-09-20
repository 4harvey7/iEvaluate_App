-- ============================================================================
-- Migration: stop every signed-in account from reading everyone's contact details
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply this with `supabase db push`.
-- WARNING  READ STEP 0 FIRST. This migration is not complete on its own.
--
-- ── What was found ──────────────────────────────────────────────────────────
--
-- Signed in as an ordinary instructor (rodzharveydlicayan@gmail.com), a plain
-- PostgREST call returns EVERY account on the system:
--
--   GET /rest/v1/user_info?select=id,first_name,last_name,email,university_id
--   -> 24 rows, 23 of them other people, every one with email and
--      university_id, e.g. Banjiee Caruana / banjieecaruana@gmail.com / 723043
--
-- The anon key ships inside the APK, so this is reachable by anyone who can
-- sign in with any account at all -- no admin screen required, just curl.
--
-- migration 00 only ever granted two SELECT policies on user_info:
--   "Users can view own profile"            USING (auth.uid() = id)
--   "Deans can view department faculty ..."  department-scoped
--
-- Neither of those returns 24 rows to an instructor. So a THIRD, permissive
-- policy exists in the live database that is not in this migrations folder --
-- almost certainly a "Enable read access for all users" USING (true) added
-- from the Supabase dashboard. This file cannot drop it by name because that
-- name is not known here, which is what STEP 0 is for.
--
-- Checked before writing this: the instructor module only ever reads its OWN
-- row (instructor_dashboard.dart:189, past_semesters_screen.dart:74 and
-- instructor_settings_screen.dart all filter .eq('id', widget.userId)), so
-- tightening this does not cost the instructor screens anything. The SAO
-- screens do need every row, which is what STEP 1 restores explicitly.
-- ============================================================================


-- ── STEP 0: find the permissive policy, then drop it ────────────────────────
-- Run this first and read the output:
--
--   select policyname, cmd, qual
--     from pg_policies
--    where schemaname = 'public' and tablename = 'user_info';
--
-- Anything whose `qual` is `true` (or is otherwise unscoped) for SELECT is the
-- leak. Drop it by its exact name:
--
--   drop policy "<the name you found>" on public.user_info;
--
-- Do NOT drop "Users can view own profile" or
-- "Deans can view department faculty profiles" -- both are still needed.


-- ── STEP 1: give the SAO office the read-all it actually needs ──────────────
-- User Management, Personnel Management and the admin dashboard all list every
-- account, so they need this explicitly once the blanket policy is gone.
-- Staff are included because the gatherer and import screens resolve
-- instructor names across departments.
DROP POLICY IF EXISTS "SAO office reads all profiles" ON public.user_info;
CREATE POLICY "SAO office reads all profiles"
  ON public.user_info FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public."Sao_users" su
    JOIN public.roles r ON r.id = su.role_id
    WHERE su.user_id = auth.uid()
      AND r."Roles" IN ('SAO_ADMIN', 'SAO_STAFF')
  ));


-- ── STEP 2: department heads, resolved the way the roster resolves them ─────
-- migration 00's dean policy goes through get_user_dept_and_role() and
-- department_table. The faculty roster goes through instructor_departments.
-- Since migration 06 those two can disagree, and a head who cannot read a
-- profile the roster is trying to show gets a blank row rather than an error.
-- This adds the instructor_departments route alongside the existing one.
DROP POLICY IF EXISTS "Heads read their department profiles" ON public.user_info;
CREATE POLICY "Heads read their department profiles"
  ON public.user_info FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.instructor_departments target
    JOIN public.department_table caller
      ON caller."Department_name_ID" = target.department_id
    JOIN public.roles r ON r.id = caller.roles
    WHERE target.instructor_id = public.user_info.id
      AND caller.user_id = auth.uid()
      AND upper(r."Roles") IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
  ));


-- == Verification ============================================================
-- After STEP 0 has been done, sign in as an ordinary instructor and repeat the
-- call. Expect ONE row (their own), not 24:
--
--   select count(*) from public.user_info;
--
-- Then confirm nothing regressed:
--   - SAO admin: User Management still lists every account.
--   - Department head: the faculty roster still shows their department.
--   - Instructor: dashboard, My Subjects and Past Semesters still load.
-- ============================================================================
