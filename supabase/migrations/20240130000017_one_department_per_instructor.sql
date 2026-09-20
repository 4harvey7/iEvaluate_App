-- 20240130000017_one_department_per_instructor.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- Same reason as 000008, 000014 and 000016: 20240130000000_initial_schema.sql
-- is a generated schema DUMP, not a runnable migration, so a push would try to
-- replay it. Every migration from 000002 onward was pasted in by hand.
--
--
-- THE RULE
-- An instructor belongs to exactly ONE department. instructor_departments
-- holds exactly one row per instructor, and is_primary on that row is always
-- true.
--
--
-- WHY
-- "Assign Second Department" is removed from SAO Admin > Users. The feature
-- wrote is_primary = false rows that no department head could ever read,
-- because every dean-facing RLS policy resolves department membership through
-- department_table -- which only ever holds the home department:
--
--   "Deans can view department faculty profiles" ON user_info
--   "Deans can view department overall survey"   ON overall_total_survey
--   "Deans can view department subjects"         ON subjects
--   plus the matching management_results and performance_results policies
--
-- No policy anywhere resolves membership through instructor_departments. So
-- the second head could not read the instructor's user_info row at all, let
-- alone their score: the faculty roster joins instructor_departments correctly
-- but RLS filtered the instructor straight back out, and the roster would have
-- rendered 0.0 even if the name had got through. The link was written, shown
-- back to SAO Admin (who holds a full-access policy, which is why it looked
-- like it worked), and had no other effect anywhere in the app.
--
-- The department average and the performance trend chart already filtered
-- is_primary = true deliberately, so that one instructor is never counted into
-- two department averages. That behaviour is unchanged.
--
--
-- WHAT THIS DOES NOT TOUCH
-- Subject assignment is a different axis. instructor_subjects still lets an
-- instructor teach a subject owned by another department: the instructor sees
-- it on their own dashboard, and Subject Analytics attributes it to the
-- department that OWNS the subject (getSubjectAnalyticsForDept), so a visiting
-- instructor still appears to that department's head.
--
-- instructor_departments itself is NOT dropped. It is not the "second
-- department" table -- it is how the faculty roster and the department
-- dashboard resolve primary membership. Dropping it would empty every
-- department head's roster.
--
--
-- WHAT THIS DELETES
-- Every is_primary = false row in instructor_departments, and the matching
-- rows in the instructor_department_terms snapshot. Nothing reads either one
-- today -- the trend query filters is_primary = true -- but they would
-- otherwise sit in a schema that now forbids them.
--
-- RUN STEP 0 ON ITS OWN FIRST and read the output. The SQL Editor shows only
-- the last statement's result, so running the whole file at once hides it.
-- ============================================================================


-- ── STEP 0: audit. Run this alone, before anything below. ───────────────────
-- Lists exactly what STEP 1 will delete. Expect zero rows.
SELECT u.first_name || ' ' || u.last_name AS instructor,
       u.university_id,
       u.employment_status,
       u.account_status,
       dn.d_name                          AS secondary_department,
       dn.d_code                          AS secondary_code,
       d.created_at                       AS linked_at
FROM public.instructor_departments d
JOIN public.user_info u             ON u.id  = d.instructor_id
LEFT JOIN public.department_name dn ON dn.id = d.department_id
WHERE NOT d.is_primary
ORDER BY instructor, secondary_department;


-- ── STEP 1: remove the secondary links ──────────────────────────────────────
-- Counted and announced before deleting, so the Messages pane records what went
-- even when the audit above was skipped.
DO $step1$
DECLARE
  victims int;
BEGIN
  SELECT count(*) INTO victims
  FROM public.instructor_departments
  WHERE NOT is_primary;

  IF victims = 0 THEN
    RAISE NOTICE 'STEP 1: no secondary department links found. Nothing to delete.';
  ELSE
    RAISE NOTICE 'STEP 1: deleting % secondary department link(s).', victims;
    DELETE FROM public.instructor_departments WHERE NOT is_primary;
  END IF;
END
$step1$;


-- ── STEP 2: one row per instructor, and that row is the primary ─────────────
-- Guarded so a leftover violation reports readably instead of failing inside
-- the index build. After STEP 1 the only way to trip this is an instructor with
-- two PRIMARY rows, which migration 10's partial index already forbids -- the
-- guard is for environments where that index was never created.
DO $guard$
DECLARE offenders int;
BEGIN
  SELECT count(*) INTO offenders FROM (
    SELECT instructor_id
    FROM public.instructor_departments
    GROUP BY instructor_id
    HAVING count(*) > 1
  ) d;

  IF offenders > 0 THEN
    RAISE EXCEPTION
      'Cannot add the one-department index yet: % instructor(s) still have more than one department row. Run the audit query at the bottom of this file to see who.',
      offenders;
  END IF;
