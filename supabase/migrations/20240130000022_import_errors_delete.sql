-- ============================================================================
-- Migration: let SAO admins clear import errors
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply this with `supabase db push`.
--    supabase_migrations.schema_migrations is empty in this project, so a push
--    would try to replay every migration from the beginning against a database
--    that already has all of them.
--
-- ── Why ─────────────────────────────────────────────────────────────────────
--
-- import_errors gets one row per survey row that failed to match. A single bad
-- sheet import therefore produces hundreds at once -- one run of a 916-row
-- sheet produced 916 -- and until now the only way to clear one was the detail
-- screen's "Discard", which sets status = 'discarded' one record at a time.
-- Nothing could remove them.
--
-- The Import Errors screen now has select-all + delete. That needs a DELETE
-- policy, and there was none: the table has no DELETE policy at all, so the
-- delete was accepted by PostgREST and silently changed nothing. Verified on
-- the live database -- deleting id 2852 returned success and left the row in
-- place. The app checks the rows are actually gone and reports the refusal
-- rather than claiming a success, but the real fix is this policy.
--
-- ── Who gets it ─────────────────────────────────────────────────────────────
--
-- The SAO office: admins AND staff. Staff were nearly left out on the grounds
-- that deleting throws away survey responses -- until it was tested. They can
-- ALREADY dispose of these records: the Fix screen's Discard button writes
-- status = 'discarded', and an UPDATE by staff@gmail.com was accepted and did
-- change the row. Withholding DELETE therefore protects nothing; it only makes
-- clearing 916 records one-at-a-time work, which is the whole problem.
--
-- Department heads and instructors are still excluded. They never run imports
-- and the screen is not in their navigation.
--
-- Written as an explicit EXISTS rather than public.is_sao(), because the exact
-- membership that helper tests was not verified here and this policy should say
-- plainly which roles it admits.
-- ============================================================================

DROP POLICY IF EXISTS "SAO admins delete import_errors" ON public.import_errors;
DROP POLICY IF EXISTS "SAO office deletes import_errors" ON public.import_errors;
CREATE POLICY "SAO office deletes import_errors"
  ON public.import_errors FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public."Sao_users" su
    JOIN public.roles r ON r.id = su.role_id
    WHERE su.user_id = auth.uid()
      AND r."Roles" IN ('SAO_ADMIN', 'SAO_STAFF')
  ));


-- == Verification ============================================================
-- 1. The policy exists.
--      select policyname, cmd from pg_policies
--       where schemaname = 'public' and tablename = 'import_errors';
--
-- 2. As an SAO admin, a delete now actually removes the row. Expect 0 rows back
--    from the second statement.
--      delete from public.import_errors where id = <some id>;
--      select id from public.import_errors where id = <that same id>;
-- ============================================================================
