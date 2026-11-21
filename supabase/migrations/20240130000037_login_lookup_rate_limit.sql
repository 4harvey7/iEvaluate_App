-- ============================================================================
-- 20240130000037_login_lookup_rate_limit.sql   (security review 2026-11-21, M1 / F2)
--
-- RUN IN THE SUPABASE SQL EDITOR, on a branch / local stack first.
-- Requires 000034 (get_login_email).
--
-- PROBLEM (M1): get_login_email(text) is callable by anon with no limit, so
-- anyone with the public anon key can map university IDs to e-mails in bulk.
--
-- FIX (no app change needed): same name, same argument, same return value.
-- The Flutter login (lib/core/services/auth_service.dart) calls it with
-- supabase.rpc(...) which is a POST, so the function may now write.
--   * Each call is logged in public.login_lookup_attempts (client IP from the
--     PostgREST request headers, never the looked-up ID).
--   * More than 20 lookups from one IP in 10 minutes raises an error; the app
--     shows its generic "Incorrect ID or password" message for any error.
--   * Rows older than 1 day are purged on each call.
-- Limits are per IP: a campus NAT shares one bucket. 20 / 10 min is far above
-- normal use (about 40 staff accounts). Raise v_max if staff get blocked.
--
-- Residual risk: a slow (or IP-rotating) attacker can still enumerate. The full
-- fix is server-side login-by-ID (edge function that signs in and never returns
-- the e-mail) -- NEEDS USER DECISION, see Security_Fixes_Applied.md.
--
-- Safe to run more than once. One transaction.
-- ROLLBACK: re-run section 2 of 20240130000034 (the old SQL body of
-- get_login_email + its grants), then `drop table public.login_lookup_attempts;`
-- ============================================================================

begin;

create table if not exists public.login_lookup_attempts (
  id         bigint generated always as identity primary key,
  client_ip  text        not null,
  created_at timestamptz not null default now()
);
create index if not exists login_lookup_attempts_ip_time
  on public.login_lookup_attempts (client_ip, created_at);

alter table public.login_lookup_attempts enable row level security;
-- No policies: deny-all through the API. Only the definer function writes.
revoke all on table public.login_lookup_attempts from anon, authenticated;

create or replace function public.get_login_email(p_university_id text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_max     constant int := 20;
  v_window  constant interval := interval '10 minutes';
  v_headers json;
  v_ip      text;
  v_recent  int;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    v_headers := null;
  end;
  -- Supabase's gateway sets x-forwarded-for; first hop = the client.
  v_ip := coalesce(
    nullif(btrim(split_part(v_headers ->> 'x-forwarded-for', ',', 1)), ''),
    nullif(btrim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(btrim(v_headers ->> 'x-real-ip'), ''),
    'unknown');

  delete from public.login_lookup_attempts where created_at < now() - interval '1 day';

  select count(*) into v_recent
  from public.login_lookup_attempts
  where client_ip = v_ip and created_at > now() - v_window;

  if v_recent >= v_max then
    raise exception 'Too many attempts. Please wait a few minutes and try again.'
      using errcode = 'P0429';
  end if;

  insert into public.login_lookup_attempts (client_ip) values (v_ip);

  return (
    select ui.email
    from public.user_info ui
    where nullif(btrim(p_university_id), '') is not null
      and lower(btrim(ui.university_id)) = lower(btrim(p_university_id))
    order by ui.created_at asc
    limit 1
  );
end;
$$;

comment on function public.get_login_email(text) is
  'Login-by-ID: email for one exact university ID, or NULL. Rate limited per '
  'client IP (20 / 10 min) via login_lookup_attempts (037).';

revoke all on function public.get_login_email(text) from public;
grant execute on function public.get_login_email(text) to anon, authenticated, service_role;

commit;
