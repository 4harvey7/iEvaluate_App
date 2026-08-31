-- 20240130000016_one_department_head_per_department.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- Same reason as 000008 and 000014: 20240130000000_initial_schema.sql is a
-- generated schema DUMP, not a runnable migration, so a push would try to
-- replay it. Every migration from 000002 onward was pasted in by hand.
--
--
-- THE RULE
-- A department has at most ONE head. "Head" means any role that
-- role_nav_config.roleFromString routes to UserRole.deptHead:
--
--   DEPARTMENT_HEAD / DEPARTMENT-HEAD / DEPARTMENT HEAD / DEAN
--
-- DEAN is included on purpose. Two accounts holding the dept-head dashboard
-- for the same department is the exact situation this rule exists to prevent,
-- and the app cannot tell those two roles apart -- both land on the same
-- screens with the same powers over the same faculty roster.
--
--
-- WHY IT HAS TO LIVE HERE TOO
-- Four separate paths write a head into department_table:
--
--   1. public registration            (auth_service.dart signUp)
--   2. SAO Admin > Add Academic       (admin-create-academic edge function)
--   3. SAO Admin > Edit Profile       (admin-update-role edge function, both a
--                                      promotion and a department move)
--   4. the REST API directly, with the publishable key that ships in the app
--
-- All four are guarded in code so the user gets a readable message, but (4)
-- cannot be, and any check-then-insert is a race: two promotions milliseconds
-- apart both read "vacant" and both write. The trigger below is what actually
-- holds, and it takes a per-department advisory lock so even the race resolves
-- to one head.
--
--
-- WHAT THIS DOES NOT DO
-- It does not pick a head when a department has none, and it does not touch
-- existing rows. A department that already has two heads keeps them until
-- someone is re-roled -- a trigger only sees new writes. Run the audit in
-- STEP 0 first and clean up whatever it reports, otherwise the app will refuse
-- edits to those departments while still displaying only one of the heads
-- (manage_departments_screen keeps the last one it reads).


-- ============================================================
-- STEP 0 (RUN THIS FIRST, BEFORE THE MIGRATION)
-- ============================================================
-- Departments that already hold more than one head. Expect zero rows.
--
--   select dn.id, dn.d_name, count(*) as heads,
--          array_agg(trim(concat_ws(' ', ui.first_name, ui.last_name))) as who
--   from public.department_table dt
--   join public.roles r on r.id = dt.roles
--   left join public.user_info ui on ui.id = dt.user_id
--   left join public.department_name dn on dn.id = dt."Department_name_ID"
--   where upper(regexp_replace(coalesce(r."Roles", ''), '[\s_-]+', '-', 'g'))
--         in ('DEPARTMENT-HEAD', 'DEAN')
--   group by dn.id, dn.d_name
--   having count(*) > 1;


-- == 1. Which role ids count as a department head ============================
-- Resolved by NAME, never by a hardcoded id. The roles table has no fixed
-- ordering and 20240130000014 already had to fix one policy that assumed
-- role_id = 1.
create or replace function public.is_department_head_role(p_role_id bigint)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.roles r
    where r.id = p_role_id
      and upper(regexp_replace(coalesce(r."Roles", ''), '[\s_-]+', '-', 'g'))
          in ('DEPARTMENT-HEAD', 'DEAN')
  );
$$;

comment on function public.is_department_head_role(bigint) is
  'True when this roles.id is a department-head role (DEPARTMENT_HEAD, '
  'DEPARTMENT-HEAD, DEPARTMENT HEAD or DEAN). Matched by name so a reordered '
  'roles table cannot silently change the answer.';


-- == 2. Pre-flight check the app calls =======================================
-- "Is the chair for this department already taken?" -- asked by the
-- registration screen before an account is created and by SAO Admin before an
-- OTP is sent, so the user reads a sentence instead of a failed insert.
--
-- Returns a BOOLEAN and nothing else. The registration screen runs while
-- nobody is signed in, so anon needs EXECUTE, and anon must not be able to
-- pull a staff member's name out of this. The SAO Admin screens already hold
-- every academic row and name the sitting head from that.
--
-- p_exclude_user_id is the account being edited, so re-saving the sitting head
-- does not report them as blocking themselves.
create or replace function public.department_has_head(
  p_department_id   bigint,
  p_exclude_user_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.department_table dt
    left join public.user_info ui on ui.id = dt.user_id
    where dt."Department_name_ID" = p_department_id
      and public.is_department_head_role(dt.roles)
      and (p_exclude_user_id is null or dt.user_id is distinct from p_exclude_user_id)
      -- A deleted account is not sitting in the chair.
      and lower(coalesce(ui.account_status, '')) <> 'deleted'
  );
