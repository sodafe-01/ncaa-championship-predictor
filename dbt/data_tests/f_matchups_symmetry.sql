-- The two orderings of a game mirror each other
SELECT a.game_id, a.team_a_id
FROM {{ ref('f_matchups') }} AS a
JOIN {{ ref('f_matchups') }} AS b
  ON b.game_id = a.game_id
  AND b.team_a_id = a.team_b_id
WHERE a.label_a_wins + b.label_a_wins != 1
   OR ABS(a.d_adj_net + b.d_adj_net) > 1e-9
   OR a.home_indicator + b.home_indicator != 0
