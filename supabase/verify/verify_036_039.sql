-- ============================================================================
-- verify_036_039.sql -- assertions for migrations 036-039 (security review 2026-11-21)
--
-- RUN ON A SUPABASE BRANCH / LOCAL STACK after applying 036-039, in the SQL
-- editor (as postgres). Everything happens in ONE transaction that ends in
-- ROLLBACK: the temporary status changes used to simulate a pending account
-- are never kept. Do not change the final ROLLBACK to COMMIT.
--
-- Output: one row per check, ok = true/false. Every row must be ok = true.
-- (Persona checks are skipped, with ok = null, when the data has no such user.)
-- ============================================================================

begin;

create temp table _v (check_name text, ok boolean, detail text) on commit drop;

-- ── A. Static checks ─────────────────────────────────────────────────────────
insert into _v
select 'A1 no policy grants access from role/membership without an approval helper',
       count(*) = 0, string_agg(tablename || '.' || policyname, '; ')
from pg_policies
where schemaname = 'public'
  and (coalesce(qual, '') || coalesce(with_check, '')) ~* '"Sao_users"|get_user_dept_and_role|get_auth_user_dept_id|get_auth_dept_id|department_table'
  and (coalesce(qual, '') || coalesce(with_check, '')) !~* 'is_approved_user|is_approved_sao|is_sao\(|is_dept_head\(|is_sao_admin\(|can_file_intervention_for';

insert into _v
select 'A2 admin helpers require approval', bool_and(pg_get_functiondef(p.oid) ~* 'is_approved_sao_(admin|staff)'), string_agg(p.proname, ', ')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('is_sao_admin', 'check_is_sao_admin', 'is_admin_check', 'eval_is_sao_office');

insert into _v
select 'A3 no mutable search_path left (lint 0011)', count(*) = 0, string_agg(p.oid::regprocedure::text, ', ')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f'
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');

insert into _v
select 'A4 anon cannot run snapshot/retention/dept helpers',
       not bool_or(has_function_privilege('anon', f, 'execute')), null
from unnest(array['public.snapshot_term_departments(uuid)', 'public.run_retention_cleanup(integer,boolean)',
                  'public.get_user_dept_and_role()', 'public.get_auth_user_dept_id()', 'public.get_auth_dept_id()',
                  'public.is_admin_check()']::regprocedure[]) f;

insert into _v
select 'A5 anon still runs the pre-login RPCs',
       bool_and(has_function_privilege('anon', f, 'execute')), null
from unnest(array['public.get_login_email(text)', 'public.check_identity_conflict(text,text,text,text,uuid)',
                  'public.department_has_head(bigint,uuid)']::regprocedure[]) f;

insert into _v
select 'A6 no TRUNCATE for anon/authenticated', count(*) = 0, string_agg(table_name || ':' || grantee, ', ')
from information_schema.role_table_grants
where table_schema = 'public' and privilege_type = 'TRUNCATE' and grantee in ('anon', 'authenticated');

insert into _v
select 'A7 login_lookup_attempts is not reachable by API roles',
       not has_table_privilege('anon', 'public.login_lookup_attempts', 'select')
       and not has_table_privilege('authenticated', 'public.login_lookup_attempts', 'select'), null;

-- ── B. Persona checks (impersonation; status changes are rolled back) ───────
create or replace function pg_temp.persona_check(p_uid uuid, p_label text, p_expect_denied boolean)
returns void language plpgsql as $$
declare
  n_other bigint; n_imgs bigint; n_raw bigint; n_del bigint; n_dept bigint; n_audit bigint; n_fsq bigint;
  ins_blocked boolean := false; ins_state text;
  v_any_raw bigint := (select id from public.sast_all_raw_data_survey
                        where "instructor_ID" is distinct from p_uid limit 1);  -- picked as postgres
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  select (select count(*) from public.overall_total_survey   where instructor_id is distinct from p_uid)
       + (select count(*) from public.performance_results    where instructor_id is distinct from p_uid)
       + (select count(*) from public.management_results     where instructor_id is distinct from p_uid)
       + (select count(*) from public.overall_question_means where instructor_id is distinct from p_uid)
       + (select count(*) from public.instructor_ai_suggestions where instructor_id is distinct from p_uid)
       + (select count(*) from public.instructor_wordcloud   where instructor_id is distinct from p_uid)
       + (select count(*) from public.intervention_reports   where instructor_id is distinct from p_uid and dean_id is distinct from p_uid)
    into n_other;
  select count(*) into n_imgs  from public.scan_error_images;
  select count(*) into n_raw   from public.sast_all_raw_data_survey where "instructor_ID" is distinct from p_uid;
  select count(*) into n_dept  from public.department_table where user_id is distinct from p_uid;
  select count(*) into n_audit from public.audit_logs where user_id is distinct from p_uid;
  select count(*) into n_fsq   from public.failed_scan_queue;

  if p_expect_denied then
    -- delete half of H1: must touch 0 rows
    delete from public.sast_all_raw_data_survey
     where id = v_any_raw;
    get diagnostics n_del = row_count;
    begin
      insert into public.sast_all_raw_data_survey (sao_staff_id) values (p_uid);
      ins_state := 'inserted';
    exception
      when insufficient_privilege then ins_blocked := true; ins_state := '42501 (RLS)';
      when others then ins_state := 'other error ' || sqlstate || ' (inconclusive, check constraints)';
    end;
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);  -- back to a trusted SQL-editor caller

  if p_expect_denied then
    insert into _v values
      (p_label || ': results of others = 0', n_other = 0, n_other::text),
      (p_label || ': scan images = 0', n_imgs = 0, n_imgs::text),
      (p_label || ': raw rows of others = 0', n_raw = 0, n_raw::text),
      (p_label || ': department roster of others = 0', n_dept = 0, n_dept::text),
      (p_label || ': audit logs of others = 0', n_audit = 0, n_audit::text),
      (p_label || ': failed_scan_queue = 0', n_fsq = 0, n_fsq::text),
      (p_label || ': raw delete touches 0 rows', n_del = 0, n_del::text),
      (p_label || ': raw insert blocked by RLS', ins_blocked, ins_state);
  else
    insert into _v values
      (p_label || ': still sees results (>0)', n_other > 0, n_other::text),
      (p_label || ': still sees raw rows (>0)', n_raw > 0, n_raw::text);
  end if;
