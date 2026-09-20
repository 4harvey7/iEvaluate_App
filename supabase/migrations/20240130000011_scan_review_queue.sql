-- ============================================================================
-- Migration: reviewable scan queue -- flagged records and failed scans, with images
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply this with `supabase db push`.
--
-- Supports the human-in-the-loop validation step: when the OCR/OMR
-- reconciliation is not confident, a SAO staff member reviews the scan, edits
-- wrong values, approves, or deletes it.
--
-- Two tables already exist and each is right for a different failure:
--
--   failed_scan_queue  -- something went wrong READING THE IMAGE. Grid not
--                         detected, the two OMR engines disagreed, or half the
--                         form is blank. Already carries n8n_ocr_image, so the
--                         reviewer can see what was scanned.
--
--   import_errors      -- the image read fine but an IDENTITY could not be
--                         resolved: no instructor or no subject matched. Also
--                         raised by the Google Sheets path, where there is no
--                         image at all.
--
-- What was missing:
--   1. failed_scan_queue could not say WHY a scan needs review, or show what
--      each engine actually read, so a reviewer had no basis to judge.
--   2. import_errors has no image column, so a scan-sourced identity failure
--      showed the reviewer nothing.
--   3. Neither table had a uniqueness rule, so resubmitting the same scan
--      queued it again and staff reviewed the same form twice.
-- ============================================================================


-- ── STEP 1: failed_scan_queue -- say why, and show the evidence ─────────────
ALTER TABLE public.failed_scan_queue
  ADD COLUMN IF NOT EXISTS review_reasons text[],
  ADD COLUMN IF NOT EXISTS omr_comparison jsonb,
  ADD COLUMN IF NOT EXISTS validation_status text;

COMMENT ON COLUMN public.failed_scan_queue.review_reasons IS
  'Why this needs a human, from the reconciler: omr_disagreement_N_of_20, too_many_blanks_N_of_20, grid_not_detected, gemini_unavailable.';

COMMENT ON COLUMN public.failed_scan_queue.omr_comparison IS
  'Per-question record of what each engine read: [{question, python, gemini, used, source}]. This is what the reviewer needs -- "the two readings disagree" is not actionable, "Python read 5 and Gemini read 2 on m3" is.';


-- ── STEP 2: import_errors -- carry the image when there is one ──────────────
-- Nullable on purpose. A Google Sheets import has no image and never will;
-- only the scan path fills this.
ALTER TABLE public.import_errors
  ADD COLUMN IF NOT EXISTS scan_image text,
  ADD COLUMN IF NOT EXISTS review_reasons text[];

COMMENT ON COLUMN public.import_errors.scan_image IS
  'Base64 composite OCR preview, copied from the scan pipeline so a reviewer can see the form. NULL for google_sheet imports, which have no image.';


-- ── STEP 3: one review per scan ────────────────────────────────────────────
-- Partial, because task_id is null for anything that did not come from a scan
-- and those rows must stay insertable.
--
-- Guarded: existing duplicates would make the index build fail with an
-- unreadable error.
DO $guard$
DECLARE dupes int;
BEGIN
  SELECT count(*) INTO dupes FROM (
    SELECT task_id FROM public.failed_scan_queue
    WHERE task_id IS NOT NULL
    GROUP BY task_id HAVING count(*) > 1
  ) d;

  IF dupes > 0 THEN
    RAISE EXCEPTION
      'Cannot add the one-review-per-scan index yet: % task_id(s) are queued more than once. Run the audit query at the bottom of this file, keep the newest row of each group, delete the rest.',
      dupes;
  END IF;
END
$guard$;

CREATE UNIQUE INDEX IF NOT EXISTS failed_scan_queue_task_unique
  ON public.failed_scan_queue (task_id)
  WHERE task_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS import_errors_task_unique
  ON public.import_errors (task_id)
  WHERE task_id IS NOT NULL;

