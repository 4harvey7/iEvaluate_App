-- Resolve the subject for a scanned form, and assign it to the instructor if
-- it is not assigned yet.
--
-- $1 = instructor_id (uuid, may arrive empty)   $2 = subject text off the form
--
-- ORDER OF EVIDENCE
--   1. Exact subject_code match after normalisation (case, spaces and
--      punctuation stripped). This is strong evidence, so it wins outright --
--      and if the instructor has no assignment for it this term, one is
--      created. That is the auto-assign.
--   2. Otherwise the best FUZZY match among the subjects already assigned to
--      this instructor, and only above 0.55. Restricted to already-assigned
--      subjects on purpose: fuzzy matching across the whole catalogue produces
--      false hits (a form reading "MATH 101" scores 0.571 against "CC 101"
--      because the digits match), and an assignment created from a false hit
--      becomes permanent as soon as a survey lands on it.
--   3. Otherwise no row, and the caller's existing flag/review path handles it.
--
-- WHY THE args CTE
-- "get instructor id" is set to output an empty item when a name matches
-- nobody, so $1 arrives as '' rather than a uuid. A bare $1::uuid raises
-- "invalid input syntax for type uuid" and takes the whole branch down with
-- it -- all 148 forms, not just the unmatched one. NULLIF turns that into a
-- NULL this query can reason about, and an unmatched instructor falls through
-- to case 3 above instead of erroring.
WITH args AS (
  SELECT NULLIF($1, '')::uuid AS instructor_id,
         COALESCE($2, '')     AS subject_raw
),
term AS (
  SELECT current_term_id AS tid FROM public.system_settings LIMIT 1
),
exact_match AS (
  SELECT s.id AS subject_id, s.subject_code, s.subject_name, s.department_id
  FROM public.subjects s
  CROSS JOIN args a
  WHERE upper(regexp_replace(COALESCE(s.subject_code, ''), '[^A-Za-z0-9]', '', 'g'))
      = upper(regexp_replace(a.subject_raw,                '[^A-Za-z0-9]', '', 'g'))
    AND length(regexp_replace(a.subject_raw, '[^A-Za-z0-9]', '', 'g')) >= 3
),
-- Guard against an ambiguous catalogue: two codes normalising to the same
-- string would make the choice arbitrary, so neither is used.
exact_one AS (
  SELECT * FROM exact_match WHERE (SELECT count(*) FROM exact_match) = 1
),
ensure_assignment AS (
  INSERT INTO public.instructor_subjects (subject_id, instructor_id, term_id)
  SELECT e.subject_id, a.instructor_id, (SELECT tid FROM term)
  FROM exact_one e
  CROSS JOIN args a
  WHERE a.instructor_id IS NOT NULL
    AND (SELECT tid FROM term) IS NOT NULL
  ON CONFLICT (subject_id, instructor_id, term_id) DO NOTHING
  RETURNING subject_id
),
fuzzy_assigned AS (
  SELECT s.id AS subject_id, s.subject_code, s.subject_name, s.department_id,
         word_similarity(COALESCE(s.subject_code, ''), a.subject_raw) AS score
  FROM public.subjects s
  CROSS JOIN args a
  JOIN public.instructor_subjects ins
    ON ins.subject_id = s.id
   AND ins.instructor_id = a.instructor_id
   AND ins.term_id = (SELECT tid FROM term)
  WHERE NOT EXISTS (SELECT 1 FROM exact_one)
    AND a.instructor_id IS NOT NULL
    AND word_similarity(COALESCE(s.subject_code, ''), a.subject_raw) > 0.55
  ORDER BY score DESC
  LIMIT 1
)
SELECT e.subject_id, e.subject_code, e.subject_name, e.department_id,
       a.instructor_id,
       1.0::float AS subject_match_score,
       'exact_code' AS match_kind,
       EXISTS (SELECT 1 FROM ensure_assignment) AS auto_assigned
FROM exact_one e
CROSS JOIN args a
WHERE a.instructor_id IS NOT NULL
UNION ALL
SELECT f.subject_id, f.subject_code, f.subject_name, f.department_id,
       a.instructor_id,
       f.score::float AS subject_match_score,
       'fuzzy_assigned' AS match_kind,
       false AS auto_assigned
FROM fuzzy_assigned f
CROSS JOIN args a
LIMIT 1;
