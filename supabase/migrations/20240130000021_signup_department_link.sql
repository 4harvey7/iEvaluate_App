-- ============================================================================
-- Migration: keep instructor_departments in step with department_table
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply this with `supabase db push`.
--    supabase_migrations.schema_migrations is empty in this project, so a push
--    would try to replay every migration from the beginning against a database
--    that already has all of them.
--
-- ── What broke ──────────────────────────────────────────────────────────────
--
-- Migration 10 replaced migration 06's permissive
--   INSERT ... TO authenticated WITH CHECK (true)
-- on instructor_departments with
--   INSERT ... TO authenticated WITH CHECK (public.is_sao_admin()).
--
-- That was the right call -- migration 06 let any signed-in user add themselves
-- to every department -- but it also revoked the one write that signUp() makes
-- on its own behalf. auth_service.dart STEP 5 inserts department_table (allowed:
-- that table's INSERT policy is self-scoped) and then instructor_departments
-- (no longer allowed: the new user is not an SAO admin). The insert is wrapped
-- in try/catch and only debugPrint'ed, so signup still reported
-- "Registration Submitted!" and the row was simply never written:
--
--   [AUTH] Warning: Could not insert instructor_departments row:
--   PostgrestException(message: new row violates row-level security policy
--   for table "instructor_departments", code: 42501)
--   --- [AUTH] SIGN UP SUCCESS ---
--
-- Every account self-registered since migration 10 was applied is therefore
-- missing its department link. That is not cosmetic. faculty_roster_screen
-- joins instructor_departments!inner on is_primary, and EvaluationService
-- resolves department faculty the same way, so an affected instructor is
-- invisible on their own department head's roster AND excluded from the
-- department average -- while their results still count on the campus
-- leaderboard. Six accounts were in this state when it was found, including the
-- top-ranked instructor in the system.
--
-- ── The fix ─────────────────────────────────────────────────────────────────
--
-- Not a self-insert policy. Handing the client back a narrower version of the
-- privilege migration 10 removed would re-open the same hole, and it would
-- leave the two tables free to disagree on every other write path.
--
-- Instead the mirror row is written by a trigger on department_table. The
-- invariant admin-update-role already states in a comment -- "department_table
-- and instructor_departments both record the primary department and must move
-- together" -- becomes something the database enforces rather than something
-- each caller has to remember. The client needs no privilege at all: it is the
-- trigger, running SECURITY DEFINER, that inserts.
-- ============================================================================


-- ── STEP 1: mirror department_table onto instructor_departments ─────────────
--
-- SECURITY DEFINER so it runs as the function owner and is unaffected by the
-- is_sao_admin() write policies -- that is the entire point. search_path is
-- pinned for the same reason migration 10 pinned it on the role helpers.
--
-- The row written is exactly the row department_table already contains, so this
-- grants no reach the caller did not already have: whoever may create a
-- department_table row has, by doing so, already chosen the department.
CREATE OR REPLACE FUNCTION public.sync_instructor_department()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW."Department_name_ID" IS NULL OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Migration 17 put a unique index on (instructor_id) alone and a
  -- CHECK (is_primary) on every row, so an instructor has at most ONE row and
  -- it is always primary. This UPDATE therefore matches whatever row exists,
  -- and the department is moved rather than joined by a second row -- which is
  -- also what stops the INSERT below from ever tripping that unique index.
  UPDATE public.instructor_departments
     SET department_id = NEW."Department_name_ID"
   WHERE instructor_id = NEW.user_id
     AND is_primary;

  IF NOT FOUND THEN
    -- Reached only when the instructor has no row at all. ON CONFLICT is for
    -- the concurrent-signup race, not for an existing row: two writes landing
    -- together would otherwise raise 23505 on
    -- instructor_departments_unique (instructor_id, department_id), which
    -- migration 17 left in place. Targeting that pair rather than
    -- (instructor_id) keeps this working on a database where migration 17 was
    -- never applied and (instructor_id) alone is not unique.
    INSERT INTO public.instructor_departments (instructor_id, department_id, is_primary)
    VALUES (NEW.user_id, NEW."Department_name_ID", true)
    ON CONFLICT (instructor_id, department_id)
    DO UPDATE SET is_primary = true;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_instructor_department() IS
  'Mirrors department_table.Department_name_ID into instructor_departments as '
  'the primary row. Exists because instructor_departments INSERT is restricted '
  'to SAO admins (migration 10) while self-registration must still produce the '
  'link the dean roster and department analytics read from.';

-- AFTER, not BEFORE: the one-head-per-department trigger from migration 16 is a
-- BEFORE trigger, and a department_table insert it rejects must not leave an
-- instructor_departments row behind.
DROP TRIGGER IF EXISTS department_table_sync_instructor_department ON public.department_table;
CREATE TRIGGER department_table_sync_instructor_department
  AFTER INSERT OR UPDATE OF "Department_name_ID" ON public.department_table
  FOR EACH ROW EXECUTE FUNCTION public.sync_instructor_department();


-- ── STEP 2: let SAO admins create academic rows ─────────────────────────────
--
-- department_table carries a self-scoped INSERT policy and no admin one, which
-- is the exact mirror of the instructor_departments problem above: an SAO admin
-- restoring an instructor who has no department_table row at all is refused
-- with the same 42501. (Found on a live account -- 'mark medello' teaches two
-- subjects in the current term with no department_table row, so he resolves to
-- no role.)
--
-- admin-update-role runs on the service role and bypasses RLS, but it only
-- UPDATEs department_table; against a missing row that matches nothing and
-- succeeds silently, so the edge function cannot repair this either.
DROP POLICY IF EXISTS "SAO admins insert department_table" ON public.department_table;
CREATE POLICY "SAO admins insert department_table"
  ON public.department_table FOR INSERT TO authenticated
  WITH CHECK (public.is_sao_admin());

DROP POLICY IF EXISTS "SAO admins update department_table" ON public.department_table;
CREATE POLICY "SAO admins update department_table"
  ON public.department_table FOR UPDATE TO authenticated
  USING (public.is_sao_admin()) WITH CHECK (public.is_sao_admin());


-- ── STEP 3: backfill the accounts the gap already broke ─────────────────────
--
-- Same shape as migration 06 STEP 2, which is what kept everyone registered
-- BEFORE migration 10 working. This catches everyone registered after it.
INSERT INTO public.instructor_departments (instructor_id, department_id, is_primary)
SELECT dt.user_id, dt."Department_name_ID", true
  FROM public.department_table dt
 WHERE dt.user_id IS NOT NULL
   AND dt."Department_name_ID" IS NOT NULL
   AND NOT EXISTS (
         SELECT 1 FROM public.instructor_departments idp
          WHERE idp.instructor_id = dt.user_id
       )
ON CONFLICT (instructor_id, department_id) DO NOTHING;


-- == Verification ============================================================
-- 1. The trigger exists.
--      select t.tgname from pg_trigger t
--        join pg_class c on c.oid = t.tgrelid
--       where not t.tgisinternal
--         and t.tgname = 'department_table_sync_instructor_department';
--
-- 2. No instructor with a department_table row lacks a link. Expect 0 rows.
--      select dt.user_id
--        from public.department_table dt
--       where dt."Department_name_ID" is not null
--         and not exists (select 1 from public.instructor_departments idp
--                          where idp.instructor_id = dt.user_id);
--
-- 3. End to end: register a new instructor from the app, then confirm the row
--    appears without anyone having touched it.
--      select * from public.instructor_departments
--       where instructor_id = '<the new account id>';
-- ============================================================================