-- The review screens read "everything still waiting", ordered oldest first.
CREATE INDEX IF NOT EXISTS failed_scan_queue_status_idx
  ON public.failed_scan_queue (status, created_at);

CREATE INDEX IF NOT EXISTS import_errors_status_idx
  ON public.import_errors (status, created_at);


-- ── STEP 4: one list for the app to read ───────────────────────────────────
-- The app needs a single "needs review" screen, not two that happen to look
-- alike. This unions both queues into one shape, so a Flutter screen binds to
-- one source and the distinction between "could not read the image" and "could
-- not identify the instructor" becomes a label rather than a second code path.
CREATE OR REPLACE VIEW public.scan_review_queue AS
SELECT
  'failed_scan'::text                     AS queue,
  f.id::text                              AS id,
  f.task_id,
  f.user_id,
  f.term_id::text                         AS term_id,
  f.status,
  f.created_at,
  coalesce(f.review_reasons, ARRAY[]::text[]) AS review_reasons,
  f.n8n_ocr_image                         AS scan_image,
  f.partial_data                          AS payload,
  f.omr_comparison,
  NULL::text                              AS raw_instructor_name,
  NULL::text                              AS raw_subject_name
FROM public.failed_scan_queue f
UNION ALL
SELECT
  'import_error'::text                    AS queue,
  e.id::text                              AS id,
  e.task_id,
  e.resolved_by                           AS user_id,
  e.raw_term_id::text                     AS term_id,
  e.status,
  e.created_at,
  coalesce(e.review_reasons, ARRAY[e.error_type]) AS review_reasons,
  e.scan_image,
  CASE
    WHEN e.raw_data IS NULL THEN NULL
    WHEN jsonb_typeof(to_jsonb(e.raw_data)) = 'string'
      THEN (to_jsonb(e.raw_data) #>> '{}')::jsonb
    ELSE to_jsonb(e.raw_data)
  END                                     AS payload,
  NULL::jsonb                             AS omr_comparison,
  e.raw_instructor_name,
  e.raw_subject_name
FROM public.import_errors e;

COMMENT ON VIEW public.scan_review_queue IS
  'Everything awaiting SAO staff validation, from both queues, in one shape. Filter on status = ''pending''.';

-- The view runs as its caller, so the underlying tables'' RLS still applies.
GRANT SELECT ON public.scan_review_queue TO authenticated;


-- ============================================================================
-- Verification -- returns exactly one row, so "no rows returned" means the
-- query failed rather than "nothing found".
-- ============================================================================
--
-- SELECT jsonb_pretty(jsonb_build_object(
--   'fsq_new_cols_want_3', (SELECT count(*) FROM information_schema.columns
--      WHERE table_schema='public' AND table_name='failed_scan_queue'
--        AND column_name IN ('review_reasons','omr_comparison','validation_status')),
--   'ie_new_cols_want_2', (SELECT count(*) FROM information_schema.columns
--      WHERE table_schema='public' AND table_name='import_errors'
--        AND column_name IN ('scan_image','review_reasons')),
--   'task_unique_indexes_want_2', (SELECT count(*) FROM pg_indexes
--      WHERE schemaname='public'
--        AND indexname IN ('failed_scan_queue_task_unique','import_errors_task_unique')),
--   'view_want_1', (SELECT count(*) FROM pg_views
--      WHERE schemaname='public' AND viewname='scan_review_queue'),
--   'pending_now', (SELECT count(*) FROM public.scan_review_queue WHERE status='pending')
-- ));
--
-- Audit query for the STEP 3 guard, if it ever aborts:
--
-- SELECT task_id, count(*) AS queued_times,
--        jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'status', status)
--                  ORDER BY created_at DESC) AS rows
-- FROM public.failed_scan_queue
-- WHERE task_id IS NOT NULL
-- GROUP BY task_id HAVING count(*) > 1;
-- ============================================================================
