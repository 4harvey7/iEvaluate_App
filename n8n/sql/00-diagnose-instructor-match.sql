-- Run this FIRST, in the Supabase SQL editor. It answers one question:
-- why did "get instructor id" match nobody for all 148 sheet rows?
--
-- Read the result like this:
--   No rows at all      -> the instructor is not in user_info. Nothing in n8n
--                          can fix that; the account has to exist first.
--   account_status is
--   not lowercase
--   'approved'          -> that is the whole bug. The lower() in
--                          get-instructor-id.sql fixes it.
--   fn_score/ln_score
--   both below 0.55     -> the name on the sheet is too far from the name in
--                          the database. Lower the 0.55 threshold, or fix the
--                          spelling on the sheet.
SELECT id,
       first_name,
       last_name,
       account_status,
       word_similarity(coalesce(first_name, ''), 'rodz harvey d. licayan') AS fn_score,
       word_similarity(coalesce(last_name,  ''), 'rodz harvey d. licayan') AS ln_score,
       ((word_similarity(coalesce(first_name, ''), 'rodz harvey d. licayan')
       + word_similarity(coalesce(last_name,  ''), 'rodz harvey d. licayan')) / 2) AS match_score
FROM public.user_info
WHERE first_name ILIKE '%licayan%'
   OR last_name  ILIKE '%licayan%'
   OR first_name ILIKE '%rodz%'
   OR last_name  ILIKE '%rodz%';


-- If the above returns nothing, widen it -- list every approved account and
-- see what the matcher is actually working with:
--
--   SELECT id, first_name, last_name, account_status
--   FROM public.user_info
--   ORDER BY account_status, last_name;
