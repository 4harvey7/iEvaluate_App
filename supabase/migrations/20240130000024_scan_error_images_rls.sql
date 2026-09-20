-- ============================================================================
-- Migration: RLS for scan_error_images
--
-- WARNING  Run this in the Supabase SQL Editor.
-- WARNING  DO NOT apply with `supabase db push`.
--
-- Context
-- -------
-- scan_error_images is the new image store. failed_scan_queue and import_errors
-- now point to it with a scan_image_id FK instead of carrying the base64 inline.
-- Without this migration the table has RLS disabled, meaning authenticated
-- users can read or write any image row -- not what we want.
--
-- Who needs what
-- --------------
--   INSERT / SELECT : n8n (service-role key) only -- it writes the image when a
--                     scan fails, and the app reads it through the FK.
--
--   SELECT only      : authenticated users who already have access to the
--                     parent row (failed_scan_queue or import_errors) must be
--                     able to fetch the linked image. Two groups:
--
--     Gatherers    -- can read an image when the linked failed_scan_queue row
--                     belongs to them (user_id = auth.uid()).
--
--     SAO office   -- can read any image, because they review any scan.
--                     Matches the existing "SAO_ADMIN" / "SAO_STAFF" pattern
--                     from migration 20240130000022.
--
--   DELETE / UPDATE : nobody from the app. Images are immutable once written.
--                     The service role can clean them up directly if needed.
-- ============================================================================


-- ── 1. Enable RLS ────────────────────────────────────────────────────────────

ALTER TABLE public.scan_error_images ENABLE ROW LEVEL SECURITY;


-- ── 2. Gatherer SELECT ───────────────────────────────────────────────────────
-- A gatherer can fetch an image if there is a failed_scan_queue row that:
--   a. owns them (user_id = auth.uid()), AND
--   b. references this image (scan_image_id = scan_error_images.id).
-- This mirrors the existing fsq_own_rw policy on failed_scan_queue, scoped to
-- SELECT so gatherers cannot insert or modify image rows.

DROP POLICY IF EXISTS "Gatherers can read own scan images" ON public.scan_error_images;

CREATE POLICY "Gatherers can read own scan images"
  ON public.scan_error_images
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.failed_scan_queue fsq
      WHERE fsq.scan_image_id = scan_error_images.id
        AND fsq.user_id = auth.uid()
    )
  );


-- ── 3. SAO office SELECT ─────────────────────────────────────────────────────
-- SAO_ADMIN and SAO_STAFF can read any image -- they review scans from all
-- gatherers. Pattern copied from "SAO office deletes import_errors"
-- (migration 20240130000022).

DROP POLICY IF EXISTS "SAO office can read all scan images" ON public.scan_error_images;

CREATE POLICY "SAO office can read all scan images"
  ON public.scan_error_images
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public."Sao_users" su
      JOIN public.roles r ON r.id = su.role_id
      WHERE su.user_id = auth.uid()
        AND r."Roles" IN ('SAO_ADMIN', 'SAO_STAFF')
    )
  );


-- ── 4. Update scan_review_queue view ─────────────────────────────────────────
-- The view previously exposed f.n8n_ocr_image AS scan_image (the old inline
-- column). It now joins to scan_error_images so the app can keep reading from
-- the view without any code change on that screen.
-- For import_errors the image was in e.scan_image (old inline); same swap.
-- Both old inline columns stay in the schema for backward compatibility with
-- existing rows -- they just won't be written for new scans.

CREATE OR REPLACE VIEW public.scan_review_queue AS
SELECT
  'failed_scan'::text                              AS queue,
  f.id::text                                       AS id,
  f.task_id,
  f.user_id,
  f.term_id::text                                  AS term_id,
  f.status,
  f.created_at,
  coalesce(f.review_reasons, ARRAY[]::text[])      AS review_reasons,
  -- image: prefer the new FK-linked image; fall back to the old inline column
  -- for rows that existed before this migration.
  coalesce(sei_f.image_base64, f.n8n_ocr_image)   AS scan_image,
  f.partial_data                                   AS payload,
  f.omr_comparison,
  NULL::text                                       AS raw_instructor_name,
  NULL::text                                       AS raw_subject_name
FROM public.failed_scan_queue f
LEFT JOIN public.scan_error_images sei_f ON sei_f.id = f.scan_image_id

UNION ALL

SELECT
  'import_error'::text                             AS queue,
  e.id::text                                       AS id,
  e.task_id,
  e.resolved_by                                    AS user_id,
  e.raw_term_id::text                              AS term_id,
  e.status,
  e.created_at,
  coalesce(e.review_reasons, ARRAY[e.error_type]) AS review_reasons,
  -- image: prefer the new FK-linked image; fall back to the old inline column.
  coalesce(sei_e.image_base64, e.scan_image)       AS scan_image,
  CASE
    WHEN e.raw_data IS NULL THEN NULL
    WHEN jsonb_typeof(to_jsonb(e.raw_data)) = 'string'
      THEN (to_jsonb(e.raw_data) #>> '{}')::jsonb
    ELSE to_jsonb(e.raw_data)
  END                                              AS payload,
  NULL::jsonb                                      AS omr_comparison,
  e.raw_instructor_name,
  e.raw_subject_name
FROM public.import_errors e
LEFT JOIN public.scan_error_images sei_e ON sei_e.id = e.scan_image_id;

COMMENT ON VIEW public.scan_review_queue IS
  'Everything awaiting SAO staff validation, from both queues, in one shape. '
  'Filter on status = ''pending''. '
  'scan_image resolves from scan_error_images via FK; falls back to old inline column for pre-migration rows.';

-- Re-grant (CREATE OR REPLACE drops grants on the view).
GRANT SELECT ON public.scan_review_queue TO authenticated;


-- ============================================================================
-- Verification
-- ============================================================================
--
-- 1. RLS is on and policies exist:
--    SELECT tablename, policyname, cmd, roles
--    FROM pg_policies
--    WHERE schemaname = 'public' AND tablename = 'scan_error_images'
--    ORDER BY cmd, policyname;
--    -- expect 2 rows (SELECT x2)
--
-- 2. View still returns rows, image column now coalesces correctly:
--    SELECT queue, id, scan_image IS NOT NULL AS has_image
--    FROM public.scan_review_queue
--    WHERE status = 'pending'
--    LIMIT 10;
--
-- 3. As a gatherer, reading an image they own returns the row:
--    -- (run as a gatherer JWT)
--    SELECT id FROM public.scan_error_images
--    WHERE id = '<scan_image_id from one of their failed scans>';
--
-- 4. As a gatherer, reading someone else's image returns nothing:
--    SELECT id FROM public.scan_error_images
--    WHERE id = '<scan_image_id from another user''s scan>';
--    -- expect 0 rows
-- ============================================================================
