-- 20240130000020_instructor_name_match.sql
--
-- RUN THIS IN THE SUPABASE SQL EDITOR, not `supabase db push`.
-- Same reason as 000008 and everything after it: 20240130000000_initial_schema.sql
-- is a generated schema DUMP, not a runnable migration.
--
--
-- WHY
-- The n8n "get instructor id" node fuzzy-matches a name from the Google Sheet
-- against user_info, and it keeps dying:
--
--   12:29  Error in 2m 9.5s    "Connection terminated unexpectedly"
--   12:36  Error in 39.4s      same
--   12:38  Error in 1m 3.7s    same
--
-- Three different durations for the same 148 rows. That rules out a statement
-- timeout and it rules out the query being slow -- user_info holds a few dozen
-- rows, so scoring every one of them is sub-millisecond with or without an
-- index. What varies is the CONNECTION: the node issues one query per sheet
-- row, 148 round trips, and something between n8n and Postgres drops the
-- socket partway through. When it does, the whole node fails and nothing
-- downstream runs -- which is why 152 forms were scanned but only 101 ever
-- reached overall_total_survey.
--
-- So the fix is to stop making 148 round trips, not to make each one faster.
-- match_instructors() below resolves the whole sheet in ONE call.
--
--
-- TWO OTHER THINGS THIS FIXES
--
--   SET LOCAL had no effect. It only applies inside a transaction block; sent
--   as a bare statement Postgres warns and moves on, leaving the threshold at
--   the 0.6 default rather than 0.55. And a multi-statement query cannot carry
--   bound parameters over the extended protocol at all. Both functions below
--   pin the threshold as a function attribute instead, so it holds for the
--   duration of the call, needs no session state, and survives any pooler.
--
--   An unmatched name silently vanished. The node is set to "output an empty
--   item if nothing would normally be returned", so a name that matched
--   nobody produced an empty item and that student's form quietly left the
--   pipeline. Both functions LEFT JOIN, so an unmatched name comes back with
--   instructor_id NULL and can be routed to Import Errors instead of
--   disappearing. Worth checking against the 51 missing forms.
-- ============================================================================


-- ── STEP 1: the extension ───────────────────────────────────────────────────
-- Already present -- word_similarity is a pg_trgm function and the current
-- node uses it -- but stated so this file stands on its own.
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ── STEP 2: batch matcher, one call for the whole sheet ─────────────────────
-- The one to use. Takes every instructor name on the sheet, returns one row
-- per name in the same order, matched or not.
--
-- The scoring is character-for-character the one the node uses today, so the
-- same names resolve to the same people. Only the number of round trips
-- changes: 148 -> 1.
CREATE OR REPLACE FUNCTION public.match_instructors(p_names text[])
RETURNS TABLE (
  search_name   text,
  instructor_id uuid,
  first_name    text,
  last_name     text,
  match_score   real
)
LANGUAGE sql
STABLE
SET search_path = public
SET pg_trgm.word_similarity_threshold = 0.55
AS $fn$
  SELECT n.search_name,
         m.id,
         m.first_name,
         m.last_name,
         m.match_score
  FROM unnest(p_names) WITH ORDINALITY AS n(search_name, ord)
  -- LEFT JOIN, not an inner one: a name that matches nobody must still come
  -- back, with a null id, so the caller can report it rather than lose it.
  LEFT JOIN LATERAL (
    SELECT u.id,
           u.first_name,
           u.last_name,
           ((word_similarity(coalesce(u.first_name, ''), n.search_name)
           + word_similarity(coalesce(u.last_name, ''),  n.search_name)) / 2)::real
             AS match_score
    FROM public.user_info u
    WHERE u.account_status = 'approved'
      AND ((word_similarity(coalesce(u.first_name, ''), n.search_name)
          + word_similarity(coalesce(u.last_name, ''),  n.search_name)) / 2) > 0.55
    ORDER BY match_score DESC
    LIMIT 1
  ) m ON true
  ORDER BY n.ord;
$fn$;

COMMENT ON FUNCTION public.match_instructors(text[]) IS
  'Resolves a whole sheet of instructor names in one call, for the n8n import. '
  'One row per input name, in input order; instructor_id is NULL when nothing '
  'scored above 0.55 so the caller can raise an import error instead of '
  'dropping the row. Threshold pinned as a function attribute because SET '
  'LOCAL does not survive outside a transaction.';


