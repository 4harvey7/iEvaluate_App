-- Always returns exactly one row, matched or not. The LEFT JOIN LATERAL is the
-- point: an unmatched name comes back with instructor_id NULL instead of no
-- row at all, so "Always Output Data" never fires an empty item and the paired
-- -item chain downstream stays intact.
--
-- $2 rides through untouched so "get subject id" never has to reach back to
-- the sheet node for it.
SELECT
  m.id         AS instructor_id,
  m.first_name,
  m.last_name,
  m.match_score,
  $2           AS subject_search_term
FROM (SELECT 1) AS one
LEFT JOIN LATERAL (
  SELECT u.id, u.first_name, u.last_name,
         ((word_similarity(COALESCE(u.first_name, ''), $1)
         + word_similarity(COALESCE(u.last_name,  ''), $1)) / 2) AS match_score
  FROM public.user_info u
  -- lower(): the column default is 'Pending', the app writes 'approved'.
  WHERE lower(COALESCE(u.account_status, '')) = 'approved'
    AND ((word_similarity(COALESCE(u.first_name, ''), $1)
        + word_similarity(COALESCE(u.last_name,  ''), $1)) / 2) > 0.55
  ORDER BY match_score DESC
  LIMIT 1
) m ON true;
