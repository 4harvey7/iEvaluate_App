-- ============================================================================
-- verify_040.sql -- assertions for migration 040 (nightly Storage retention)
--
-- Run in the SQL editor (as postgres) after applying 040. Read-only: one
-- transaction that ends in ROLLBACK; nothing is deleted (the candidate function
-- only lists names, and only counts are shown here).
-- Output: one row per check, ok = true/false. Every row must be ok = true.
-- ============================================================================

begin;

create temp table _v (check_name text, ok boolean, detail text) on commit drop;

insert into _v
select 'B1 candidate function: security definer, fixed search_path',
       p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'), null
from pg_proc p where p.oid = to_regprocedure('public.retention_storage_candidates(integer, integer)');

insert into _v
select 'B2 only service_role can run it',
       not has_function_privilege('anon', 'public.retention_storage_candidates(integer, integer)', 'execute')
       and not has_function_privilege('authenticated', 'public.retention_storage_candidates(integer, integer)', 'execute')
       and has_function_privilege('service_role', 'public.retention_storage_candidates(integer, integer)', 'execute'), null;

do $$
begin
  perform public.retention_storage_candidates(29, 10);
  insert into _v values ('B3 days below 30 is refused', false, 'no error raised');
exception when others then
  insert into _v values ('B3 days below 30 is refused', true, null);
end $$;

insert into _v
select 'B4 pg_net installed', exists (select 1 from pg_extension where extname = 'pg_net'), null;

insert into _v
select 'B5 nightly jobs scheduled + active',
       count(*) = 2 and bool_and(active),
       string_agg(jobname || ' ' || schedule, '; ')
from cron.job where jobname in ('ievaluate-storage-retention', 'ievaluate-retention');

insert into _v
select 'B6 vault secrets present (names only)', count(*) = 2, string_agg(name, ', ')
from vault.secrets where name in ('ievaluate_project_url', 'retention_cleanup_secret');

-- B7: nothing the function offers for deletion is in an open batch or an open review.
with c as (select name from public.retention_storage_candidates(30, 1000))
insert into _v
select 'B7 no protected file is a candidate (30-day probe)', count(*) = 0, count(*)::text || ' protected hit(s)'
from c
where exists (select 1 from public.scan_batches b where b.id::text = split_part(c.name, '/', 1) and b.status = 'open')
   or exists (select 1 from public.scan_batch_items i
              where i.page_image_path = c.name
                and (exists (select 1 from public.scan_batches b where b.id = i.batch_id and b.status = 'open')
                     or exists (select 1 from public.failed_scan_queue f where f.task_id = i.task_id and f.status = 'pending')
                     or exists (select 1 from public.scan_unsaved_pages u
                                where (u.item_id = i.id or u.task_id = i.task_id) and u.status = 'needs_review')));

insert into _v
select 'B8 every candidate is older than the cutoff', bool_and(o.created_at < now() - interval '90 days') is not false, count(*)::text || ' candidate(s) at 90 days'
from public.retention_storage_candidates(90, 1000) c join storage.objects o on o.bucket_id = 'scan-pages' and o.name = c.name;

select * from _v order by check_name;

rollback;

-- After the first night:
--   select jobid, status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
--   select status_code, content from net._http_response order by created desc limit 5;  -- {"deleted": n, ...} counts only
