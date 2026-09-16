-- Each game has exactly two team rows matching stg_games, and each decided closed game has one winner
WITH per_game AS (
  SELECT tg.game_id, COUNT(*) AS n_rows, COUNTIF(tg.win) AS n_wins,
    LOGICAL_AND(tg.team_id IN (g.home_team_id, g.away_team_id)) AS teams_match
  FROM {{ ref('stg_team_games') }} tg
  JOIN {{ ref('stg_games') }} g USING (game_id)
  GROUP BY tg.game_id
)
SELECT g.game_id, p.n_rows, p.n_wins, p.teams_match
FROM {{ ref('stg_games') }} g
LEFT JOIN per_game p USING (game_id)
WHERE p.n_rows IS DISTINCT FROM 2
   OR NOT p.teams_match
   OR (g.is_closed AND g.home_points IS NOT NULL AND g.home_points != g.away_points AND p.n_wins != 1)
