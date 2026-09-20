-- 20240130000013_verification_purpose.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
--
-- admin_verifications holds one emailed 6-digit code per user, keyed by
-- admin_id (20240130000000_initial_schema.sql:63-70). Until now every code in
-- it meant the same thing: "this SAO admin is about to perform an admin
-- action". Self-deactivation adds a second kind of code, requested by ordinary
-- instructors and gatherers rather than admins, and authorising something quite
-- different -- banning your own account.
--
-- With one unlabelled row per user those two are indistinguishable. A code
-- emailed to approve a role change would also unlock account deletion, which
-- is not what the recipient was told the code was for.
--
-- So the row gets a purpose, and every consumer filters on it. The primary key
-- stays admin_id, which means requesting a second code of a different purpose
-- overwrites the first. That is deliberate: it fails closed. The overwritten
-- code stops working and the user is told to request a new one, rather than two
-- live codes existing at once.
--
-- Existing rows are ADMIN_ACTION -- that is the only thing they can have been.

alter table public.admin_verifications
  add column if not exists purpose text not null default 'ADMIN_ACTION';

-- Only the two the application knows how to issue and check. A typo in a
-- filter would otherwise silently match nothing and read as "code expired".
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.admin_verifications'::regclass
      and conname = 'admin_verifications_purpose_check'
  ) then
    alter table public.admin_verifications
      add constraint admin_verifications_purpose_check
      check (purpose in ('ADMIN_ACTION', 'SELF_DEACTIVATE'));
  end if;
end $$;

comment on column public.admin_verifications.purpose is
  'What the code authorises. ADMIN_ACTION = SAO admin mutation (role change, '
  'user creation). SELF_DEACTIVATE = the account owner deactivating their own '
  'account. Consumers must filter on this; a code issued for one purpose must '
  'never satisfy the other.';


-- ── Verification ─────────────────────────────────────────────────────────────
--   select admin_id, purpose, attempts, expires_at from public.admin_verifications;
-- Expect every pre-existing row to read ADMIN_ACTION.
