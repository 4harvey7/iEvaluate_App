-- ============================================================================
-- 20240130000038_retention_cleanup.sql   (security review 2026-11-21, M3 / F3)
--
-- RUN IN THE SUPABASE SQL EDITOR, on a branch / local stack first.
--
-- PROBLEM (M3): only the scan-pages BUCKET has a 90-day cleanup (backend, on
-- page view). Image copies and plaintext student IDs inside the database are
-- never purged:
--   scan_error_images.image_base64      (full page images)
--   failed_scan_queue.n8n_ocr_image      (page image copy)
--   scan_unsaved_pages.image_base64 / header_image_base64
--   scan_batch_items.result_summary->'student_id'
--   failed_scan_queue.partial_data / validated_data / review_correction ->'student_id'
--   import_errors.raw_student_id, import_errors.raw_data->'student_id'
--
-- WHAT THIS ADDS: public.run_retention_cleanup(p_days int default 90), a
-- service-role-only function that, for rows OLDER than p_days:
--   * keeps everything that is still waiting for review (status 'pending' /
--     'needs_review'), so no open review loses its image;
--   * deletes scan_error_images no open review points at (references from
--     closed rows are set to NULL first; the FKs have no ON DELETE action);
--   * clears failed_scan_queue.n8n_ocr_image on closed rows;
--   * deletes closed scan_unsaved_pages rows;
--   * strips the top-level 'student_id' key from the JSON columns above and
--     nulls import_errors.raw_student_id on closed rows.
-- The saved survey keeps only student_id_hash (021), so results are unchanged.
-- Side effect: old rows drop out of the ocr_correction_log student-ID accuracy
-- statistics (that view reads partial_data->'student_id').
--
-- NOT DONE HERE (needs a decision):
--   * Purging the plaintext student_id of SAVED survey rows
--     (sast_all_raw_data_survey.student_id, kept by 021 for the n8n upsert):
--     opt-in via run_retention_cleanup(90, true).
--   * Backup tables backup_*_20261003 and wordcloud_backfill_016: export them,
--     then run the commented DROP at the bottom.
--   * Scheduling: pg_cron is available but NOT installed (see step 3).
--   * Bucket objects: run `python -m app.page_images cleanup_expired` from the
--     backend on a schedule (Render cron job), see Security_Fixes_Applied.md.
--
-- Safe to run more than once. One transaction. Creating the function deletes
-- nothing; data is only removed when the function is called.
-- ROLLBACK: drop function public.run_retention_cleanup(int, boolean);
--           and re-run the sast_raw_set_student_id_hash() body from
--           app/migrations/021_student_id_hash.sql (optional: the new branch
--           is inert unless ievaluate.retention='on').
--           (deleted data cannot be restored except from a backup / PITR).
-- ============================================================================

begin;

-- Retention purge of the SAVED plaintext student_id must keep the HMAC hash
-- (021 recomputes it from student_id on every update, i.e. would set it NULL).
-- Only the retention function sets ievaluate.retention='on'; every other
-- update behaves exactly as before.
create or replace function public.sast_raw_set_student_id_hash()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE'
     and coalesce(current_setting('ievaluate.retention', true), '') = 'on'
     and nullif(btrim(new.student_id), '') is null
     and old.student_id_hash is not null then
    new.student_id_hash := old.student_id_hash;
    return new;
  end if;
  -- always recomputed from student_id, so the hash can't be set to anything else by hand
  new.student_id_hash := public.sast_hash_student_id(nullif(btrim(new.student_id), ''));
  return new;
end;
$function$;