$$;

comment on function public.department_has_head(bigint, uuid) is
  'Pre-flight check for the registration screen and the SAO Admin create/edit '
  'dialogs: does this department already have a head? Returns a boolean only -- '
  'never a name or a row. The trigger department_table_one_head is the actual '
  'guarantee.';

revoke all on function public.department_has_head(bigint, uuid) from public;
grant execute on function public.department_has_head(bigint, uuid)
  to anon, authenticated, service_role;


-- == 3. The guarantee ========================================================
create or replace function public.enforce_one_department_head()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_head_name text;
  v_dept_name text;
begin
  -- Not a head, or no department to be head of: nothing to enforce.
  if new."Department_name_ID" is null
     or not public.is_department_head_role(new.roles) then
    return new;
  end if;

  -- An UPDATE that leaves both the department and the role alone is a rename
  -- or a no-op save. Re-checking it would make the sitting head block their
  -- own edit.
  if tg_op = 'UPDATE'
     and old."Department_name_ID" is not distinct from new."Department_name_ID"
     and old.roles is not distinct from new.roles then
    return new;
  end if;

  -- Serialise head assignment per department. Without this, two promotions in
  -- flight at the same moment both read an empty chair and both succeed.
  -- Transaction-scoped, so it is released on commit or rollback.
  perform pg_advisory_xact_lock(
    hashtext('department_head'),
    (new."Department_name_ID" % 2147483647)::int
  );

  select trim(concat_ws(' ', ui.first_name, ui.last_name))
    into v_head_name
  from public.department_table dt
  left join public.user_info ui on ui.id = dt.user_id
  where dt."Department_name_ID" = new."Department_name_ID"
    and dt.id <> new.id
    and dt.user_id is distinct from new.user_id
    and public.is_department_head_role(dt.roles)
    and lower(coalesce(ui.account_status, '')) <> 'deleted'
  limit 1;

  if v_head_name is null then
    return new;
  end if;

  select d_name into v_dept_name
  from public.department_name
  where id = new."Department_name_ID";

  raise exception
    'Department head already assigned: % already holds the department head '
    'role for %. A department can only have one head -- change that person''s '
    'role first, or choose a different department.',
    coalesce(nullif(v_head_name, ''), 'another account'),
    coalesce(v_dept_name, 'this department')
    using errcode = 'unique_violation';
end $$;

comment on function public.enforce_one_department_head() is
  'Rejects a second department head for the same department, whichever path '
  'the write came from. Message is written to be shown to a user as-is; the '
  'edge functions and the Flutter screens pass it straight through.';

drop trigger if exists department_table_one_head on public.department_table;
create trigger department_table_one_head
  before insert or update on public.department_table
  for each row execute function public.enforce_one_department_head();


-- == Verification ============================================================
-- 1. Expect the trigger to exist.
--    select c.relname, t.tgname from pg_trigger t
--      join pg_class c on c.oid = t.tgrelid
--     where not t.tgisinternal and t.tgname = 'department_table_one_head';
--
-- 2. Expect true for a department that has a head, false for one that does not.
--    select dn.d_name, public.department_has_head(dn.id)
--      from public.department_name dn order by dn.d_name;
--
-- 3. Expect the exception, and expect it to roll back. Pick a department that
--    already has a head and any head role id:
--    begin;
--      insert into public.department_table (user_id, "Department_name_ID", roles)
--      values (null, <dept_with_head_id>, <dept_head_role_id>);
--    rollback;
--
-- 4. Expect success: the sitting head saving their own row unchanged.
--    begin;
--      update public.department_table set created_at = created_at
--       where id = <sitting_head_row_id>;
--    rollback;
