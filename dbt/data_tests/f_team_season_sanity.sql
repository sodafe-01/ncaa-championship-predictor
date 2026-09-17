-- One row per failed sanity check on the rating
WITH scopes AS (
  SELECT 'pre_ncaa' AS scope
  UNION ALL
  SELECT 'full' AS scope
),
expected_tempo AS (
  SELECT
    e.season,
    sc.scope,
    e.team_id,
    AVG(e.game_poss) AS tempo
  FROM {{ ref('f_team_game_efficiency') }} AS e
  CROSS JOIN scopes AS sc
  WHERE e.is_valid_efficiency_row
    AND (sc.scope = 'full' OR e.in_pre_ncaa_scope)
  GROUP BY e.season, sc.scope, e.team_id
),
s AS (SELECT * FROM {{ ref('f_team_season') }}),
checks AS (
  SELECT 'mean adj_net is not ~0' AS failed_check, CONCAT(CAST(season AS STRING), ' ', scope) AS detail
  FROM s GROUP BY season, scope HAVING ABS(AVG(adj_net)) > 0.5
  UNION ALL
  SELECT 'adj_net weakly correlated with raw_net', CONCAT(CAST(season AS STRING), ' ', scope)
  FROM s GROUP BY season, scope HAVING CORR(adj_net, raw_net) < 0.85
  UNION ALL
  SELECT 'tempo differs from AVG(game_poss)', CONCAT(CAST(s.season AS STRING), ' ', s.scope, ' ', s.team_id)
  FROM s
  INNER JOIN expected_tempo AS e
    ON e.season = s.season
    AND e.scope = s.scope
    AND e.team_id = s.team_id
  WHERE ABS(s.tempo - e.tempo) > 1e-9
  UNION ALL
  SELECT 'conference_strength differs within conference or from conference mean',
    CONCAT(CAST(season AS STRING), ' ', scope, ' ', conf_alias)
  FROM s
  GROUP BY season, scope, conf_alias
  HAVING MAX(conference_strength) - MIN(conference_strength) > 1e-9
     OR ABS(ANY_VALUE(conference_strength) - AVG(adj_net)) > 1e-9
  UNION ALL
  SELECT 'Villanova 2017-18 not top 5 before the tournament', CAST(s.rank_adj_net AS STRING)
  FROM s JOIN {{ ref('stg_teams') }} t ON t.team_id = s.team_id
  WHERE s.season = 2017 AND s.scope = 'pre_ncaa' AND t.alias = 'VILL' AND s.rank_adj_net > 5
  UNION ALL
  SELECT 'champion ranked outside the top 30 before its tournament',
    CONCAT(CAST(s.season AS STRING), ' rank ', CAST(s.rank_adj_net AS STRING))
  FROM s JOIN {{ ref('stg_games') }} g
    ON g.season = s.season AND g.ncaa_round = 'FINAL' AND g.winner_team_id = s.team_id
  WHERE s.scope = 'pre_ncaa' AND s.season BETWEEN 2014 AND 2016 AND s.rank_adj_net > 30
)
SELECT * FROM checks
