-- ============================================================
-- Migration: Identity uniqueness (no duplicate ID / email / name)
-- Run this in your Supabase SQL Editor (Dashboard -> SQL Editor -> New Query)
-- ============================================================
-- DO NOT apply this with `supabase db push`. 20240130000000_initial_schema.sql
-- in this same folder is a generated schema DUMP, not a runnable migration --
-- it says so in its own header -- so this folder is documentation, not an
-- applied migration history. A db push could try to replay that dump. Every
-- migration here from 000002 onward was pasted into the SQL Editor by hand;
-- this one follows the same route.
--
-- Enforces, for every ACTIVE account in public.user_info:
--
--   * university_id  is unique  (case-insensitive, whitespace-trimmed)
--   * email          is unique  (case-insensitive, whitespace-trimmed)
--   * first_name + last_name TOGETHER are unique (case-insensitive)
--
-- The name rule is deliberately on the PAIR, which is what was asked for:
--
--   Juan Cruz  + Juan Cruz     -> BLOCKED  (same first AND same last)
--   Juan Cruz  + Juan Santos   -> allowed  (same first, different last)
--   Juan Cruz  + Maria Cruz    -> allowed  (different first, same last)
--
-- Both of the allowed cases keep working normally, including login: login
-- resolves an account by university_id or email, never by name, so two people
-- sharing a first OR a last name never collide at sign-in.
--
-- WHY THIS LIVES IN THE DATABASE
-- App-side "SELECT then INSERT" checks cannot guarantee uniqueness. Two
-- registrations a few milliseconds apart both read "not taken" and both insert.
-- A unique index is the only thing that actually holds, and it holds no matter
-- which path the row came in through: the signup screen, an admin screen, an
-- edge function, a CSV import, or a hand-typed INSERT in the SQL editor.
--
-- ============================================================
-- STEP 1 (RUN THIS FIRST, BEFORE THE MIGRATION)
-- ============================================================
-- Creating a unique index FAILS if the table already contains duplicates. Run
-- the audit below first and clean up whatever it reports. If it returns zero
-- rows, this migration will apply cleanly.
--
--   -- duplicate university IDs
--   select lower(btrim(university_id)) as key, count(*), array_agg(id) as ids
--   from public.user_info
--   where lower(coalesce(account_status, '')) <> 'deleted'
--     and btrim(coalesce(university_id, '')) <> ''
--   group by 1 having count(*) > 1;
--
--   -- duplicate emails
--   select lower(btrim(email)) as key, count(*), array_agg(id) as ids
--   from public.user_info
--   where lower(coalesce(account_status, '')) <> 'deleted'
--     and btrim(coalesce(email, '')) <> ''
--   group by 1 having count(*) > 1;
--
--   -- duplicate full names
--   select lower(btrim(first_name)) as first, lower(btrim(last_name)) as last,
--          count(*), array_agg(id) as ids
--   from public.user_info
--   where lower(coalesce(account_status, '')) <> 'deleted'
--     and btrim(coalesce(first_name, '')) <> ''
--     and btrim(coalesce(last_name, ''))  <> ''
--   group by 1, 2 having count(*) > 1;
--
-- A duplicate university_id is worth fixing regardless of this migration:
-- sign-in looks an account up by ID and expects exactly one match, so a
-- duplicated ID can lock BOTH of those people out.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Normalisation helper
-- ------------------------------------------------------------
-- One definition of "the same value", used by the indexes, by the conflict
-- check below, and mirrored in the app. Lower-cases, trims the ends, and
-- collapses runs of inner whitespace, so "  Juan   CRUZ " and "juan cruz"
-- are one value. Must be IMMUTABLE to be usable in an index.
CREATE OR REPLACE FUNCTION public.norm_identity(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT nullif(btrim(regexp_replace(lower(value), '\s+', ' ', 'g')), '');
$$;

COMMENT ON FUNCTION public.norm_identity(text) IS
  'Canonical form for identity comparisons: lower-cased, trimmed, inner '
  'whitespace collapsed, empty string folded to NULL. Mirrored in Dart by '
  'IdentityValidator.normalise.';

-- ------------------------------------------------------------
-- 2. Fail early with a readable message if duplicates exist
-- ------------------------------------------------------------
-- Without this the migration still fails, just with a bare
-- "could not create unique index" and no indication of which rows are at fault.
DO $$
DECLARE
  dup_ids   int;
  dup_mails int;
  dup_names int;
BEGIN
  SELECT count(*) INTO dup_ids FROM (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(university_id) IS NOT NULL
    GROUP BY public.norm_identity(university_id) HAVING count(*) > 1
  ) t;

  SELECT count(*) INTO dup_mails FROM (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(email) IS NOT NULL
    GROUP BY public.norm_identity(email) HAVING count(*) > 1
  ) t;

  SELECT count(*) INTO dup_names FROM (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(first_name) IS NOT NULL
      AND public.norm_identity(last_name)  IS NOT NULL
    GROUP BY public.norm_identity(first_name), public.norm_identity(last_name)
    HAVING count(*) > 1
  ) t;

  IF dup_ids > 0 OR dup_mails > 0 OR dup_names > 0 THEN
    RAISE EXCEPTION
      'Cannot enforce identity uniqueness yet: % duplicate university_id group(s), % duplicate email group(s), % duplicate full-name group(s) already exist in user_info. Run the audit queries in the header of this migration, merge or correct those rows, then re-run.',
      dup_ids, dup_mails, dup_names;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 3. The uniqueness guarantees
-- ------------------------------------------------------------
-- All three are PARTIAL indexes that skip soft-deleted rows. A soft-deleted
-- row (account_status = 'deleted') is an archive record, not a live identity,
-- so it must not permanently reserve a name or an ID number. Note that a
-- deleted person's EMAIL is still held by auth.users, so reusing that
-- particular email is rejected by Supabase Auth rather than by this index.
--
-- They are also partial on "value is present": rows with a NULL/blank field
-- are not compared against each other.

CREATE UNIQUE INDEX IF NOT EXISTS user_info_university_id_unique_idx
  ON public.user_info (public.norm_identity(university_id))
  WHERE lower(coalesce(account_status, '')) <> 'deleted'
    AND public.norm_identity(university_id) IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_info_email_unique_idx
  ON public.user_info (public.norm_identity(email))
  WHERE lower(coalesce(account_status, '')) <> 'deleted'
    AND public.norm_identity(email) IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_info_full_name_unique_idx
  ON public.user_info (public.norm_identity(first_name), public.norm_identity(last_name))
  WHERE lower(coalesce(account_status, '')) <> 'deleted'
    AND public.norm_identity(first_name) IS NOT NULL
    AND public.norm_identity(last_name)  IS NOT NULL;

COMMENT ON INDEX public.user_info_full_name_unique_idx IS
  'No two active accounts may share BOTH first and last name. Sharing only '
  'one of the two is allowed and does not affect login.';

-- ------------------------------------------------------------
-- 4. Pre-flight conflict check, callable from the app
-- ------------------------------------------------------------
-- The indexes above reject a duplicate, but only at the moment of INSERT --
-- by which point Supabase Auth has already created the account, leaving an
-- auth user with no profile row. So every screen also checks up front, and
-- this is the function it calls.
--
-- SECURITY DEFINER on purpose, though not because RLS would block the read.
-- user_info currently carries
--     "Allow anonymous email lookup"  SELECT  TO anon  USING (true)
--     "Authenticated users can view profiles"  SELECT  TO authenticated  USING (true)
-- so the table is in practice readable by anyone holding the anon key. The
-- first of those exists so sign-in can resolve a university ID to an email
-- before the user is authenticated.
--
-- Routing through a function instead means (a) this check keeps working if
-- those blanket policies are ever narrowed -- and they should be, since the
-- anon key ships inside the app, so USING (true) exposes every staff name,
-- email, ID and address to anyone who unpacks it -- and (b) callers get back
-- one short field name instead of whole rows.
--
-- Returns exactly one of:
--   'university_id' | 'email' | 'name' | NULL (nothing conflicts)
-- Checked in that order so the most actionable problem is reported first.
CREATE OR REPLACE FUNCTION public.check_identity_conflict(
  p_first_name    text DEFAULT NULL,
  p_last_name     text DEFAULT NULL,
  p_email         text DEFAULT NULL,
  p_university_id text DEFAULT NULL,
  p_exclude_id    uuid DEFAULT NULL   -- the account being edited, so it does
                                      -- not collide with itself on a rename
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n_first text := public.norm_identity(p_first_name);
  n_last  text := public.norm_identity(p_last_name);
  n_mail  text := public.norm_identity(p_email);
  n_uid   text := public.norm_identity(p_university_id);
BEGIN
  IF n_uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(university_id) = n_uid
      AND (p_exclude_id IS NULL OR id <> p_exclude_id)
  ) THEN
    RETURN 'university_id';
  END IF;

  IF n_mail IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(email) = n_mail
      AND (p_exclude_id IS NULL OR id <> p_exclude_id)
  ) THEN
    RETURN 'email';
  END IF;

  IF n_first IS NOT NULL AND n_last IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_info
    WHERE lower(coalesce(account_status, '')) <> 'deleted'
      AND public.norm_identity(first_name) = n_first
      AND public.norm_identity(last_name)  = n_last
      AND (p_exclude_id IS NULL OR id <> p_exclude_id)
  ) THEN
    RETURN 'name';
  END IF;

  RETURN NULL;
END $$;

COMMENT ON FUNCTION public.check_identity_conflict(text, text, text, text, uuid) IS
  'Pre-flight duplicate check for registration and admin create/edit screens. '
  'Returns ''university_id'', ''email'', ''name'', or NULL. Returns a field '
  'name only -- never row data.';

-- The registration screen calls this while nobody is signed in, so anon needs
-- EXECUTE. That does confirm to a caller whether a given email or ID is
-- already registered, which is unavoidable for a form that has to say "that ID
-- is taken" -- and it is strictly less than anon can already read straight from
-- the table today. It returns no names, no IDs and no rows.
REVOKE ALL ON FUNCTION public.check_identity_conflict(text, text, text, text, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.check_identity_conflict(text, text, text, text, uuid)
  TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- 5. Speed up the lookups the app already does
-- ------------------------------------------------------------
-- Sign-in resolves university_id -> email on every login by ID, and the
-- conflict check above filters on normalised email. The unique indexes in
-- section 3 already cover both, but they are partial, so add a plain index for
-- the case-insensitive email lookup across all rows including deleted ones.
CREATE INDEX IF NOT EXISTS user_info_email_lookup_idx
  ON public.user_info (public.norm_identity(email));
