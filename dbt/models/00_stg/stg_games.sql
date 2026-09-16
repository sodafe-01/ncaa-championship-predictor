-- Grain: one row per game (29,805); every source row kept. Owner: DE1 (story DE-01).
-- Scores use h_points_game / a_points_game: the final score is never NULL and always agrees with the
-- source win flag, while h_points / a_points (box-score sums) are NULL for 4,009 games.
WITH games AS (
  SELECT
    g.*,
    {{ postseason_kind('g.tournament', 'g.tournament_type') }} AS postseason_kind_derived,
    {{ ncaa_round('g.season', 'g.tournament_type', 'g.tournament_round') }} AS ncaa_round_derived,
    home_team.venue_id AS home_team_venue_id
  FROM {{ source('ncaa_basketball', 'mbb_games_sr') }} AS g
  LEFT JOIN {{ source('ncaa_basketball', 'mbb_teams') }} AS home_team ON home_team.id = g.h_id
)

SELECT
  game_id,
  season,
  {{ season_label('season') }} AS season_label,
  scheduled_date,
  gametime,
  status,
  status = 'closed' AS is_closed,
  COALESCE(coverage = 'full', FALSE) AS has_pbp,
  tournament,
  tournament_type,
  tournament_round,
  postseason_kind_derived AS postseason_kind,
  ncaa_round_derived AS ncaa_round,
  {{ ncaa_round_order('ncaa_round_derived') }} AS ncaa_round_order,
  {{ ncaa_region('tournament_type') }} AS ncaa_region,
  conference_game,
  neutral_site AS neutral_site_raw,
  CASE
    WHEN postseason_kind_derived = 'NCAA' THEN TRUE
    WHEN neutral_site IS NOT NULL THEN neutral_site
    WHEN venue_id = home_team_venue_id THEN FALSE
    WHEN tournament = 'Conference' THEN TRUE
    ELSE FALSE
  END AS is_neutral,
  venue_id,
  venue_name,
  venue_city,
  venue_state,
  h_id AS home_team_id,
  h_market AS home_market,
  h_alias AS home_alias,
  h_conf_alias AS home_conf_alias,
  h_division_alias AS home_division_alias,
  a_id AS away_team_id,
  a_market AS away_market,
  a_alias AS away_alias,
  a_conf_alias AS away_conf_alias,
  a_division_alias AS away_division_alias,
  h_points_game AS home_points,
  a_points_game AS away_points,
  NULLIF(h_rank, 0) AS home_ap_rank,
  NULLIF(a_rank, 0) AS away_ap_rank,
  CASE
    WHEN status = 'closed' AND h_points_game != a_points_game
      THEN IF(h_points_game > a_points_game, h_id, a_id)
  END AS winner_team_id,
  COALESCE(h_division_alias = 'D1' AND a_division_alias = 'D1', FALSE) AS is_d1_matchup,
  attendance,
  lead_changes,
  times_tied,
  periods,
  periods > 2 AS is_overtime
FROM games
