-- Lock down dept_faculty_active and dept_word_cloud.
-- Views stay definer-owned (postgres) so aggregates are complete, but rows are
-- filtered to the caller's department (dept head) or all (SAO admin).
-- anon: no access. authenticated: SELECT only.

CREATE OR REPLACE VIEW public.dept_faculty_active AS
SELECT dt."Department_name_ID" AS department_id,
       count(DISTINCT dt.user_id) FILTER (WHERE ui.account_status = ANY (ARRAY['Active'::text, 'approved'::text, 'Approved'::text])) AS active_count,
       count(DISTINCT dt.user_id) AS total_count
FROM public.department_table dt
JOIN public.user_info ui ON ui.id = dt.user_id
WHERE (public.is_dept_head() AND dt."Department_name_ID" = public.get_my_dept_id()) OR public.is_sao_admin()
GROUP BY dt."Department_name_ID";

CREATE OR REPLACE VIEW public.dept_word_cloud AS
SELECT dt."Department_name_ID" AS department_id,
       wc.word,
       wc.term_id,
       sum(wc.count) AS total_count
FROM public.instructor_wordcloud wc
JOIN public.department_table dt ON dt.user_id = wc.instructor_id
WHERE (public.is_dept_head() AND dt."Department_name_ID" = public.get_my_dept_id()) OR public.is_sao_admin()
GROUP BY dt."Department_name_ID", wc.word, wc.term_id;

REVOKE ALL ON public.dept_faculty_active FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dept_word_cloud FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.dept_faculty_active TO authenticated;
GRANT SELECT ON public.dept_word_cloud TO authenticated;
GRANT ALL ON public.dept_faculty_active TO service_role;
GRANT ALL ON public.dept_word_cloud TO service_role;