create or replace function public.run_retention_cleanup(p_days int default 90,
                                                        p_purge_saved_ids boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_cutoff timestamptz;
  v_out    jsonb := '{}'::jsonb;
  n        bigint;
begin
  if p_days is null or p_days < 30 then
    raise exception 'run_retention_cleanup: p_days must be >= 30 (got %)', p_days;
  end if;
  v_cutoff := now() - make_interval(days => p_days);

  -- 1. Detach old images from CLOSED review rows, then delete images that no
  --    open review still needs.
  update public.failed_scan_queue f set scan_image_id = null
  where f.scan_image_id is not null and f.status is distinct from 'pending'
    and f.created_at < v_cutoff;
  update public.import_errors e set scan_image_id = null
  where e.scan_image_id is not null and e.status is distinct from 'pending'
    and e.created_at < v_cutoff;

  delete from public.scan_error_images s
  where s.created_at < v_cutoff
    and not exists (select 1 from public.failed_scan_queue f where f.scan_image_id = s.id)
    and not exists (select 1 from public.import_errors e where e.scan_image_id = s.id);
  get diagnostics n = row_count;
  v_out := v_out || jsonb_build_object('scan_error_images_deleted', n);

  -- 2. failed_scan_queue: image copy + student IDs on closed rows
  update public.failed_scan_queue f
  set n8n_ocr_image     = null,
      partial_data      = case when jsonb_typeof(f.partial_data) = 'object'      then f.partial_data      - 'student_id' else f.partial_data end,
      validated_data    = case when jsonb_typeof(f.validated_data) = 'object'    then f.validated_data    - 'student_id' else f.validated_data end,
      review_correction = case when jsonb_typeof(f.review_correction) = 'object' then f.review_correction - 'student_id' else f.review_correction end
  where f.status is distinct from 'pending'
    and f.created_at < v_cutoff
    and (f.n8n_ocr_image is not null
         or f.partial_data ? 'student_id'
         or f.validated_data ? 'student_id'
         or f.review_correction ? 'student_id');
  get diagnostics n = row_count;
  v_out := v_out || jsonb_build_object('failed_scan_queue_scrubbed', n);

  -- 3. import_errors: student IDs on closed rows
  update public.import_errors e
  set raw_student_id = null,
      raw_data = case when jsonb_typeof(e.raw_data) = 'object' then e.raw_data - 'student_id' else e.raw_data end
  where e.status is distinct from 'pending'
    and e.created_at < v_cutoff
    and (e.raw_student_id is not null or e.raw_data ? 'student_id');
  get diagnostics n = row_count;
  v_out := v_out || jsonb_build_object('import_errors_scrubbed', n);

  -- 4. scan_unsaved_pages: closed rows go entirely (they hold the images)
  delete from public.scan_unsaved_pages u
  where u.created_at < v_cutoff and u.status is distinct from 'needs_review';
  get diagnostics n = row_count;
  v_out := v_out || jsonb_build_object('scan_unsaved_pages_deleted', n);

  -- 5. scan_batch_items: plaintext student ID in the per-page summary
  update public.scan_batch_items i
  set result_summary = i.result_summary - 'student_id'
  where i.created_at < v_cutoff and i.result_summary ? 'student_id';
  get diagnostics n = row_count;
  v_out := v_out || jsonb_build_object('scan_batch_items_scrubbed', n);

  -- 6. OPT-IN (needs user decision): plaintext student_id on SAVED survey rows.
  --    The hash stays, so duplicate detection by hash keeps working; the n8n
  --    upsert keyed on the plaintext index will then raise a unique violation
  --    (hash index) for a re-scan of a purged form instead of overwriting it.
  if p_purge_saved_ids then
    perform set_config('ievaluate.retention', 'on', true);
    update public.sast_all_raw_data_survey r set student_id = null
    where r.created_at < v_cutoff and r.student_id is not null and r.student_id_hash is not null;
    get diagnostics n = row_count;
    perform set_config('ievaluate.retention', 'off', true);
    v_out := v_out || jsonb_build_object('saved_student_ids_purged', n);
  end if;

  -- 7. login lookup log (037), if present
  if to_regclass('public.login_lookup_attempts') is not null then
    execute 'delete from public.login_lookup_attempts where created_at < now() - interval ''1 day''';
  end if;

  return v_out || jsonb_build_object('cutoff', v_cutoff);
end;
$$;

comment on function public.run_retention_cleanup(int, boolean) is
  '90-day retention for image copies and plaintext student IDs (038). '
  'Keeps rows still pending review. service_role only.';

revoke all on function public.run_retention_cleanup(int, boolean) from public, anon, authenticated;
grant execute on function public.run_retention_cleanup(int, boolean) to service_role;

commit;

-- ── 3. Schedule it (MANUAL, after the function is applied and tested) ──────
-- Dashboard > Database > Extensions > enable "pg_cron", then run:
--
--   select cron.schedule('ievaluate-retention', '15 3 * * *',
--                        $$select public.run_retention_cleanup(90)$$);
--
-- Check:   select * from cron.job;  select * from cron.job_run_details order by start_time desc limit 5;
-- Remove:  select cron.unschedule('ievaluate-retention');
--
-- Without pg_cron, run it by hand (SQL editor) or from the backend with the
-- service role:  sb.rpc("run_retention_cleanup", {"p_days": 90}).execute()
--
-- ── 4. Backup tables (MANUAL, export first) ────────────────────────────────
-- drop table if exists public.backup_mgmt_20261003, public.backup_overall_20261003,
--   public.backup_perf_20261003, public.backup_qmeans_20261003,
--   public.wordcloud_backfill_016;
