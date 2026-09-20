-- ============================================================
-- Migration: SAO Admin & Dashboard RLS Fixes
-- Description: Ensures SAO admins can view all dashboard data. 
-- Also fixes missing/broken RLS policies for student_remarks,
-- ensuring Instructors and Deans can see feedback.
-- ============================================================

-- 1. Ensure RLS is enabled on all critical tables
ALTER TABLE public.student_remarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instructor_ai_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instructor_wordcloud ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.management_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.performance_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overall_total_survey ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overall_question_means ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. STUDENT REMARKS POLICIES (Instructors, Deans, SAO)
-- ============================================================

-- Drop existing to cleanly recreate
DROP POLICY IF EXISTS "Instructors can view own student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "Deans can view department student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "SAO admins can view all student remarks" ON public.student_remarks;

CREATE POLICY "Instructors can view own student remarks" ON public.student_remarks
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department student remarks" ON public.student_remarks
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE "Department_name_ID" IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "SAO admins can view all student remarks" ON public.student_remarks
FOR SELECT USING (
  EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid())
);

-- ============================================================
-- 3. SAO ADMIN POLICIES FOR ALL OTHER DASHBOARD TABLES
-- (Allows SAO admins to view the dashboards of any instructor)
-- ============================================================

DO $$
BEGIN
  -- AI Suggestions
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'instructor_ai_suggestions' AND policyname = 'SAO admins can view all AI suggestions') THEN
    CREATE POLICY "SAO admins can view all AI suggestions" ON public.instructor_ai_suggestions
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Wordcloud
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'instructor_wordcloud' AND policyname = 'SAO admins can view all wordclouds') THEN
    CREATE POLICY "SAO admins can view all wordclouds" ON public.instructor_wordcloud
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Management Results
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'management_results' AND policyname = 'SAO admins can view all management results') THEN
    CREATE POLICY "SAO admins can view all management results" ON public.management_results
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Performance Results
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'performance_results' AND policyname = 'SAO admins can view all performance results') THEN
    CREATE POLICY "SAO admins can view all performance results" ON public.performance_results
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Overall Total Survey
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'overall_total_survey' AND policyname = 'SAO admins can view all overall surveys') THEN
    CREATE POLICY "SAO admins can view all overall surveys" ON public.overall_total_survey
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Overall Question Means
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'overall_question_means' AND policyname = 'SAO admins can view all question means') THEN
    CREATE POLICY "SAO admins can view all question means" ON public.overall_question_means
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Subjects
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subjects' AND policyname = 'SAO admins can view all subjects') THEN
    CREATE POLICY "SAO admins can view all subjects" ON public.subjects
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

  -- Intervention Reports
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'intervention_reports' AND policyname = 'SAO admins can view all intervention reports') THEN
    CREATE POLICY "SAO admins can view all intervention reports" ON public.intervention_reports
      FOR SELECT USING (EXISTS (SELECT 1 FROM public."Sao_users" WHERE user_id = auth.uid()));
  END IF;

END $$;
