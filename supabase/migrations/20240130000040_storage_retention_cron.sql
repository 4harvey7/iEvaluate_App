-- ============================================================================
-- 20240130000040_storage_retention_cron.sql   (security review 2026-11-21, M3 follow-up)
--
-- RUN IN THE SUPABASE SQL EDITOR, on a branch / local stack first, AFTER 038.
--
-- PROBLEM: run_retention_cleanup() (038) clears DATABASE rows only. The page
-- pictures in the private Storage bucket 'scan-pages' ('<batch_id>/<item_id>.jpg',
-- written by the web backend, app/page_images.py) were only removed when
-- somebody opened a batch page. Deleting storage.objects rows in SQL does NOT
-- delete the files; they must be removed through the Storage API.
--
-- WHAT THIS ADDS
--   1. public.retention_storage_candidates(p_days, p_limit): service-role-only,
--      read-only. Lists 'scan-pages' objects older than p_days (>= 30) by
--      storage.objects.created_at, EXCEPT objects that
--        * belong to a batch that is still open (path prefix or item row), or
--        * belong to a page whose review is still open:
--          failed_scan_queue.status = 'pending' or
--          scan_unsaved_pages.status = 'needs_review'.
--   2. Edge function retention-storage-cleanup (supabase/functions/) removes
--      those files with storage.from('scan-pages').remove([...]) and clears
--      scan_batch_items.page_image_path (page_image_saved_at stays, so the
--      viewer can say why the picture is gone).
--   3. pg_net + two nightly pg_cron jobs:
--        ievaluate-retention          03:15  select public.run_retention_cleanup(90)  (038, DB rows)
--        ievaluate-storage-retention  03:30  POST to the edge function, dry_run=false, days=90
--      The function URL and the shared secret come from Supabase Vault.
--
-- BEFORE APPLYING (MANUAL, no values in this file):
--   a) supabase secrets set RETENTION_CLEANUP_SECRET=<long random string>
--      supabase functions deploy retention-storage-cleanup --no-verify-jwt
--   b) In the SQL editor (values typed by hand, never committed):
--        select vault.create_secret('https://<project-ref>.supabase.co', 'ievaluate_project_url');
--        select vault.create_secret('<same long random string>', 'retention_cleanup_secret');
--      To change one later: select vault.update_secret(id, '<new>') ... using
--        select id, name from vault.secrets;
--   c) Dry run first (counts only, deletes nothing), from a terminal:
--        curl -X POST https://<project-ref>.supabase.co/functions/v1/retention-storage-cleanup \
--             -H "x-retention-secret: <secret>" -H "Content-Type: application/json" -d "{}"
--
-- CHANGE THE PERIOD: edit "days" in the cron body below (minimum 30) and the
--   run_retention_cleanup(90) argument, then re-run this file.
--
-- Safe to run more than once (jobs are unscheduled before being scheduled).
-- ROLLBACK:
--   select cron.unschedule('ievaluate-storage-retention');
--   select cron.unschedule('ievaluate-retention');
--   drop function if exists public.retention_storage_candidates(int, int);
--   (files already removed cannot be restored: Storage has no undo / PITR.)
-- ============================================================================

begin;

create extension if not exists pg_net with schema extensions;

create or replace function public.retention_storage_candidates(p_days int default 90,
                                                               p_limit int default 500)
returns table (name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_days is null or p_days < 30 then
    raise exception 'retention_storage_candidates: p_days must be >= 30 (got %)', p_days;
  end if;
  return query
  select o.name
  from storage.objects o
  where o.bucket_id = 'scan-pages'
    and o.created_at < now() - make_interval(days => p_days)
    -- the batch named by the path is still open
    and not exists (select 1 from public.scan_batches b
                    where b.id::text = split_part(o.name, '/', 1) and b.status = 'open')
    -- the page this file belongs to is in an open batch or still needs review
    and not exists (
      select 1 from public.scan_batch_items i
      where i.page_image_path = o.name
        and (exists (select 1 from public.scan_batches b where b.id = i.batch_id and b.status = 'open')
             or exists (select 1 from public.failed_scan_queue f
                        where f.task_id = i.task_id and f.status = 'pending')
             or exists (select 1 from public.scan_unsaved_pages u
                        where (u.item_id = i.id or u.task_id = i.task_id) and u.status = 'needs_review')))
  order by o.created_at
  limit greatest(1, least(coalesce(p_limit, 500), 1000));
end;
$$;

comment on function public.retention_storage_candidates(int, int) is
  'scan-pages files older than p_days (>= 30) that no open batch or open review needs (040). '
  'Read-only; the retention-storage-cleanup edge function deletes them. service_role only.';

revoke all on function public.retention_storage_candidates(int, int) from public, anon, authenticated;
grant execute on function public.retention_storage_candidates(int, int) to service_role;

-- ── Nightly jobs (idempotent) ───────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job where jobname = 'ievaluate-storage-retention') then
    perform cron.unschedule('ievaluate-storage-retention');
  end if;
  if exists (select 1 from cron.job where jobname = 'ievaluate-retention') then
    perform cron.unschedule('ievaluate-retention');
  end if;

  perform cron.schedule('ievaluate-storage-retention', '30 3 * * *', $job$
    select net.http_post(
      url     := (select decrypted_secret from vault.decrypted_secrets where name = 'ievaluate_project_url')
                 || '/functions/v1/retention-storage-cleanup',
      headers := jsonb_build_object(
                   'Content-Type', 'application/json',
                   'x-retention-secret',
                   (select decrypted_secret from vault.decrypted_secrets where name = 'retention_cleanup_secret')),
      body    := '{"dry_run": false, "days": 90}'::jsonb,
      timeout_milliseconds := 120000);
  $job$);

  -- DB-row cleanup from 038 (it was left unscheduled there).
  if to_regprocedure('public.run_retention_cleanup(integer, boolean)') is not null then
    perform cron.schedule('ievaluate-retention', '15 3 * * *',
                          'select public.run_retention_cleanup(90)');
  else
    raise notice '038 not applied: ievaluate-retention NOT scheduled; apply 038 and re-run 040';
  end if;
end;
$$;

commit;

-- Check:  select jobname, schedule, active from cron.job;
--         select jobid, status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
--         select status_code, content from net._http_response order by created desc limit 5;   -- counts only
