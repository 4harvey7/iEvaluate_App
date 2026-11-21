-- ============================================================================
-- 20240130000039_db_hygiene.sql   (security review 2026-11-21, L10 / I2 / F7)
--
-- RUN IN THE SUPABASE SQL EDITOR AFTER 000036 (036 moves the policies that use
-- get_user_dept_and_role / get_auth_user_dept_id / get_auth_dept_id to
-- `authenticated`, which makes the anon revokes below safe).
--
-- WHAT IT DOES
--   1. Pins search_path on the 17 remaining functions flagged by advisor lint
--      0011 (function_search_path_mutable). `public, extensions` so functions
--      that use extension functions (pg_trgm etc.) unqualified keep working.
--   2. snapshot_term_departments(uuid) wrote rows for ANY caller, anon
--      included. It now requires an approved SAO admin (the only app caller,
--      sao_admin_settings.dart) or a trusted DB caller (service role / SQL
--      editor / n8n Postgres).
--   3. Revokes EXECUTE from anon on SECURITY DEFINER helpers that no anon
--      policy and no pre-login screen uses. NOT revoked on purpose:
--        is_sao / is_dean / is_dept_head / is_sao_admin / check_is_sao_admin /
--        get_my_dept_id  -> used inside policies that apply TO public; an anon
--          query on those tables would then fail with "permission denied for
--          function" instead of returning no rows.
--        get_login_email, check_identity_conflict, department_has_head
--          -> called before sign-in (login / registration).
--   4. Revokes TRUNCATE on every public table from anon and authenticated
--      (not reachable through PostgREST; defence in depth).
--
-- Leaked-password protection (L9) is a dashboard setting, not SQL: see
-- Security_Fixes_Applied.md.
--
-- Safe to run more than once. One transaction.
-- ROLLBACK:
--   alter function <each> reset search_path;
--   grant execute on function <each revoked> to anon;
--   grant truncate on all tables in schema public to anon, authenticated;
--   re-create snapshot_term_departments without the guard (body below minus
--   the IF block).
-- ============================================================================

begin;

-- 1. search_path
do $sp$
declare
  f text;
begin
  foreach f in array array[
    'public.eval_scale_max(jsonb)',
    'public.eval_verbal_label(jsonb,numeric)',
    'public.find_instructor(text)',
    'public.forbid_assignment_delete_with_results()',
    'public.forbid_department_delete()',
    'public.forbid_subject_delete()',
    'public.get_auth_dept_id()',
    'public.get_auth_user_dept_id()',
    'public.get_current_academic_term()',
    'public.get_fuzzy_instructor_id(text)',
    'public.get_my_dept_id()',
    'public.norm_identity(text)',
    'public.update_updated_at()',
    'public.upsert_instructor_ai_suggestion(uuid,text,text,text,text)',
    'public.upsert_instructor_summary(uuid,text)',
    'public.upsert_wordcloud(integer,text,integer)',
    'public.upsert_wordcloud(uuid,text,integer)',
    -- recreated with search_path in 036; harmless to repeat
    'public.check_is_sao_admin()',
    'public.is_admin_check()'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('alter function %s set search_path = public, extensions', f);
    else
      raise notice 'skipped (not found): %', f;
    end if;
  end loop;
end
$sp$;

-- 2. snapshot_term_departments: admin only
create or replace function public.snapshot_term_departments(p_term_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
DECLARE
  inserted int;
BEGIN
  IF NOT (public.is_trusted_db_caller() OR public.is_approved_sao_admin()) THEN
    RAISE EXCEPTION 'Forbidden: only an SAO administrator can snapshot departments.';
  END IF;

  IF p_term_id IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO public.instructor_department_terms
    (term_id, instructor_id, department_id, is_primary)
  SELECT p_term_id, d.instructor_id, d.department_id, d.is_primary
  FROM public.instructor_departments d
  ON CONFLICT (term_id, instructor_id, department_id) DO NOTHING;

  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END
$function$;

-- 3. anon EXECUTE
revoke execute on function public.snapshot_term_departments(uuid) from public, anon;
grant  execute on function public.snapshot_term_departments(uuid) to authenticated, service_role;

revoke execute on function public.is_admin_check()          from public, anon;
revoke execute on function public.get_user_dept_and_role()  from public, anon;
revoke execute on function public.get_auth_user_dept_id()   from public, anon;
revoke execute on function public.get_auth_dept_id()        from public, anon;
grant  execute on function public.is_admin_check()          to authenticated, service_role;
grant  execute on function public.get_user_dept_and_role()  to authenticated, service_role;
grant  execute on function public.get_auth_user_dept_id()   to authenticated, service_role;
grant  execute on function public.get_auth_dept_id()        to authenticated, service_role;

-- 4. TRUNCATE
revoke truncate on all tables in schema public from anon, authenticated;

commit;
