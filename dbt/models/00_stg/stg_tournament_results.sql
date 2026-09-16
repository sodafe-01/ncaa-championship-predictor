-- Grain: one row per historical NCAA tournament game (2,117; March 1985 to March 2017). Owner: DE1 (story DE-03).
-- The source season is the tournament (end) year: season here is the start year, source season - 1.
-- Seeds are strings '01'-'16'; region codes W/X/Y/Z are not region names.
WITH games AS (
  SELECT
    h.*,
    h.season - 1 AS start_season,
    {{ hist_round_to_ncaa_round('h.round') }} AS ncaa_round_derived,
    SAFE_CAST(h.win_seed AS INT64) AS win_seed_int,
    SAFE_CAST(h.lose_seed AS INT64) AS lose_seed_int
  FROM {{ source('ncaa_basketball', 'mbb_historical_tournament_games') }} AS h
)

SELECT
  start_season AS season,
  {{ season_label('start_season') }} AS season_label,
  season AS tournament_year,
  ncaa_round_derived AS ncaa_round,
  {{ ncaa_round_order('ncaa_round_derived') }} AS ncaa_round_order,
  game_date,
  win_team_id,
  lose_team_id,
  win_seed_int AS win_seed,
  lose_seed_int AS lose_seed,
  win_region AS win_region_code,
  lose_region AS lose_region_code,
  win_pts,
  lose_pts,
  num_ot,
  win_seed_int > lose_seed_int AS is_upset
FROM games
