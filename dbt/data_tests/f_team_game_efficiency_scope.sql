-- Feature rows are closed games with a result, and the pre-NCAA flag is exactly the strict date cutoff.
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
SELECT 'national postseason game leaked into pre_ncaa', game_id
FROM {{ ref('f_team_game_efficiency') }}
WHERE in_pre_ncaa_scope AND postseason_kind IN ('NCAA', 'NIT', 'CBI', 'CIT')
