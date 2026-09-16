{{
  config(materialized="table")
}}

WITH d1_teams AS (
  SELECT
    season,
    team_id
  FROM {{ ref('stg_team_games') }}
  WHERE division_alias = 'D1'
    AND season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
  GROUP BY season, team_id
),

played AS (
  SELECT
    season,
    team_id,
    player_id,
    minutes,
    points,
    class_rank
  FROM {{ ref('stg_player_games') }}
  WHERE played
    AND is_closed
),

next_season_players AS (
  SELECT DISTINCT
    season,
    team_id,
    player_id
  FROM played
),

player_season AS (
  SELECT
    p.season,
    p.team_id,
    p.player_id,
    SUM(p.minutes) AS minutes,
    SUM(p.points) AS points,
    ANY_VALUE(p.class_rank) AS class_rank
  FROM played AS p
  GROUP BY p.season, p.team_id, p.player_id
),

player_with_return AS (
  SELECT
    ps.season,
    ps.team_id,
    ps.minutes,
    ps.points,
    ps.class_rank,
    nxt.player_id IS NOT NULL AS returns_next
  FROM player_season AS ps
  LEFT JOIN next_season_players AS nxt
    ON nxt.player_id = ps.player_id
    AND nxt.team_id = ps.team_id
    AND nxt.season = ps.season + 1
),

team_production AS (
  SELECT
    season,
    team_id,
    CAST(SUM(minutes) AS INT64) AS team_minutes,
    CAST(SUM(points) AS INT64) AS team_points,
    SAFE_DIVIDE(
      SUM(IF(returns_next, minutes, 0)),
      SUM(minutes)
    ) AS ret_min_share_actual_raw,
    SAFE_DIVIDE(
      SUM(IF(returns_next, points, 0)),
      SUM(points)
    ) AS ret_pts_share_actual_raw,
    SAFE_DIVIDE(
      SUM(IF(class_rank IS NOT NULL AND class_rank <= 3, minutes, 0)),
      SUM(IF(class_rank IS NOT NULL, minutes, 0))
    ) AS ret_min_share_class_raw,
    SAFE_DIVIDE(
      SUM(IF(class_rank IS NOT NULL AND class_rank <= 3, points, 0)),
      SUM(IF(class_rank IS NOT NULL, points, 0))
    ) AS ret_pts_share_class_raw
  FROM player_with_return
  GROUP BY season, team_id
),

minutes_coverage AS (
  SELECT
    season,
    team_id,
    SAFE_DIVIDE(COUNTIF(minutes IS NOT NULL), COUNT(*)) AS minutes_coverage
  FROM played
  GROUP BY season, team_id
)

SELECT
  t.season,
  t.season + 1 AS next_season,
  t.team_id,
  p.team_minutes,
  p.team_points,
  IF(
    t.season < {{ var('last_season') }},
    p.ret_min_share_actual_raw,
    NULL
  ) AS ret_min_share_actual,
  IF(
    t.season < {{ var('last_season') }},
    p.ret_pts_share_actual_raw,
    NULL
  ) AS ret_pts_share_actual,
  IF(
    t.season = {{ var('last_season') }},
    p.ret_min_share_class_raw,
    NULL
  ) AS ret_min_share_class,
  IF(
    t.season = {{ var('last_season') }},
    p.ret_pts_share_class_raw,
    NULL
  ) AS ret_pts_share_class,
  COALESCE(
    IF(t.season < {{ var('last_season') }}, p.ret_min_share_actual_raw, NULL),
    IF(t.season = {{ var('last_season') }}, p.ret_min_share_class_raw, NULL)
  ) AS ret_min_share,
  COALESCE(
    IF(t.season < {{ var('last_season') }}, p.ret_pts_share_actual_raw, NULL),
    IF(t.season = {{ var('last_season') }}, p.ret_pts_share_class_raw, NULL)
  ) AS ret_pts_share,
  IF(
    t.season < {{ var('last_season') }},
    'actual',
    'class_proxy'
  ) AS ret_basis,
  c.minutes_coverage
FROM d1_teams AS t
LEFT JOIN team_production AS p
  ON p.season = t.season
  AND p.team_id = t.team_id
LEFT JOIN minutes_coverage AS c
  ON c.season = t.season
  AND c.team_id = t.team_id