end $$;

do $b$
declare
  v_staff uuid; v_head uuid; v_admin_disabled uuid;
begin
  select su.user_id into v_staff
  from public."Sao_users" su join public.user_info ui on ui.id = su.user_id
  where su.role_id = 2 and ui.account_status = 'approved' and not coalesce(ui.disabled, false) limit 1;

  select dt.user_id into v_head
  from public.department_table dt join public.user_info ui on ui.id = dt.user_id
  where dt.roles = 3 and ui.account_status = 'approved' and not coalesce(ui.disabled, false) limit 1;

  select su.user_id into v_admin_disabled
  from public."Sao_users" su join public.user_info ui on ui.id = su.user_id
  where su.role_id = 1 and ui.account_status = 'disabled' limit 1;

  -- approved first (must keep access), then the same accounts as pending
  if v_staff is not null then
    perform pg_temp.persona_check(v_staff, 'B1 approved SAO_STAFF', false);
    update public.user_info set account_status = 'pending' where id = v_staff;   -- rolled back
    perform pg_temp.persona_check(v_staff, 'B2 pending SAO_STAFF', true);
  else
    insert into _v values ('B1/B2 SAO_STAFF persona', null, 'no approved SAO_STAFF in data');
  end if;

  if v_head is not null then
    perform pg_temp.persona_check(v_head, 'B3 approved DEPARTMENT_HEAD', false);
    update public.user_info set account_status = 'pending' where id = v_head;    -- rolled back
    -- a pending head keeps only own rows; own filed interventions are excluded in the count
    perform pg_temp.persona_check(v_head, 'B4 pending DEPARTMENT_HEAD', true);
  else
    insert into _v values ('B3/B4 head persona', null, 'no approved DEPARTMENT_HEAD in data');
  end if;

  if v_admin_disabled is not null then
    perform pg_temp.persona_check(v_admin_disabled, 'B5 disabled SAO_ADMIN', true);
  else
    insert into _v values ('B5 disabled admin persona', null, 'no disabled SAO_ADMIN in data');
  end if;
end
$b$;

-- ── C. Self-service guards (036 section 4) ─────────────────────────────────
do $c$
declare v_uid uuid; blocked boolean := false;
begin
  select id into v_uid from public.user_info where account_status = 'approved' and not coalesce(disabled, false)
    and not exists (select 1 from public."Sao_users" s where s.user_id = user_info.id and s.role_id = 1) limit 1;
  update public.user_info set disabled = true where id = v_uid;                     -- rolled back
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    update public.user_info set disabled = false where id = v_uid;
  exception when others then blocked := true;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  insert into _v values ('C1 user cannot clear own disabled flag', blocked, null);
end
$c$;

-- ── D. Login rate limit (037): 21st lookup from one IP fails ─────────────────
do $d$
declare i int; failed_at int := null;
begin
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.77"}', true);
  delete from public.login_lookup_attempts where client_ip = '203.0.113.77';
  for i in 1..21 loop
    begin
      perform public.get_login_email('does-not-exist-' || i);
    exception when others then failed_at := i; exit;
    end;
  end loop;
  insert into _v values ('D1 get_login_email blocks the 21st call in 10 min', failed_at = 21, coalesce(failed_at::text, 'never'));
end
$d$;

-- ── E. Retention (038) runs and refuses silly windows ────────────────────────
do $e$
declare r jsonb; refused boolean := false;
begin
  r := public.run_retention_cleanup(90);                                          -- rolled back
  insert into _v values ('E1 run_retention_cleanup(90) returns counts', r ? 'cutoff', r::text);
  begin perform public.run_retention_cleanup(7); exception when others then refused := true; end;
  insert into _v values ('E2 run_retention_cleanup refuses < 30 days', refused, null);
end
$e$;

select * from _v order by check_name;

rollback;
