-- p(a, b) + p(b, a) = 1 for every pair, and every pair has its mirror
SELECT a.scenario, a.team_a_id, a.team_b_id, a.p_a_wins, b.p_a_wins AS p_b_wins
FROM {{ ref('p_matchup') }} AS a
LEFT JOIN {{ ref('p_matchup') }} AS b
  ON b.scenario = a.scenario
  AND b.team_a_id = a.team_b_id
  AND b.team_b_id = a.team_a_id
WHERE b.team_a_id IS NULL
   OR ABS(a.p_a_wins + b.p_a_wins - 1) > 1e-9
