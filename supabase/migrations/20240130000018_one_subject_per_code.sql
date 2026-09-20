-- 20240130000018_one_subject_per_code.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- Same reason as 000008, 000014, 000016 and 000017:
-- 20240130000000_initial_schema.sql is a generated schema DUMP, not a runnable
-- migration, so a push would try to replay it. Every migration from 000002
-- onward was pasted in by hand.
--
--
-- THE RULE
-- A subject code identifies exactly ONE subject. upper(btrim(subject_code)) is
-- unique across the table.
--
--
-- WHY
-- subjects had no unique constraint of any kind on subject_code, and the Manage
-- Subjects form treated the code as a key anyway: it looked the code up and, on
-- a hit, UPDATED that subject's name and department to whatever had just been
-- typed. So entering an existing code with a different name silently rewrote a
-- shared record -- for every term, and for every other instructor assigned to
-- it -- and reported success. There was no duplicate to see afterwards, which
-- is why it went unnoticed.
--
-- The lookup also used .maybeSingle(), which THROWS when it matches more than
-- one row. Nothing stopped the n8n bulk import from creating a second row with
-- the same code, and once it had, the manual add form raised an error on every
-- save for that code.
--
-- Both paths are now guarded in Dart (manage_subjects_screen refuses a fresh
-- add on a taken code and names the subject holding it), but the bulk import
-- runs outside the app and instructor_subjects/subjects are reachable over the
-- REST API with the publishable key. A Dart check alone is advisory.
--
--
-- WHY THE EXPRESSION, NOT THE COLUMN
-- Codes were stored however they arrived: the form upper-cases and trims on
-- save, the n8n import does not. A plain UNIQUE (subject_code) would let
-- "ias 301" and "IAS 301" coexist as different subjects, which is the same
-- split-results problem wearing a different hat. Indexing
-- upper(btrim(subject_code)) closes that, and the Dart check normalises
-- identically (_normCode) so the two can never disagree about what counts as
-- taken.
--
-- Existing stored codes are deliberately NOT rewritten. The scanner matches
-- subject codes exactly (see the exact-code matching work in
-- 3077ab6), so normalising the data in place is a separate decision with its
-- own blast radius. The index does not require it.
--
--
-- WHAT THIS BLOCKS THAT MIGHT BE LEGITIMATE
-- Two departments running genuinely different courses under the SAME code can
-- no longer both exist. If STEP 0 returns rows, that is the case to look at
-- before going further -- one of them needs a distinct code.
--
-- RUN STEP 0 ON ITS OWN FIRST and read the output. The SQL Editor shows only
-- the last statement's result, so running the whole file at once hides it.
-- ============================================================================


-- ── STEP 0: audit. Run this alone, before anything below. ───────────────────
-- Every code held by more than one subject row, with how much is attached to
-- each. Expect zero rows. If it returns any, DO NOT merge them blindly: the
-- row with assignments and results is the one to keep, and the other's
-- assignments have to be repointed by hand before it can be deleted.
SELECT upper(btrim(s.subject_code))                      AS normalised_code,
       s.id                                             AS subject_id,
       s.subject_code                                   AS stored_code,
       s.subject_name,
       dn.d_name                                        AS department,
       (SELECT count(*) FROM public.instructor_subjects i
         WHERE i.subject_id = s.id)                     AS assignments,
       (SELECT count(*) FROM public.management_results r
         WHERE r.subject_id = s.id)                     AS management_rows,
       (SELECT count(*) FROM public.performance_results r
         WHERE r.subject_id = s.id)                     AS performance_rows,
       (SELECT count(*) FROM public.student_remarks r
         WHERE r.subject_id = s.id)                     AS remark_rows,
       s.created_at
FROM public.subjects s
LEFT JOIN public.department_name dn ON dn.id = s.department_id
WHERE upper(btrim(s.subject_code)) IN (
        SELECT upper(btrim(subject_code))
        FROM public.subjects
        GROUP BY upper(btrim(subject_code))
        HAVING count(*) > 1
      )
ORDER BY normalised_code, s.created_at;


-- ── STEP 1: one subject per code ────────────────────────────────────────────
-- Guarded so a duplicate reports readably instead of failing inside the index
-- build. Deliberately does NOT resolve duplicates itself: picking a survivor
-- means repointing instructor_subjects, management_results,
-- performance_results and student_remarks, and guessing wrong there silently
-- moves a real student's evaluation onto the wrong subject.
DO $guard$
DECLARE offenders int;
BEGIN
  SELECT count(*) INTO offenders FROM (
    SELECT upper(btrim(subject_code))
    FROM public.subjects
    GROUP BY upper(btrim(subject_code))
    HAVING count(*) > 1
  ) d;

  IF offenders > 0 THEN
    RAISE EXCEPTION
      'Cannot add the one-subject-per-code index yet: % code(s) are held by more than one subject row. Run STEP 0 to see which, decide which row survives, repoint its assignments and results, then re-run this file.',
      offenders;
  END IF;
END
$guard$;

CREATE UNIQUE INDEX IF NOT EXISTS subjects_one_per_code
  ON public.subjects (upper(btrim(subject_code)));

COMMENT ON INDEX public.subjects_one_per_code IS
  'A subject code identifies exactly one subject. Normalised so that '
  '"ias 301" and "IAS 301" cannot become two subjects splitting one course''s '
  'evaluation results between them. Matches _normCode in '
  'manage_subjects_screen.dart.';


-- ============================================================================
-- Verification -- returns exactly one row, so "no rows returned" would mean the
-- query itself failed rather than "nothing found".
-- ============================================================================
--
-- SELECT jsonb_pretty(jsonb_build_object(
--   'duplicate_codes_want_0', (SELECT count(*) FROM (
--      SELECT upper(btrim(subject_code)) FROM public.subjects
--      GROUP BY upper(btrim(subject_code)) HAVING count(*) > 1) x),
--   'unique_index_want_1', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='subjects_one_per_code'),
--   'subjects', (SELECT count(*) FROM public.subjects),
--   'codes_needing_normalising', (SELECT count(*) FROM public.subjects
--      WHERE subject_code <> upper(btrim(subject_code)))
-- ));
--
-- The last figure is informational: those rows are stored unnormalised but are
-- still unique under the index. Rewriting them is a separate decision, because
-- the scanner matches subject codes exactly.
--
-- To confirm the index actually refuses a duplicate:
--
--   begin;
--   insert into public.subjects (subject_code, subject_name)
--   select lower(subject_code), 'duplicate probe' from public.subjects limit 1;
--   rollback;   -- expect: unique_violation on subjects_one_per_code
-- ============================================================================
