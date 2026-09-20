-- 20240130000019_one_department_per_name_and_code.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- Same reason as 000008, 000014, 000016, 000017 and 000018:
-- 20240130000000_initial_schema.sql is a generated schema DUMP, not a runnable
-- migration, so a push would try to replay it. Every migration from 000002
-- onward was pasted in by hand.
--
--
-- THE RULE
-- A department name is unique, and so is a department code. Both normalised:
-- lower(btrim(d_name)) and upper(btrim(d_code)).
--
--
-- WHY
-- department_name had a primary key and nothing else. The Manage Departments
-- screen carried the only guard, and it had four holes:
--
--   1. It ran ONLY when adding. The edit path had no check at all, so renaming
--      one department onto another's exact name simply succeeded.
--   2. It checked ONLY d_name. A reused CODE was never looked at.
--   3. It used .ilike('d_name', name), which treats _ and % in the typed name
--      as wildcards -- so a name containing either matched the wrong set.
--   4. It used .maybeSingle(), which THROWS on more than one match. Once two
--      departments shared a name, every later add of that name surfaced as a
--      raw "Error: ..." rather than as a refusal.
--
-- All four are fixed in manage_departments_screen.dart, which now checks both
-- fields on both paths and names the department holding the conflict. This
-- migration is the part a Dart check cannot be: department_name is reachable
-- over the REST API with the publishable key and an SAO admin session, and any
-- check-then-insert is a race -- two admins adding the same department
-- milliseconds apart both read "free" and both write.
--
--
-- WHY NORMALISED, AND WHY THE CODE INDEX IS PARTIAL
-- Names were stored as typed. A plain UNIQUE (d_name) would let "College of
-- Technology" and "college of  technology" coexist, which is the same
-- split-faculty problem wearing a different hat: department averages, the
-- faculty roster and subject analytics all resolve through a single
-- department_name row, so two rows for one department divide its staff between
-- them. The Dart check normalises identically (_normName / _normCode).
--
-- d_code arrived in migration 000007 as `text DEFAULT ''`, so rows predating it
-- legitimately hold an empty code. A blank is not an identity and several rows
-- may share it, hence WHERE btrim(d_code) <> '' on that index only.
--
-- Existing stored values are deliberately NOT rewritten: d_code is displayed
-- verbatim in the roster and on report headers, and d_name is what every
-- screen shows. The indexes do not require it.
--
--
-- IF STEP 0 RETURNS ROWS
-- Which problem it is matters, and the two look alike in the audit output.
--
--   Duplicated CODE, names distinct -- the common case, and the cheap one.
--     Two real departments both picked the same abbreviation. Nothing is
--     shared and nothing moves: give one of them a different d_code and
--     re-run. The app's Edit Department does it, or:
--       UPDATE public.department_name SET d_code = '<new>' WHERE id = <id>;
--
--   Duplicated NAME -- two rows for ONE department, which is the case worth
--     being careful about. One row has to absorb the other's members,
--     subjects, memberships and term snapshots before the loser can be
--     renamed out of the way. Departments cannot be deleted: migration 000014
--     added department_name_no_delete precisely because four foreign keys
--     point here and one of them CASCADEs.
--
-- The audit below reports name_holders and code_holders separately, and counts
-- what hangs off each row, so the choice is informed rather than a guess.
--
-- RUN STEP 0 ON ITS OWN FIRST and read the output. The SQL Editor shows only
-- the last statement's result, so running the whole file at once hides it.
-- ============================================================================


-- ── STEP 0: audit. Run this alone, before anything below. ───────────────────
-- Every name or code held by more than one department, with what is attached to
-- each row. Expect zero rows.
WITH dupes AS (
  SELECT d.*,
         count(*) OVER (PARTITION BY lower(btrim(d.d_name)))  AS name_holders,
         CASE WHEN btrim(d.d_code) = '' THEN 1
              ELSE count(*) OVER (PARTITION BY upper(btrim(d.d_code)))
         END                                                  AS code_holders
  FROM public.department_name d
)
SELECT dupes.id                                        AS department_id,
       dupes.d_name                                    AS stored_name,
       dupes.d_code                                    AS stored_code,
       dupes.name_holders,
       dupes.code_holders,
       (SELECT count(*) FROM public.department_table t
         WHERE t."Department_name_ID" = dupes.id)      AS members,
       (SELECT count(*) FROM public.subjects s
         WHERE s.department_id = dupes.id)             AS subjects,
       (SELECT count(*) FROM public.instructor_departments i
         WHERE i.department_id = dupes.id)             AS memberships,
       (SELECT count(*) FROM public.instructor_department_terms i
         WHERE i.department_id = dupes.id)             AS term_snapshots,
       dupes.created_at
