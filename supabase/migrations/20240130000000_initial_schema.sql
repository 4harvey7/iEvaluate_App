-- User Info: Stores the core identity and profile details of the instructor (matches Supabase auth.users).
-- Subjects: Stores the individual classes or courses taught by the instructor.
-- Overall Total Survey: Stores the final, overall aggregated semester scores for an instructor (The Grand Master Dashboard).
-- Overall Question Means: Stores exactly 10 Management rows and 10 Performance rows per instructor containing the grand mean for each specific question.
-- Management Results: Stores the granular, class-by-class aggregated scores specifically for the Classroom Management category.
-- Performance Results: Stores the granular, class-by-class aggregated scores specifically for the Teaching Performance category.
-- Instructor AI Suggestions: Stores the AI-generated summaries and actionable teaching insights based on student feedback.
-- Student Remarks: Stores the raw, individual text comments left by students, along with their analyzed sentiment tone.
-- Instructor Wordcloud: Stores the frequency of specific keywords used in student remarks to generate a visual UI word cloud.

-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.user_info (
  id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  first_name text,
  last_name text,
  address text,
  email text,
  account_status text DEFAULT 'Pending'::text,
  university_id text,
  CONSTRAINT user_info_pkey PRIMARY KEY (id),
  CONSTRAINT user_info_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

CREATE TABLE public.department_table (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id uuid,
  Department_name_ID bigint,
  roles bigint,
  CONSTRAINT department_table_pkey PRIMARY KEY (id),
  CONSTRAINT department_table_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_info(id),
  CONSTRAINT department_table_roles_fkey FOREIGN KEY (roles) REFERENCES public.roles(id),
  CONSTRAINT department_table_Department_name_ID_fkey FOREIGN KEY (Department_name_ID) REFERENCES public.department_name(id)
);

CREATE TABLE public.roles (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  Roles text,
  CONSTRAINT roles_pkey PRIMARY KEY (id)
);

CREATE TABLE public.department_name (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  d_name text NOT NULL,
  CONSTRAINT department_name_pkey PRIMARY KEY (id)
);

CREATE TABLE public.Sao_users (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  role_id bigint,
  user_id uuid,
  CONSTRAINT Sao_users_pkey PRIMARY KEY (id),
  CONSTRAINT Sao_users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id),
  CONSTRAINT Sao_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_info(id)
);

CREATE TABLE public.admin_verifications (
  admin_id uuid NOT NULL,
  code text NOT NULL,
  expires_at timestamp with time zone DEFAULT (now() + '00:10:00'::interval),
  attempts integer DEFAULT 0,
  CONSTRAINT admin_verifications_pkey PRIMARY KEY (admin_id),
  CONSTRAINT admin_verifications_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id)
);

CREATE TABLE public.audit_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  action text NOT NULL,
  metadata jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id),
  CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_info(id)
);

CREATE TABLE public.academic_terms (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  semester text NOT NULL,
  academic_year text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academic_terms_pkey PRIMARY KEY (id)
);

CREATE TABLE public.system_settings (
  id integer NOT NULL DEFAULT 1 CHECK (id = 1),
  auto_sync boolean DEFAULT true,
  current_term_id uuid,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT system_settings_pkey PRIMARY KEY (id),
  CONSTRAINT system_settings_current_term_id_fkey FOREIGN KEY (current_term_id) REFERENCES public.academic_terms(id)
);

CREATE TABLE public.sast_results (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 integer, m2 integer, m3 integer, m4 integer, m5 integer,
  m6 integer, m7 integer, m8 integer, m9 integer, m10 integer,
  p1 integer, p2 integer, p3 integer, p4 integer, p5 integer,
  p6 integer, p7 integer, p8 integer, p9 integer, p10 integer,
  Remarks_and_Suggestions text,
  sao_staff_id uuid NOT NULL,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  raw_image_url text, -- To store the link from the scan if needed
  processing_status text DEFAULT 'pending', -- pending, completed, error
  CONSTRAINT sast_results_pkey PRIMARY KEY (id),
  CONSTRAINT sast_results_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_results_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES public.user_info(id),
  CONSTRAINT sast_results_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_results_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);

