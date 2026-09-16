-- Grain: one row per Sportradar season (2013-2017). Owner: DE1 (story DE-04).
-- model_ready = D1 box scores >= 95% complete AND all 67 NCAA games AND all 351 D1 teams.
WITH games AS (
  SELECT
    season,
    ANY_VALUE(season_label) AS season_label,
    COUNT(*) AS games,
    COUNTIF(is_closed) AS closed_games,
    COUNTIF(postseason_kind = 'NCAA') AS ncaa_games
  FROM {{ ref('stg_games') }}
  GROUP BY season
),

team_games AS (
  SELECT
    season,
    COUNT(DISTINCT IF(division_alias = 'D1', team_id, NULL)) AS d1_teams,
    COUNTIF(is_closed AND is_d1_matchup) AS d1_team_games,
    SAFE_DIVIDE(
      COUNTIF(is_closed AND is_d1_matchup AND has_box_stats),
      COUNTIF(is_closed AND is_d1_matchup)
    ) AS box_stats_rate
  FROM {{ ref('stg_team_games') }}
  GROUP BY season
),

players AS (
  SELECT
    season,
    COUNTIF(played) AS played_player_rows,
    SAFE_DIVIDE(COUNTIF(played AND class IS NOT NULL), COUNTIF(played)) AS class_rate,
    SAFE_DIVIDE(COUNTIF(played AND minutes IS NOT NULL), COUNTIF(played)) AS minutes_rate
  FROM {{ ref('stg_player_games') }}
  GROUP BY season
),

catalog_class AS (
  SELECT percent_null AS catalog_class_percent_null
  FROM {{ ref('dq_column_profile') }}
  WHERE table_name = 'mbb_players_games_sr' AND column_name = 'class'
),

gate AS (
  SELECT
    g.season,
    g.season_label,
    g.games,
    g.closed_games,
    tg.d1_teams,
    g.ncaa_games,
    g.ncaa_games = 67 AS ncaa_complete,
    tg.d1_team_games,
    tg.box_stats_rate,
    tg.box_stats_rate >= 0.95 AS stats_usable,
    p.played_player_rows,
    p.class_rate,
    COALESCE(p.class_rate >= 0.9, FALSE) AS class_usable,
    p.minutes_rate,
    c.catalog_class_percent_null
  FROM games AS g
  LEFT JOIN team_games AS tg ON tg.season = g.season
  LEFT JOIN players AS p ON p.season = g.season
  CROSS JOIN catalog_class AS c
)

SELECT
  season,
  season_label,
  games,
  closed_games,
  d1_teams,
  ncaa_games,
  ncaa_complete,
  d1_team_games,
  box_stats_rate,
  stats_usable,
  played_player_rows,
  class_rate,
  class_usable,
  minutes_rate,
  catalog_class_percent_null,
  COALESCE(stats_usable AND ncaa_complete AND d1_teams = 351, FALSE) AS model_ready,
  CONCAT(
    season_label,
    ': ',
    CASE
      WHEN NOT stats_usable
        THEN CONCAT(
          CAST(ROUND(100 * (1 - box_stats_rate)) AS STRING),
          '% of D1 box scores missing, so not model-ready'
        )
      WHEN NOT ncaa_complete
        THEN CONCAT('only ', CAST(ncaa_games AS STRING), ' of 67 NCAA tournament games, so not model-ready')
      WHEN d1_teams != 351
        THEN CONCAT(CAST(d1_teams AS STRING), ' D1 teams instead of 351, so not model-ready')
      ELSE 'model-ready'
    END,
    IF(class_usable, '; player class available', '; no player class')
  ) AS gate_note
FROM gate
