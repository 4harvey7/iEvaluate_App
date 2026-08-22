-- ============================================================
-- Migration: Fix student_remarks RLS only
-- ============================================================

-- Make sure RLS is enabled
ALTER TABLE public.student_remarks ENABLE ROW LEVEL SECURITY;

-- 1. Drop existing policies on this table so they don't conflict
DROP POLICY IF EXISTS "Instructors can view own student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "Deans can view department student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "SAO admins can view all student remarks" ON public.student_remarks;
DROP POLICY IF EXISTS "Authenticated users can view student remarks" ON public.student_remarks;

-- 2. Create the policy for Instructors to see their own feedback
CREATE POLICY "Instructors can view own student remarks" ON public.student_remarks
FOR SELECT USING (auth.uid() = instructor_id);

-- 3. (Optional / Testing) If you want ALL logged-in users (including SAO Admins & Deans) 
-- to be able to view remarks without dealing with role-checking tables that might be causing errors:
CREATE POLICY "Authenticated users can view student remarks" ON public.student_remarks
FOR SELECT USING (auth.role() = 'authenticated');