CREATE TABLE public.sast_all_raw_data_survey (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint,
  m6 bigint, m7 bigint, m8 bigint, m9 bigint, m10 bigint,
  p1 bigint, p2 bigint, p3 bigint, p4 bigint, p5 bigint,
  p6 bigint, p7 bigint, p8 bigint, p9 bigint, p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint,
  m6 bigint, m7 bigint, m8 bigint, m9 bigint, m10 bigint,
  p1 bigint, p2 bigint, p3 bigint, p4 bigint, p5 bigint,
  p6 bigint, p7 bigint, p8 bigint, p9 bigint, p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint,
  m6 bigint, m7 bigint, m8 bigint, m9 bigint, m10 bigint,
  p1 bigint, p2 bigint, p3 bigint, p4 bigint, p5 bigint,
  p6 bigint, p7 bigint, p8 bigint, p9 bigint, p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint, m2 bigint, m3 bigint, m4 bigint, m5 bigint,
  m6 bigint, m7 bigint, m8 bigint, m9 bigint, m10 bigint,
  p1 bigint, p2 bigint, p3 bigint, p4 bigint, p5 bigint,
  p6 bigint, p7 bigint, p8 bigint, p9 bigint, p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint,
  m2 bigint,
  m3 bigint,
  m4 bigint,
  m5 bigint,
  m6 bigint,
  m7 bigint,
  m8 bigint,
  m9 bigint,
  m10 bigint,
  p1 bigint,
  p2 bigint,
  p3 bigint,
  p4 bigint,
  p5 bigint,
  p6 bigint,
  p7 bigint,
  p8 bigint,
  p9 bigint,
  p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  m1 bigint,
  m2 bigint,
  m3 bigint,
  m4 bigint,
  m5 bigint,
  m6 bigint,
  m7 bigint,
  m8 bigint,
  m9 bigint,
  m10 bigint,
  p1 bigint,
  p2 bigint,
  p3 bigint,
  p4 bigint,
  p5 bigint,
  p6 bigint,
  p7 bigint,
  p8 bigint,
  p9 bigint,
  p10 bigint,
  Remarks_and_Suggestions text,
  sao_staff_id uuid,
  student_id text,
  instructor text,
  submitted_date date,
  instructor_ID uuid,
  term_id uuid,
  subject_id uuid,
  CONSTRAINT sast_all_raw_data_survey_pkey PRIMARY KEY (id),
  CONSTRAINT sast_all_raw_data_survey_sao_staff_id_fkey FOREIGN KEY (sao_staff_id) REFERENCES public.user_info(id),
  CONSTRAINT sast_all_raw_data_survey_instructor_ID_fkey FOREIGN KEY (instructor_ID) REFERENCES auth.users(id),
  CONSTRAINT fk_raw_results_term FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT sast_all_raw_data_survey_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);

CREATE TABLE public.management_results (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  total_responses integer NOT NULL,
  m1_total integer NOT NULL,
  m2_total integer NOT NULL,
  m3_total integer NOT NULL,
  m4_total integer NOT NULL,
  m5_total integer NOT NULL,
  m6_total integer NOT NULL,
  m7_total integer NOT NULL,
  m8_total integer NOT NULL,
  m9_total integer NOT NULL,
  m10_total integer NOT NULL,
  grand_total integer NOT NULL,
  m1_mean numeric NOT NULL,
  m2_mean numeric NOT NULL,
  m3_mean numeric NOT NULL,
  m4_mean numeric NOT NULL,
  m5_mean numeric NOT NULL,
  m6_mean numeric NOT NULL,
  m7_mean numeric NOT NULL,
  m8_mean numeric NOT NULL,
  m9_mean numeric NOT NULL,
  m10_mean numeric NOT NULL,
  overall_management_mean numeric NOT NULL,
  average_per_response_management numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  term_id uuid,
  subject_id uuid,
  CONSTRAINT management_results_pkey PRIMARY KEY (id),
  CONSTRAINT management_results_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT management_results_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT management_results_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);

CREATE TABLE public.performance_results (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  total_responses integer NOT NULL,
  p1_total integer NOT NULL,
  p2_total integer NOT NULL,
  p3_total integer NOT NULL,
  p4_total integer NOT NULL,
  p5_total integer NOT NULL,
  p6_total integer NOT NULL,
  p7_total integer NOT NULL,
  p8_total integer NOT NULL,
  p9_total integer NOT NULL,
  p10_total integer NOT NULL,
  grand_total integer NOT NULL,
  p1_mean numeric NOT NULL,
  p2_mean numeric NOT NULL,
  p3_mean numeric NOT NULL,
  p4_mean numeric NOT NULL,
  p5_mean numeric NOT NULL,
  p6_mean numeric NOT NULL,
  p7_mean numeric NOT NULL,
  p8_mean numeric NOT NULL,
  p9_mean numeric NOT NULL,
  p10_mean numeric NOT NULL,
  overall_performance_mean numeric NOT NULL,
  average_per_response_performance numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  term_id uuid,
  subject_id uuid,
  CONSTRAINT performance_results_pkey PRIMARY KEY (id),
  CONSTRAINT performance_results_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT performance_results_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT performance_results_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id)
);