END
$guard$;

-- The new guarantee. Created before the old partial index is dropped, so there
-- is no window in which neither constraint holds.
CREATE UNIQUE INDEX IF NOT EXISTS instructor_departments_one_department
  ON public.instructor_departments (instructor_id);

-- Superseded: (instructor_id) WHERE is_primary is implied by the above.
DROP INDEX IF EXISTS public.instructor_departments_one_primary;

-- is_primary is now structurally always true. Kept as a column rather than
-- dropped, because instructor_department_terms mirrors it and both
-- evaluation_service and the faculty roster still filter on it. A NOT NULL
-- DEFAULT true column costs nothing.
DO $chk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'instructor_departments_primary_only'
      AND conrelid = 'public.instructor_departments'::regclass
  ) THEN
    ALTER TABLE public.instructor_departments
      ADD CONSTRAINT instructor_departments_primary_only CHECK (is_primary);
  END IF;
END
$chk$;

COMMENT ON TABLE public.instructor_departments IS
  'One row per instructor: the single department they belong to. is_primary is '
  'always true, kept only because the term snapshot and the roster queries '
  'filter on it. Secondary departments were removed in migration 000017.';

-- Note: instructor_departments_unique (instructor_id, department_id) from
-- migration 06 is now redundant, since (instructor_id) alone is unique. Left in
-- place -- dropping it buys nothing, and one fewer moving part is worth more.


-- ── STEP 3: the per-term snapshot ───────────────────────────────────────────
-- snapshot_term_departments copies is_primary straight from
-- instructor_departments, so every future snapshot is primary-only already.
-- This clears the historic secondary rows. The trend query filters
-- is_primary = true, so no chart changes.
DO $step3$
DECLARE
  victims int;
BEGIN
  IF to_regclass('public.instructor_department_terms') IS NULL THEN
    RAISE NOTICE 'STEP 3: instructor_department_terms does not exist (migration 10 not applied). Skipped.';
    RETURN;
  END IF;

  SELECT count(*) INTO victims
  FROM public.instructor_department_terms
  WHERE NOT is_primary;

  IF victims = 0 THEN
    RAISE NOTICE 'STEP 3: no secondary rows in the term snapshot. Nothing to delete.';
  ELSE
    RAISE NOTICE 'STEP 3: deleting % secondary snapshot row(s).', victims;
    DELETE FROM public.instructor_department_terms WHERE NOT is_primary;
  END IF;
END
$step3$;


-- ============================================================================
-- Verification -- returns exactly one row, so "no rows returned" would mean the
-- query itself failed rather than "nothing found".
-- ============================================================================
--
-- SELECT jsonb_pretty(jsonb_build_object(
--   'secondary_links_want_0', (SELECT count(*) FROM public.instructor_departments
--      WHERE NOT is_primary),
--   'instructors_with_2plus_depts_want_0', (SELECT count(*) FROM (
--      SELECT instructor_id FROM public.instructor_departments
--      GROUP BY instructor_id HAVING count(*) > 1) x),
--   'one_department_index_want_1', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='instructor_departments_one_department'),
--   'old_one_primary_index_want_0', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='instructor_departments_one_primary'),
--   'primary_only_check_want_1', (SELECT count(*) FROM pg_constraint
--      WHERE conname='instructor_departments_primary_only'),
--   'secondary_snapshot_rows_want_0', (SELECT count(*)
--      FROM public.instructor_department_terms WHERE NOT is_primary),
--   'total_links', (SELECT count(*) FROM public.instructor_departments),
--   'instructors_linked', (SELECT count(DISTINCT instructor_id)
--      FROM public.instructor_departments)
-- ));
--
-- Audit query for the STEP 2 guard, if it ever aborts:
--
-- SELECT u.first_name || ' ' || u.last_name AS instructor,
--        u.university_id,
--        u.account_status,
--        count(*) AS department_rows,
--        jsonb_agg(jsonb_build_object('dept', dn.d_name, 'primary', d.is_primary)
--                  ORDER BY dn.d_name) AS departments
-- FROM public.instructor_departments d
-- JOIN public.user_info u ON u.id = d.instructor_id
-- LEFT JOIN public.department_name dn ON dn.id = d.department_id
-- GROUP BY u.id, u.first_name, u.last_name, u.university_id, u.account_status
-- HAVING count(*) > 1
-- ORDER BY instructor;
-- ============================================================================