FROM dupes
WHERE dupes.name_holders > 1 OR dupes.code_holders > 1
ORDER BY lower(btrim(dupes.d_name)), dupes.created_at;


-- ── STEP 1: unique name, unique code ────────────────────────────────────────
-- Guarded so a duplicate reports readably instead of failing inside the index
-- build, and reports the two cases separately -- they are resolved differently.
DO $guard$
DECLARE
  dupe_names int;
  dupe_codes int;
BEGIN
  SELECT count(*) INTO dupe_names FROM (
    SELECT lower(btrim(d_name))
    FROM public.department_name
    GROUP BY lower(btrim(d_name))
    HAVING count(*) > 1
  ) d;

  SELECT count(*) INTO dupe_codes FROM (
    SELECT upper(btrim(d_code))
    FROM public.department_name
    WHERE btrim(d_code) <> ''
    GROUP BY upper(btrim(d_code))
    HAVING count(*) > 1
  ) d;

  -- Reported separately, and with different advice, because they are different
  -- problems. A duplicated NAME means two rows for ONE department, so one has
  -- to absorb the other's members and subjects before it can be renamed. A
  -- duplicated CODE alongside distinct names is only an abbreviation
  -- collision: two real departments that both picked "CS". Nothing moves --
  -- one of them just needs a different code.
  IF dupe_names > 0 THEN
    RAISE EXCEPTION
      'Cannot add the department uniqueness indexes yet: % duplicated name(s), and % duplicated code(s). A duplicated NAME means two rows for the same department: run STEP 0, decide which survives, move its members and subjects across, then rename the other. Re-run this file afterwards.',
      dupe_names, dupe_codes;
  END IF;

  IF dupe_codes > 0 THEN
    RAISE EXCEPTION
      'Cannot add the department uniqueness indexes yet: % duplicated code(s) (names are all unique). These are separate departments sharing an abbreviation, so nothing needs moving -- run STEP 0, pick one, and give it a different d_code. Re-run this file afterwards.',
      dupe_codes;
  END IF;
END
$guard$;

CREATE UNIQUE INDEX IF NOT EXISTS department_name_one_per_name
  ON public.department_name (lower(btrim(d_name)));

-- Partial: a blank code is not an identity, and rows predating migration 07
-- carry one by default.
CREATE UNIQUE INDEX IF NOT EXISTS department_name_one_per_code
  ON public.department_name (upper(btrim(d_code)))
  WHERE btrim(d_code) <> '';

COMMENT ON INDEX public.department_name_one_per_name IS
  'A department name identifies exactly one department. Normalised so that '
  '"College of Technology" and "college of  technology" cannot become two '
  'departments splitting one faculty between them. Matches _normName in '
  'manage_departments_screen.dart.';

COMMENT ON INDEX public.department_name_one_per_code IS
  'A department code identifies exactly one department. Partial: d_code was '
  'added by migration 000007 with DEFAULT '''', so blanks are allowed to '
  'repeat. Matches _normCode in manage_departments_screen.dart.';


-- ============================================================================
-- Verification -- returns exactly one row, so "no rows returned" would mean the
-- query itself failed rather than "nothing found".
-- ============================================================================
--
-- SELECT jsonb_pretty(jsonb_build_object(
--   'duplicate_names_want_0', (SELECT count(*) FROM (
--      SELECT lower(btrim(d_name)) FROM public.department_name
--      GROUP BY lower(btrim(d_name)) HAVING count(*) > 1) x),
--   'duplicate_codes_want_0', (SELECT count(*) FROM (
--      SELECT upper(btrim(d_code)) FROM public.department_name
--      WHERE btrim(d_code) <> ''
--      GROUP BY upper(btrim(d_code)) HAVING count(*) > 1) x),
--   'name_index_want_1', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='department_name_one_per_name'),
--   'code_index_want_1', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public' AND indexname='department_name_one_per_code'),
--   'departments', (SELECT count(*) FROM public.department_name),
--   'blank_codes', (SELECT count(*) FROM public.department_name
--      WHERE btrim(d_code) = '')
-- ));
--
-- blank_codes is informational. Those rows are exempt from the code index, so
-- an SAO admin can still create two codeless departments -- the name index is
-- what stops that being a duplicate. Filling them in is a data task, not a
-- schema one.
--
-- To confirm the indexes actually refuse a duplicate:
--
--   begin;
--   insert into public.department_name (d_name, d_code)
--   select lower(d_name), d_code from public.department_name
--    where btrim(d_code) <> '' limit 1;
--   rollback;   -- expect: unique_violation on department_name_one_per_name
-- ============================================================================