CREATE TABLE public.overall_total_survey (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  instructor_id uuid NOT NULL,
  term_id uuid NOT NULL,
  total_responses integer,
  management_total integer,
  performance_total integer,
  combined_total integer,
  management_mean numeric,
  performance_mean numeric,
  overall_mean numeric,
  combined_score_mean numeric,
  created_at timestamp without time zone DEFAULT now(),
  CONSTRAINT overall_total_survey_pkey PRIMARY KEY (id),
  CONSTRAINT overall_total_survey_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT overall_total_survey_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id),
  CONSTRAINT overall_total_survey_instructor_term_unique UNIQUE (instructor_id, term_id)
);

CREATE TABLE public.instructor_wordcloud (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  word text NOT NULL,
  count integer NOT NULL DEFAULT 1,
  created_at timestamp without time zone DEFAULT now(),
  updated_at timestamp without time zone DEFAULT now(),
  term_id uuid,
  CONSTRAINT instructor_wordcloud_pkey PRIMARY KEY (id),
  CONSTRAINT instructor_wordcloud_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT instructor_wordcloud_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id)
);

CREATE TABLE public.intervention_reports (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  instructor_id uuid REFERENCES public.user_info(id) NOT NULL,
  dean_id uuid REFERENCES public.user_info(id) NOT NULL,
  action_type text NOT NULL,
  notes text,
  status text DEFAULT 'Active Tracking',
  term_id uuid REFERENCES public.academic_terms(id),
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.intervention_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Deans can view department intervention reports" ON public.intervention_reports
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

ALTER TABLE public.intervention_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Deans can view department intervention reports" ON public.intervention_reports
FOR SELECT USING (
  dean_id = auth.uid() OR
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Deans can create intervention reports" ON public.intervention_reports
FOR INSERT WITH CHECK (
  auth.uid() = dean_id AND
  EXISTS (
    SELECT 1 FROM get_user_dept_and_role()
    WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
  )
);

CREATE POLICY "Deans can update their department intervention reports" ON public.intervention_reports
FOR UPDATE USING (
  dean_id = auth.uid()
);

CREATE POLICY "Instructors can view their own intervention reports" ON public.intervention_reports
FOR SELECT USING (instructor_id = auth.uid());

CREATE TABLE public.instructor_ai_suggestions (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  ai_suggestion text NOT NULL,
  student_interpretation text,
  positive_themes text,
  improvement_insights text,
  updated_at timestamp without time zone DEFAULT now(),
  term_id uuid,
  CONSTRAINT instructor_ai_suggestions_pkey PRIMARY KEY (id),
  CONSTRAINT instructor_ai_suggestions_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT instructor_ai_suggestions_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id)
);

CREATE TABLE public.student_remarks (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  remark text NOT NULL,
  tone text CHECK (tone = ANY (ARRAY['Positive'::text, 'Critical'::text, 'Neutral'::text, NULL::text])),
  created_at timestamp without time zone DEFAULT now(),
  subject_id uuid,
  term_id uuid,
  CONSTRAINT student_remarks_pkey PRIMARY KEY (id),
  CONSTRAINT student_remarks_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(id),
  CONSTRAINT student_remarks_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id)
);

CREATE TABLE public.subjects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_code text NOT NULL,
  subject_name text NOT NULL,
  instructor_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT subjects_pkey PRIMARY KEY (id),
  CONSTRAINT subjects_instructor_id_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id)
);

CREATE TABLE public.overall_question_means (
  id bigint NOT NULL,
  instructor_id uuid NOT NULL,
  term_id uuid NOT NULL,
  category text NOT NULL CHECK (category = ANY (ARRAY['Management'::text, 'Performance'::text])),
  question_number integer NOT NULL CHECK (question_number >= 1 AND question_number <= 10),
  mean_score numeric NOT NULL DEFAULT 0,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT overall_question_means_pkey PRIMARY KEY (id),
  CONSTRAINT overall_question_means_instructor_fkey FOREIGN KEY (instructor_id) REFERENCES public.user_info(id),
  CONSTRAINT overall_question_means_term_fkey FOREIGN KEY (term_id) REFERENCES public.academic_terms(id)
);

-- ==========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- Enable RLS on all relevant tables
ALTER TABLE public.user_info ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_table ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_name ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.management_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.performance_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overall_total_survey ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.overall_question_means ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instructor_ai_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_remarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instructor_wordcloud ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.academic_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sast_all_raw_data_survey ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sast_results ENABLE ROW LEVEL SECURITY;

