-- ============================================================================
-- Migration: instructor_departments integrity + per-term membership snapshot
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply this with `supabase db push`.
--    supabase_migrations.schema_migrations is empty in this project, so a push
--    would try to replay every migration from the beginning against a database
--    that already has all of them.
--
-- Fixes three things:
--   1. Any logged-in user can currently add themselves to every department, or
--      delete their own department link. Migration 06 granted INSERT
--      WITH CHECK (true) and DELETE USING (true) to `authenticated`. The
--      comment claimed "SAO Admin manages via service role" but no policy
--      enforced it.
--   2. Nothing stops an instructor having two primary departments, which makes
--      "home department" ambiguous for the roster and for reporting.
--   3. Department membership has no term dimension, so historical reports are
--      rebuilt from *today's* membership. Reassigning one instructor silently
--      changes department averages for terms that already closed.
-- ============================================================================


-- ── STEP 1: harden the existing role helpers ────────────────────────────────
-- public.is_sao_admin() already exists and is exactly the check we want
-- (Sao_users JOIN roles WHERE "Roles" ILIKE 'SAO_ADMIN'), and four policies
-- already depend on it, so it is NOT redefined here.
--
-- Both helpers are SECURITY DEFINER with no pinned search_path, which lets a
-- caller who can create objects in an earlier schema shadow the tables the
-- function body resolves unqualified. ALTER FUNCTION ... SET search_path
-- changes no behaviour -- both bodies reference "Sao_users" and "roles", which
-- live in public -- and closes that surface.
ALTER FUNCTION public.is_sao_admin() SET search_path = public;
ALTER FUNCTION public.is_sao() SET search_path = public;


-- ── STEP 2: replace the permissive write policies ───────────────────────────
-- Dropped by their exact names as they exist in pg_policies.
DROP POLICY IF EXISTS "SAO Admin can insert instructor_departments" ON public.instructor_departments;
DROP POLICY IF EXISTS "SAO Admin can delete instructor_departments" ON public.instructor_departments;

-- Written as three explicit policies rather than one FOR ALL, so the read path
-- stays unambiguous: the existing
-- "Authenticated users can read instructor_departments" policy remains the only
-- thing granting SELECT, and it is left alone. Deans need to read the roster
-- and instructors need to see their own membership; it is not sensitive the way
-- emails are.
--
-- UPDATE is new. Migration 06 created no UPDATE policy at all, so moving an
-- instructor's primary department from client code would silently fail.
CREATE POLICY "SAO admins insert instructor_departments"
  ON public.instructor_departments FOR INSERT TO authenticated
  WITH CHECK (public.is_sao_admin());

CREATE POLICY "SAO admins update instructor_departments"
  ON public.instructor_departments FOR UPDATE TO authenticated
  USING (public.is_sao_admin()) WITH CHECK (public.is_sao_admin());

CREATE POLICY "SAO admins delete instructor_departments"
  ON public.instructor_departments FOR DELETE TO authenticated
  USING (public.is_sao_admin());


-- ── STEP 3: one primary department per instructor ───────────────────────────
-- Guarded so a violation reports readably instead of failing inside the index
-- build. This counted 0 when the migration was written; the guard is for other
-- environments and for re-runs.
DO $guard$
DECLARE offenders int;
BEGIN
  SELECT count(*) INTO offenders FROM (
    SELECT instructor_id
    FROM public.instructor_departments
    WHERE is_primary
    GROUP BY instructor_id
    HAVING count(*) > 1
  ) d;

  IF offenders > 0 THEN
    RAISE EXCEPTION
      'Cannot add the one-primary index yet: % instructor(s) have more than one primary department. Run the audit query at the bottom of this file to see who.',
      offenders;
  END IF;
END
$guard$;

-- Partial unique index: at most one is_primary = true row per instructor,
-- while any number of secondary departments stays allowed. This is a
-- constraint, not a convention -- no code path can violate it, including ones
-- written later.
CREATE UNIQUE INDEX IF NOT EXISTS instructor_departments_one_primary
  ON public.instructor_departments (instructor_id)
  WHERE is_primary;

-- Reporting reads membership by department, filtered to primaries.
CREATE INDEX IF NOT EXISTS instructor_departments_dept_primary_idx
  ON public.instructor_departments (department_id, is_primary);


-- ── STEP 4: per-term membership snapshot ────────────────────────────────────
-- Why this table exists: no results table stores a department.
-- overall_total_survey, management_results and performance_results all carry
-- only instructor_id + term_id. So a department report is reconstructed at read
-- time from current membership, and moving one instructor rewrites the past for
-- two departments at once.
--
-- Snapshotting membership per term makes a closed term's numbers reproducible:
-- a report printed last semester still matches the app next year.
CREATE TABLE IF NOT EXISTS public.instructor_department_terms (
  id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  term_id       uuid        NOT NULL REFERENCES public.academic_terms(id)  ON DELETE CASCADE,
  instructor_id uuid        NOT NULL REFERENCES public.user_info(id)       ON DELETE CASCADE,
  department_id bigint      NOT NULL REFERENCES public.department_name(id) ON DELETE CASCADE,
  is_primary    boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT instructor_department_terms_unique UNIQUE (term_id, instructor_id, department_id)
);

