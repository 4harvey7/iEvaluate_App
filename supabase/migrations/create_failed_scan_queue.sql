-- ============================================================
-- Migration: Create failed_scan_queue table
-- Run this in your Supabase SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public.failed_scan_queue (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Links back to the scan task from the Flutter app queue
  task_id         TEXT        NOT NULL,

  -- Who scanned it
  user_id         UUID,
  term_id         TEXT,

  -- Why it failed
  table_found     BOOLEAN     DEFAULT FALSE,
  grid_source     TEXT,        -- 'auto-detected' | 'fallback'

  -- Whatever Python managed to extract (partial / possibly wrong)
  -- Includes: instructor, subject, ay_semester, remarks, date,
  --           student_id, ratings (management/performance), summary
  partial_data    JSONB,

  -- The composite OCR image from Python (base64 JPEG).
  -- This is the "n8n_ocr_image" — a side-by-side of RAW + CLEAN
  -- binarized field crops. Shown in the Flutter validation screen
  -- as the "OCR Attempt" preview so the gatherer can see what
  -- Python tried to read.
  n8n_ocr_image   TEXT,

  -- Validation lifecycle
  status          TEXT        DEFAULT 'pending',
  -- pending   : waiting for human review
  -- validated : gatherer submitted corrected data → written to raw_GoogleSheet_data_result
  -- discarded : gatherer rejected this scan entirely

  -- Corrected fields after human review
  validated_data  JSONB,
  validated_by    UUID,

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  validated_at    TIMESTAMPTZ
);

-- Indexes for fast queries from Flutter
CREATE INDEX IF NOT EXISTS idx_fsq_status
  ON public.failed_scan_queue(status);

CREATE INDEX IF NOT EXISTS idx_fsq_user
  ON public.failed_scan_queue(user_id);

CREATE INDEX IF NOT EXISTS idx_fsq_task
  ON public.failed_scan_queue(task_id);

CREATE INDEX IF NOT EXISTS idx_fsq_created
  ON public.failed_scan_queue(created_at DESC);

-- Row-Level Security
ALTER TABLE public.failed_scan_queue ENABLE ROW LEVEL SECURITY;

-- Gatherers can read/write their own records only
CREATE POLICY fsq_own_rw ON public.failed_scan_queue
  FOR ALL
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- SAO admins (service role) bypass RLS automatically
-- No extra policy needed for the n8n service key.

-- ============================================================
-- Also add a column to raw_GoogleSheet_data_result to mark
-- manually corrected records (if it doesn't already exist)
-- ============================================================
ALTER TABLE public.raw_GoogleSheet_data_result
  ADD COLUMN IF NOT EXISTS manually_corrected BOOLEAN DEFAULT FALSE;

ALTER TABLE public.raw_GoogleSheet_data_result
  ADD COLUMN IF NOT EXISTS task_id TEXT;