-- Helper Function to avoid recursion in department_table
-- SECURITY DEFINER bypasses RLS for the internal query
-- SET search_path ensures the function always looks in the public schema
CREATE OR REPLACE FUNCTION get_user_dept_and_role()
RETURNS TABLE (dept_id bigint, role_name text) AS $$
BEGIN
  RETURN QUERY
  SELECT dt.Department_name_ID as dept_id, r.Roles as role_name
  FROM public.department_table dt
  JOIN public.roles r ON dt.roles = r.id
  WHERE dt.user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 1. USER_INFO: Users can read and update their own profile; Deans can view department faculty
CREATE POLICY "Users can view own profile" ON public.user_info
FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Deans can view department faculty profiles" ON public.user_info
FOR SELECT USING (
  id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Users can update own profile" ON public.user_info
FOR UPDATE USING (auth.uid() = id);

-- 2. DEPARTMENT_TABLE: Basic self-view and Dean-view
CREATE POLICY "Users can view own department entry" ON public.department_table
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Deans can view their department faculty" ON public.department_table
FOR SELECT USING (
  Department_name_ID IN (
    SELECT dept_id FROM get_user_dept_and_role()
    WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
  )
);

-- 3. SUBJECTS: Instructors can manage their own subjects; Deans can view all
CREATE POLICY "Instructors can view own subjects" ON public.subjects
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department subjects" ON public.subjects
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can insert own subjects" ON public.subjects
FOR INSERT WITH CHECK (auth.uid() = instructor_id);

-- 4. RESULTS: Instructors view own; Deans view department
CREATE POLICY "Instructors can view own management results" ON public.management_results
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department management results" ON public.management_results
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can view own performance results" ON public.performance_results
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department performance results" ON public.performance_results
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can view own overall survey" ON public.overall_total_survey
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department overall survey" ON public.overall_total_survey
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can view own question means" ON public.overall_question_means
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department question means" ON public.overall_question_means
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

-- 5. SYSTEM & TERMS: Everyone can read
CREATE POLICY "Everyone can view academic terms" ON public.academic_terms
FOR SELECT USING (true);

CREATE POLICY "Everyone can view system settings" ON public.system_settings
FOR SELECT USING (true);

-- 5.5 RAW DATA & SAST: Gatherers can insert; Deans can view department raw results
CREATE POLICY "Gatherers can insert sast results" ON public.sast_results
FOR INSERT WITH CHECK (auth.uid() = sao_staff_id);

CREATE POLICY "Deans can view department sast results" ON public.sast_results
FOR SELECT USING (
  instructor_ID IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Gatherers can insert raw results" ON public.sast_all_raw_data_survey
FOR INSERT WITH CHECK (auth.uid() = sao_staff_id);

CREATE POLICY "Instructors can view own raw results" ON public.sast_all_raw_data_survey
FOR SELECT USING (auth.uid() = instructor_ID);

CREATE POLICY "Deans can view department raw results" ON public.sast_all_raw_data_survey
FOR SELECT USING (
  instructor_ID IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Everyone can view roles" ON public.roles
FOR SELECT USING (true);

CREATE POLICY "Everyone can view department names" ON public.department_name
FOR SELECT USING (true);

-- ==========================================
-- ANALYTICS VIEWS (Optional/Internal)
-- ==========================================
-- These would typically be materialized views or regular views for Performance Analysis
-- For the sake of schema completeness, we ensure the tables they reference exist.

-- 6. FEEDBACK & SUMMARIES: Instructors can view remarks and summaries for their own IDs
CREATE POLICY "Instructors can view own student remarks" ON public.student_remarks
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department student remarks" ON public.student_remarks
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can view own AI suggestions" ON public.instructor_ai_suggestions
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department AI suggestions" ON public.instructor_ai_suggestions
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

CREATE POLICY "Instructors can view own wordcloud" ON public.instructor_wordcloud
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department wordcloud" ON public.instructor_wordcloud
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE Department_name_ID IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);

-- 7. SUMMARIES: Deans can view department summaries
CREATE POLICY "Instructors can view own summaries" ON public.instructor_summaries
FOR SELECT USING (auth.uid() = instructor_id);

CREATE POLICY "Deans can view department summaries" ON public.instructor_summaries
FOR SELECT USING (
  instructor_id IN (
    SELECT user_id FROM public.department_table
    WHERE "Department_name_ID" IN (
      SELECT dept_id FROM get_user_dept_and_role()
      WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
    )
  )
);
