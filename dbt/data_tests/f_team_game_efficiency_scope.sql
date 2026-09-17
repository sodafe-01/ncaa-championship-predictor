-- Feature rows contain every eligible source row, and pre-NCAA is exactly the strict date cutoff.
WITH eligible AS (
  SELECT
    game_id,
    team_id
  FROM {{ ref('stg_team_games') }}
  WHERE is_closed
    AND win IS NOT NULL
    AND is_d1_matchup
    AND has_box_stats
    AND season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
),

missing_eligible AS (
  SELECT
    e.game_id,
    e.team_id
  FROM eligible AS e
  LEFT JOIN {{ ref('f_team_game_efficiency') }} AS f
    ON f.game_id = e.game_id
    AND f.team_id = e.team_id
  WHERE f.game_id IS NULL
)

SELECT 'non-closed game reached features' AS failed_check, f.game_id
FROM {{ ref('f_team_game_efficiency') }} f
JOIN {{ ref('stg_games') }} g USING (game_id)
WHERE NOT g.is_closed
UNION ALL
SELECT 'game without a result reached features', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE win IS NULL
UNION ALL
SELECT 'pre_ncaa flag differs from first-NCAA-date cutoff', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE in_pre_ncaa_scope IS DISTINCT FROM (scheduled_date < first_ncaa_date)
UNION ALL
SELECT 'eligible source row missing from features', game_id
FROM missing_eligible