-- ── STEP 3: single-name matcher ─────────────────────────────────────────────
-- Kept for any caller that genuinely has one name to resolve. Same scoring.
-- Prefer match_instructors() for the import -- this one still costs a round
-- trip per row, which is the actual failure being fixed here.
CREATE OR REPLACE FUNCTION public.match_instructor(p_name text)
RETURNS TABLE (
  instructor_id uuid,
  first_name    text,
  last_name     text,
  match_score   real
)
LANGUAGE sql
STABLE
SET search_path = public
SET pg_trgm.word_similarity_threshold = 0.55
AS $fn$
  SELECT m.instructor_id, m.first_name, m.last_name, m.match_score
  FROM public.match_instructors(ARRAY[p_name]) m;
$fn$;


-- ── STEP 4: trigram indexes ─────────────────────────────────────────────────
-- Not the fix, and not needed at today's user_info size -- the planner will
-- correctly ignore them on a few dozen rows. Added because match_instructors
-- runs the scan once per sheet row inside the LATERAL, so the cost grows with
-- staff count multiplied by sheet length. Cheap insurance, no behaviour change.
CREATE INDEX IF NOT EXISTS user_info_first_name_trgm
  ON public.user_info USING gin (first_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS user_info_last_name_trgm
  ON public.user_info USING gin (last_name gin_trgm_ops);


-- ============================================================================
-- USING IT FROM n8n
-- ============================================================================
-- Replace the per-row query in "get instructor id" with a single call. The
-- node stops running once per item, so add an Aggregate step before it.
--
--   1. Aggregate node, before the Postgres node
--        Aggregate: All Item Data  ->  or field "Instructor/Professor" into a
--        list. The goal is ONE item holding every name from the sheet.
--
--   2. Postgres node, Execute Query, ONE statement, ONE parameter:
--
--        SELECT * FROM public.match_instructors($1::text[]);
--
--      Query Parameter $1:
--        {{ JSON.stringify($json.names).replace('[','{').replace(/]$/,'}') }}
--
--      or, if passing a Postgres array literal from n8n proves awkward, send
--      JSON instead and unwrap it in the call:
--
--        SELECT * FROM public.match_instructors(
--          ARRAY(SELECT jsonb_array_elements_text($1::jsonb)));
--
--      with $1 = {{ JSON.stringify($json.names) }}
--
--   3. Merge the result back onto the sheet rows by search_name, then branch:
--        instructor_id IS NULL  ->  Import Errors
--        otherwise              ->  carry on as today
--
-- If the workflow restructure has to wait, the single-name function is still a
-- strict improvement on what is in the node now -- one statement, no SET, no
-- silent drop:
--
--   SELECT m.*, $2 AS subject_search_term
--   FROM public.match_instructor($1) m;
--
-- It will not stop the connection drops on its own, though. 148 round trips is
-- the thing that keeps failing.
--
--
-- IF IT STILL DROPS AFTER GOING TO ONE CALL
-- Then the connection itself is the problem, not the volume. Check, in order:
--   - Which port the n8n credential uses. 6543 is the transaction pooler and
--     does not hold session state; 5432 is the session pooler. For a single
--     function call either works, but the transaction pooler is the one that
--     tends to drop long or prepared-statement traffic.
--   - Whether the n8n host has IPv6. A Supabase DIRECT connection is
--     IPv6-only; without it, connections come and go exactly like this.
--   - Supabase project connection limits, if other workflows are also holding
--     connections open.
-- ============================================================================


-- ============================================================================
-- Verification
-- ============================================================================
-- 1. Same answer as the current node, for a name from the sheet:
--
--      SELECT * FROM public.match_instructors(ARRAY['rodz harvey d. licayan']);
--
--    Expect one row with the correct instructor_id and match_score > 0.55.
--
-- 2. An unmatched name comes back rather than vanishing:
--
--      SELECT * FROM public.match_instructors(ARRAY['nobody at all xyzzy']);
--
--    Expect exactly one row, instructor_id NULL. Under the old node this
--    produced an empty item and the form was lost.
--
-- 3. Order and count are preserved -- three in, three out, in order:
--
--      SELECT * FROM public.match_instructors(
--        ARRAY['rodz harvey d. licayan', 'nobody at all xyzzy',
--              'rodz harvey d. licayan']);
--
-- 4. How many names on the sheet resolve to nobody. Paste the distinct
--    instructor names from the Google Sheet in place of the sample array --
--    every row returned is a form the import would silently have dropped:
--
--      SELECT search_name
--      FROM public.match_instructors(ARRAY['name one', 'name two'])
--      WHERE instructor_id IS NULL;
-- ============================================================================
