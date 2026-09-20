-- Migration: instructor_departments
-- Purpose: Allow Non-Resident instructors to be linked to multiple departments.
-- department_name.id is bigint, user_info.id is uuid (matching existing schema)

-- STEP 1: Create the junction table
CREATE TABLE IF NOT EXISTS public.instructor_departments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  instructor_id uuid NOT NULL,
  department_id bigint NOT NULL,
  is_primary boolean NOT NULL DEFAULT true,
  CONSTRAINT instructor_departments_pkey PRIMARY KEY (id),
  CONSTRAINT instructor_departments_instructor_id_fkey
    FOREIGN KEY (instructor_id) REFERENCES public.user_info(id) ON DELETE CASCADE,
  CONSTRAINT instructor_departments_department_id_fkey
    FOREIGN KEY (department_id) REFERENCES public.department_name(id) ON DELETE CASCADE,
  CONSTRAINT instructor_departments_unique
    UNIQUE (instructor_id, department_id)
);

-- STEP 2: Backfill all existing instructors from department_table as primary dept
-- CRITICAL: Must run before deploying Flutter code or roster will be empty
INSERT INTO public.instructor_departments (instructor_id, department_id, is_primary)
SELECT
  dt.user_id,
  dt."Department_name_ID",
  true
FROM public.department_table dt
WHERE dt.user_id IS NOT NULL
  AND dt."Department_name_ID" IS NOT NULL
ON CONFLICT (instructor_id, department_id) DO NOTHING;

-- STEP 3: Enable Row Level Security
ALTER TABLE public.instructor_departments ENABLE ROW LEVEL SECURITY;

-- STEP 4: RLS Policy — authenticated users can read; SAO Admin manages via service role
CREATE POLICY "Authenticated users can read instructor_departments"
  ON public.instructor_departments
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "SAO Admin can insert instructor_departments"
  ON public.instructor_departments
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "SAO Admin can delete instructor_departments"
  ON public.instructor_departments
  FOR DELETE
  TO authenticated
  USING (true);
