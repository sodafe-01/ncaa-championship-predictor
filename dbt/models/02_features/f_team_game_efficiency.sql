{{
  config(materialized="table")
}}

WITH ncaa_openers AS (
  SELECT
    season,
    MIN(scheduled_date) AS first_ncaa_date
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
  GROUP BY season
),

base AS (
  SELECT
    tg.game_id,
    tg.season,
    tg.scheduled_date,
    tg.team_id,
    tg.opp_id,
    tg.conf_alias,
    tg.opp_conf_alias,
    tg.is_home,
    tg.is_neutral,
    tg.venue_type,
    tg.postseason_kind,
    tg.ncaa_round,
    n.first_ncaa_date,
    tg.scheduled_date < n.first_ncaa_date AS in_pre_ncaa_scope,
    tg.win,
    tg.points,
    tg.opp_points,
    tg.margin,
    tg.fgm,
    tg.fga,
    tg.tpm,
    tg.tpa,
    tg.ftm,
    tg.fta,
    tg.orb,
    tg.drb,
    tg.tov,
    tg.opp_fgm,
    tg.opp_fga,
    tg.opp_tpm,
    tg.opp_tpa,
    tg.opp_ftm,
    tg.opp_fta,
    tg.opp_orb,
    tg.opp_drb,
    tg.opp_tov,
    tg.poss,
    tg.opp_poss,
    (tg.poss + tg.opp_poss) / 2 AS game_poss
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN ncaa_openers AS n
    ON n.season = tg.season
  WHERE tg.is_closed
    AND tg.is_d1_matchup
    AND tg.has_box_stats
    AND tg.season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
)

SELECT
  game_id,
  season,
  scheduled_date,
  team_id,
  opp_id,
  conf_alias,
  opp_conf_alias,
  is_home,
  is_neutral,
  venue_type,
  postseason_kind,
  ncaa_round,
  first_ncaa_date,
  in_pre_ncaa_scope,
  ROW_NUMBER() OVER (
    PARTITION BY team_id, season
    ORDER BY scheduled_date, game_id
  ) AS game_seq,
  win,
  points,
  opp_points,
  margin,
  fgm,
  fga,
  tpm,
  tpa,
  ftm,
  fta,
  orb,
  drb,
  tov,
  opp_fgm,
  opp_fga,
  opp_tpm,
  opp_tpa,
  opp_ftm,
  opp_fta,
  opp_orb,
  opp_drb,
  opp_tov,
  poss,
  opp_poss,
  game_poss,
  game_poss BETWEEN 45 AND 115 AS is_valid_efficiency_row,
  100 * SAFE_DIVIDE(points, game_poss) AS oe,
  100 * SAFE_DIVIDE(opp_points, game_poss) AS de,
  100 * SAFE_DIVIDE(points, game_poss)
    - 100 * SAFE_DIVIDE(opp_points, game_poss) AS net,
  SAFE_DIVIDE(fgm + 0.5 * tpm, fga) AS efg_pct,
  SAFE_DIVIDE(tov, game_poss) AS tov_pct,
  SAFE_DIVIDE(orb, orb + opp_drb) AS orb_pct,
  SAFE_DIVIDE(fta, fga) AS ftr,
  SAFE_DIVIDE(tpa, fga) AS three_par,
  SAFE_DIVIDE(opp_fgm + 0.5 * opp_tpm, opp_fga) AS opp_efg_pct,
  SAFE_DIVIDE(opp_tov, game_poss) AS opp_tov_pct,
  SAFE_DIVIDE(opp_fta, opp_fga) AS opp_ftr,
  SAFE_DIVIDE(drb, drb + opp_orb) AS drb_pct
FROM base
