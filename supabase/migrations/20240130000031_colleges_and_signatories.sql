-- Colleges, department->college link, and report signatories. Idempotent.

CREATE TABLE IF NOT EXISTS public.colleges (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  created_at timestamptz DEFAULT now()
);

INSERT INTO public.colleges (code, name) VALUES
  ('CoEd',  'College of Education'),
  ('CAS',   'College of Arts and Sciences'),
  ('CoTE',  'College of Technology and Engineering'),
  ('CoF',   'College of Forestry'),
  ('CoA',   'College of Agriculture'),
  ('CHMT',  'College of Hospitality Management and Tourism')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.department_name
  ADD COLUMN IF NOT EXISTS college_id bigint REFERENCES public.colleges(id);

UPDATE public.department_name d SET college_id = c.id
FROM (VALUES
  ('BSIE','CoTE'),('BIT','CoTE'),('BSIT','CoTE'),
  ('BEED','CoEd'),('BSED-Math','CoEd'),('BTLEd','CoEd'),
  ('BAELS','CAS'),('BALit','CAS'),
  ('BSF','CoF'),('BSA','CoA'),('BSHM','CHMT')
) AS m(d_code, c_code)
JOIN public.colleges c ON c.code = m.c_code
WHERE d.d_code = m.d_code AND d.college_id IS NULL;

-- Row stored as a department that is really the CAS college (blank code).
UPDATE public.department_name d SET college_id = c.id
FROM public.colleges c
WHERE c.code = 'CAS' AND coalesce(d.d_code, '') = ''
  AND d.d_name = 'College of Arts and Sciences' AND d.college_id IS NULL;

-- Remove the BICS test department only when nothing references it.
DO $$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM public.department_name WHERE d_code = 'BICS' AND d_name = 'BachelorInCybersecurity';
  IF v_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.department_table WHERE "Department_name_ID" = v_id)
     AND NOT EXISTS (SELECT 1 FROM public.instructor_departments WHERE department_id = v_id)
     AND NOT EXISTS (SELECT 1 FROM public.instructor_department_terms WHERE department_id = v_id)
     AND NOT EXISTS (SELECT 1 FROM public.subjects WHERE department_id = v_id)
  THEN
    ALTER TABLE public.department_name DISABLE TRIGGER department_name_no_delete;
    DELETE FROM public.department_name WHERE id = v_id;
    ALTER TABLE public.department_name ENABLE TRIGGER department_name_no_delete;
  ELSE
    RAISE NOTICE 'BICS department left in place (missing or still referenced).';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.report_signatories (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  prepared_by_name text, prepared_by_title text,
  checked_by_name text, checked_by_title text,
  certified_by_name text, certified_by_title text,
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.report_signatories
  (id, prepared_by_name, prepared_by_title, checked_by_name, checked_by_title, certified_by_name, certified_by_title)
VALUES (1, 'MELANIE R. ABARRACIN', 'OFA Focal/Dean, Student Life',
        'CHRISTINE JOY A. TOMOL', 'Dean of Instruction',
        'EINGILBERT C. BENOLOIRAO', 'Campus Director')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.colleges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_signatories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Everyone can view colleges" ON public.colleges;
CREATE POLICY "Everyone can view colleges" ON public.colleges
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "SAO admins insert colleges" ON public.colleges;
CREATE POLICY "SAO admins insert colleges" ON public.colleges
  FOR INSERT TO authenticated WITH CHECK (public.is_sao_admin());
DROP POLICY IF EXISTS "SAO admins update colleges" ON public.colleges;
CREATE POLICY "SAO admins update colleges" ON public.colleges
  FOR UPDATE TO authenticated USING (public.is_sao_admin()) WITH CHECK (public.is_sao_admin());

DROP POLICY IF EXISTS "Authenticated read report_signatories" ON public.report_signatories;
CREATE POLICY "Authenticated read report_signatories" ON public.report_signatories
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "SAO admins insert report_signatories" ON public.report_signatories;
CREATE POLICY "SAO admins insert report_signatories" ON public.report_signatories
  FOR INSERT TO authenticated WITH CHECK (public.is_sao_admin());
DROP POLICY IF EXISTS "SAO admins update report_signatories" ON public.report_signatories;
CREATE POLICY "SAO admins update report_signatories" ON public.report_signatories
  FOR UPDATE TO authenticated USING (public.is_sao_admin()) WITH CHECK (public.is_sao_admin());
