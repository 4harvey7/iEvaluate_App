-- ============================================================
-- Migration: Security Fixes
-- Addresses: C-4, M-6, and duplicate intervention_reports RLS
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- C-4 FIX: Enable RLS on tables that were missing it
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.Sao_users ENABLE ROW LEVEL SECURITY;

-- SAO users can only view their own entry.
-- The service role (edge functions) bypasses RLS automatically.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'Sao_users' AND policyname = 'SAO users can view own entry'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "SAO users can view own entry" ON public.Sao_users
        FOR SELECT USING (auth.uid() = user_id)
    $policy$;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.admin_verifications ENABLE ROW LEVEL SECURITY;

-- Only the owning admin can read/write their own OTP record.
-- Edge functions use service role and bypass this automatically.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'admin_verifications' AND policyname = 'Admins can manage own verification'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Admins can manage own verification" ON public.admin_verifications
        FOR ALL USING (auth.uid() = admin_id)
        WITH CHECK (auth.uid() = admin_id)
    $policy$;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Only SAO users (admins/staff) can view audit logs via the client.
-- Service role (edge functions) bypasses this.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'audit_logs' AND policyname = 'SAO users can view audit logs'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "SAO users can view audit logs" ON public.audit_logs
        FOR SELECT USING (
          EXISTS (
            SELECT 1 FROM public.Sao_users WHERE user_id = auth.uid()
          )
        )
    $policy$;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- C-4 FIX: Remove duplicate intervention_reports policies
-- The original migration had ENABLE ROW LEVEL SECURITY twice,
-- and the first SELECT policy was a duplicate. Drop and recreate cleanly.
-- ──────────────────────────────────────────────────────────────

-- Drop the potentially-duplicate policy (safe to run even if it doesn't exist)
DROP POLICY IF EXISTS "Deans can view department intervention reports" ON public.intervention_reports;

-- Recreate the correct merged policy: dean sees their own reports OR department instructors' reports
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_reports'
      AND policyname = 'Deans can view own and department intervention reports'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Deans can view own and department intervention reports"
        ON public.intervention_reports
        FOR SELECT USING (
          dean_id = auth.uid() OR
          instructor_id IN (
            SELECT user_id FROM public.department_table
            WHERE Department_name_ID IN (
              SELECT dept_id FROM get_user_dept_and_role()
              WHERE UPPER(role_name) IN ('DEAN', 'DEPARTMENT HEAD', 'DEPARTMENT_HEAD')
            )
          )
        )
    $policy$;
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────────
-- M-6 FIX: Replace broad FOR ALL policy on failed_scan_queue
-- with specific per-operation policies that prevent self-deletion
-- ──────────────────────────────────────────────────────────────

-- Drop the old broad policy
DROP POLICY IF EXISTS "fsq_own_rw" ON public.failed_scan_queue;

-- SELECT: gatherers can only see their own records
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'failed_scan_queue' AND policyname = 'fsq_own_select'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "fsq_own_select" ON public.failed_scan_queue
        FOR SELECT USING (user_id = auth.uid())
    $policy$;
  END IF;
END $$;

-- INSERT: gatherers can only insert their own records
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'failed_scan_queue' AND policyname = 'fsq_own_insert'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "fsq_own_insert" ON public.failed_scan_queue
        FOR INSERT WITH CHECK (user_id = auth.uid())
    $policy$;
  END IF;
END $$;

-- UPDATE: gatherers can only update their own PENDING records (not already validated/discarded)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'failed_scan_queue' AND policyname = 'fsq_own_update_pending'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "fsq_own_update_pending" ON public.failed_scan_queue
        FOR UPDATE USING (user_id = auth.uid() AND status = 'pending')
        WITH CHECK (user_id = auth.uid())
    $policy$;
  END IF;
END $$;

-- NOTE: No DELETE policy for gatherers — only the service role (n8n, edge functions) can delete records.
-- This preserves the audit trail.

-- ──────────────────────────────────────────────────────────────
-- H-5 FIX: Add max-length constraints on text fields
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.intervention_reports
  ADD CONSTRAINT IF NOT EXISTS intervention_notes_max_length
  CHECK (notes IS NULL OR length(notes) <= 3000);

ALTER TABLE public.student_remarks
  ADD CONSTRAINT IF NOT EXISTS remark_max_length
  CHECK (length(remark) <= 5000);

-- ──────────────────────────────────────────────────────────────
-- L-1 FIX: Remove orphan RLS policies that reference
-- instructor_summaries (a table that doesn't exist in the schema)
-- ──────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Instructors can view own summaries" ON public.instructor_summaries;
DROP POLICY IF EXISTS "Deans can view department summaries" ON public.instructor_summaries;