CREATE INDEX IF NOT EXISTS idt_term_dept_idx
  ON public.instructor_department_terms (term_id, department_id, is_primary);

ALTER TABLE public.instructor_department_terms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read instructor_department_terms" ON public.instructor_department_terms;
CREATE POLICY "Authenticated users can read instructor_department_terms"
  ON public.instructor_department_terms FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "SAO admins write instructor_department_terms" ON public.instructor_department_terms;
CREATE POLICY "SAO admins write instructor_department_terms"
  ON public.instructor_department_terms FOR ALL TO authenticated
  USING (public.is_sao_admin()) WITH CHECK (public.is_sao_admin());


-- ── STEP 5: the snapshot function ───────────────────────────────────────────
-- Idempotent, so it is safe to call on every term switch and again as a
-- backfill. Returns how many rows it actually added.
--
-- SECURITY DEFINER so it can read instructor_departments regardless of the
-- caller's own policies. It takes no user-supplied data beyond a term id that
-- must already exist -- the foreign key enforces that -- so there is nothing
-- to inject.
CREATE OR REPLACE FUNCTION public.snapshot_term_departments(p_term_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  inserted int;
BEGIN
  IF p_term_id IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO public.instructor_department_terms
    (term_id, instructor_id, department_id, is_primary)
  SELECT p_term_id, d.instructor_id, d.department_id, d.is_primary
  FROM public.instructor_departments d
  ON CONFLICT (term_id, instructor_id, department_id) DO NOTHING;

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END
$fn$;

REVOKE ALL ON FUNCTION public.snapshot_term_departments(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.snapshot_term_departments(uuid) TO authenticated, service_role;


-- ── STEP 6: backfill every existing term ────────────────────────────────────
-- Who was in which department during 2024-2025 was never recorded, so current
-- membership is the best available answer for past terms. This does not
-- reconstruct history; it freezes it from today forward.
SELECT t.academic_year,
       t.semester,
       public.snapshot_term_departments(t.id) AS rows_added
FROM public.academic_terms t
ORDER BY t.academic_year, t.semester;


-- ============================================================================
-- Verification -- returns exactly one row, so "no rows returned" would mean the
-- query itself failed rather than "nothing found".
-- ============================================================================
--
-- SELECT jsonb_pretty(jsonb_build_object(
--   'write_policies_want_3', (SELECT count(*) FROM pg_policies
--      WHERE schemaname='public' AND tablename='instructor_departments'
--        AND cmd <> 'SELECT'),
--   'permissive_writes_want_0', (SELECT count(*) FROM pg_policies
--      WHERE schemaname='public' AND tablename='instructor_departments'
--        AND cmd <> 'SELECT'
--        AND coalesce(qual,'') || coalesce(with_check,'') = 'true'),
--   'one_primary_index_want_1', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='instructor_departments_one_primary'),
--   'snapshot_fn_want_1', (SELECT count(*) FROM pg_proc p
--      JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname='public' AND p.proname='snapshot_term_departments'),
--   'snapshot_rows', (SELECT count(*) FROM public.instructor_department_terms),
--   'terms_snapshotted', (SELECT count(DISTINCT term_id) FROM public.instructor_department_terms),
--   'search_path_pinned_want_2', (SELECT count(*) FROM pg_proc p
--      JOIN pg_namespace n ON n.oid = p.pronamespace
--      WHERE n.nspname='public' AND p.proname IN ('is_sao','is_sao_admin')
--        AND array_to_string(coalesce(p.proconfig, '{}'), ',') LIKE '%search_path%')
-- ));
--
-- Audit query for the STEP 3 guard, if it ever aborts:
--
-- SELECT u.first_name || ' ' || u.last_name AS instructor,
--        u.university_id,
--        u.account_status,
--        count(*) AS primary_rows,
--        jsonb_agg(jsonb_build_object('dept', dn.d_name, 'code', dn.d_code)
--                  ORDER BY dn.d_name) AS primary_departments
-- FROM public.instructor_departments d
-- JOIN public.user_info u ON u.id = d.instructor_id
-- LEFT JOIN public.department_name dn ON dn.id = d.department_id
-- WHERE d.is_primary
-- GROUP BY u.id, u.first_name, u.last_name, u.university_id, u.account_status
-- HAVING count(*) > 1
-- ORDER BY instructor;
-- ============================================================================
