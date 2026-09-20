-- Add department code (short abbreviation) to department_name table
-- e.g. "College of Technology and Engineering" → code "CTE"
ALTER TABLE department_name ADD COLUMN IF NOT EXISTS d_code text DEFAULT '';
