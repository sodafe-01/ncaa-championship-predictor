-- A team's offensive efficiency equals its opponent's defensive efficiency in the same game
SELECT a.game_id, a.team_id, a.oe, b.de
FROM {{ ref('f_team_game_efficiency') }} AS a
JOIN {{ ref('f_team_game_efficiency') }} AS b
  ON b.game_id = a.game_id
  AND b.team_id = a.opp_id
WHERE ABS(a.oe - b.de) > 0.001
