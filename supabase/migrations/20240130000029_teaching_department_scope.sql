-- Department heads see subjects by the department of the INSTRUCTOR who teaches
-- the class, not the subject's owning program (subjects.department_id).
-- Subjects with no instructor appear for no head. Co-taught subjects: each head
-- sees only their own department's instructors' results.

-- Department an instructor taught for in a term: the term snapshot (primary)
-- if present, else the current primary instructor_departments row.
CREATE OR REPLACE FUNCTION public.teaching_department_id(p_instructor uuid, p_term uuid)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER  -- also called from RLS policies (030) where the caller cannot read these tables
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT t.department_id
       FROM public.instructor_department_terms t
      WHERE t.instructor_id = p_instructor
        AND t.term_id = p_term
        AND t.is_primary
      ORDER BY t.id
      LIMIT 1),
    (SELECT d.department_id
       FROM public.instructor_departments d
      WHERE d.instructor_id = p_instructor
        AND d.is_primary
      ORDER BY d.department_id
      LIMIT 1)
  );
$$;

-- Return type may differ from an earlier draft, so drop first (idempotent re-run).
DROP FUNCTION IF EXISTS public.dept_head_subject_analytics(uuid);

-- One row per (subject, instructor) the calling head's department teaches in the
-- term, with that class's management/performance means and remark tone counts.
CREATE OR REPLACE FUNCTION public.dept_head_subject_analytics(p_term_id uuid DEFAULT NULL)
RETURNS TABLE (
  subject_id               uuid,
  subject_code             text,
  subject_name             text,
  owner_department_id      bigint,
  owner_d_code             text,
  instructor_id            uuid,
  instructor_first_name    text,
  instructor_last_name     text,
  overall_management_mean  numeric,
  overall_performance_mean numeric,
  total_responses          integer,
  remark_positive          bigint,
  remark_neutral           bigint,
  remark_critical          bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_term uuid;
  v_dept bigint;
BEGIN
  IF NOT public.is_dept_head() THEN
    RETURN;
  END IF;

  v_dept := public.get_my_dept_id();
  IF v_dept IS NULL THEN
    RETURN;
  END IF;

  v_term := COALESCE(p_term_id,
                     (SELECT s.current_term_id FROM public.system_settings s LIMIT 1));
  IF v_term IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    sub.id,
    sub.subject_code,
    sub.subject_name,
    sub.department_id,
    od.d_code,
    i.instructor_id,
    ui.first_name,
    ui.last_name,
    mr.overall_management_mean,
    pr.overall_performance_mean,
    mr.total_responses,
    (SELECT count(*) FROM public.student_remarks r
      WHERE r.instructor_id = i.instructor_id AND r.subject_id = sub.id
        AND r.term_id = v_term AND r.tone = 'Positive'),
    (SELECT count(*) FROM public.student_remarks r
      WHERE r.instructor_id = i.instructor_id AND r.subject_id = sub.id
        AND r.term_id = v_term AND r.tone = 'Neutral'),
    (SELECT count(*) FROM public.student_remarks r
      WHERE r.instructor_id = i.instructor_id AND r.subject_id = sub.id
        AND r.term_id = v_term AND r.tone = 'Critical')
  FROM public.instructor_subjects i
  JOIN public.subjects sub              ON sub.id = i.subject_id
  JOIN public.management_results mr     ON mr.instructor_id = i.instructor_id
                                       AND mr.subject_id = i.subject_id
                                       AND mr.term_id = v_term
  LEFT JOIN public.performance_results pr ON pr.instructor_id = i.instructor_id
                                       AND pr.subject_id = i.subject_id
                                       AND pr.term_id = v_term
  LEFT JOIN public.user_info ui         ON ui.id = i.instructor_id
  LEFT JOIN public.department_name od   ON od.id = sub.department_id
  WHERE i.term_id = v_term
    AND i.instructor_id <> auth.uid()   -- the head's own classes are excluded
    AND public.teaching_department_id(i.instructor_id, v_term) = v_dept;
END;
$$;

REVOKE ALL ON FUNCTION public.dept_head_subject_analytics(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.teaching_department_id(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dept_head_subject_analytics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaching_department_id(uuid, uuid) TO authenticated;
