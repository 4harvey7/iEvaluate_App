-- Lock down SELECT on student_remarks. Before: allow_view_remarks (true) and
-- "Authenticated users can view student remarks" exposed every remark to everyone
-- (even anon). Requires 029 (teaching_department_id).
-- Allowed after this: instructor reads own; dept head/dean reads remarks of
-- instructors who teach for their department in the remark's term; SAO admin reads all.
-- INSERT/UPDATE/DELETE policies are intentionally untouched (n8n writes via direct
-- Postgres connection, which bypasses RLS).

ALTER TABLE public.student_remarks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_view_remarks"                           ON public.student_remarks;
DROP POLICY IF EXISTS "Authenticated users can view student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "Allow leadership to read student remarks"     ON public.student_remarks;
DROP POLICY IF EXISTS "Instructors can view own student remarks"     ON public.student_remarks;
DROP POLICY IF EXISTS "Instructors can view their own student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "remarks: instructor reads own"                ON public.student_remarks;
DROP POLICY IF EXISTS "remarks: dept head reads dept"                ON public.student_remarks;
DROP POLICY IF EXISTS "remarks: sao reads all"                       ON public.student_remarks;
DROP POLICY IF EXISTS "remarks: sao admin reads all"                 ON public.student_remarks;

CREATE POLICY "remarks: instructor reads own" ON public.student_remarks
  FOR SELECT TO authenticated
  USING (instructor_id = auth.uid());

CREATE POLICY "remarks: dept head reads dept" ON public.student_remarks
  FOR SELECT TO authenticated
  USING (
    public.is_dept_head()
    AND public.teaching_department_id(instructor_id, term_id) = public.get_my_dept_id()
  );

CREATE POLICY "remarks: sao admin reads all" ON public.student_remarks
  FOR SELECT TO authenticated
  USING (public.is_sao_admin());
