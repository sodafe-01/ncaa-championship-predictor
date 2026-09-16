-- One row per failed sanity check on the rating
WITH s AS (SELECT * FROM {{ ref('f_team_season') }}),
checks AS (
  SELECT 'mean adj_net is not ~0' AS failed_check, CONCAT(CAST(season AS STRING), ' ', scope) AS detail
  FROM s GROUP BY season, scope HAVING ABS(AVG(adj_net)) > 0.5
  UNION ALL
  SELECT 'adj_net weakly correlated with raw_net', CONCAT(CAST(season AS STRING), ' ', scope)
  FROM s GROUP BY season, scope HAVING CORR(adj_net, raw_net) < 0.85
  UNION ALL
  SELECT 'Villanova 2017-18 not top 5 before the tournament', CAST(s.rank_adj_net AS STRING)
  FROM s JOIN {{ ref('stg_teams') }} t ON t.team_id = s.team_id
  WHERE s.season = 2017 AND s.scope = 'pre_ncaa' AND t.alias = 'VILL' AND s.rank_adj_net > 5
  UNION ALL
  SELECT 'champion ranked outside the top 30 before its tournament',
    CONCAT(CAST(s.season AS STRING), ' rank ', CAST(s.rank_adj_net AS STRING))
  FROM s JOIN {{ ref('stg_games') }} g
    ON g.season = s.season AND g.ncaa_round = 'FINAL' AND g.winner_team_id = s.team_id
  WHERE s.scope = 'pre_ncaa' AND s.rank_adj_net > 30
)
SELECT * FROM checks
