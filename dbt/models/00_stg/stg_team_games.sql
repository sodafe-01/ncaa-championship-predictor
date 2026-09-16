-- Grain: one row per team per game (59,610). Owner: DE1 (story DE-01).
-- Labels (season_label, postseason_kind, ncaa_round, is_neutral, is_closed, is_d1_matchup) come from stg_games.
-- Scores use points_game / opp_points_game (final score); tov adds team-charged turnovers.
SELECT
  tg.game_id,
  g.season,
  g.season_label,
  g.scheduled_date,
  tg.team_id,
  tg.market,
  tg.name,
  tg.alias,
  tg.conf_alias,
  tg.division_alias,
  tg.opp_id,
  tg.opp_market,
  tg.opp_alias,
  tg.opp_conf_alias,
  tg.opp_division_alias,
  tg.home_team AS is_home,
  g.is_neutral,
  CASE
    WHEN g.is_neutral THEN 'neutral'
    WHEN tg.home_team THEN 'home'
    ELSE 'away'
  END AS venue_type,
  g.postseason_kind,
  g.ncaa_round,
  g.ncaa_round_order,
  g.conference_game,
  g.is_closed,
  g.is_d1_matchup,
  tg.win,
  tg.points_game AS points,
  tg.opp_points_game AS opp_points,
  tg.points_game - tg.opp_points_game AS margin,
  tg.field_goals_made AS fgm,
  tg.field_goals_att AS fga,
  tg.three_points_made AS tpm,
  tg.three_points_att AS tpa,
  tg.free_throws_made AS ftm,
  tg.free_throws_att AS fta,
  tg.offensive_rebounds AS orb,
  tg.defensive_rebounds AS drb,
  tg.rebounds AS reb,
  tg.team_rebounds AS team_reb,
  tg.assists AS ast,
  tg.steals AS stl,
  tg.blocks AS blk,
  tg.personal_fouls AS pf,
  tg.turnovers + COALESCE(tg.team_turnovers, 0) AS tov,
  tg.opp_field_goals_made AS opp_fgm,
  tg.opp_field_goals_att AS opp_fga,
  tg.opp_three_points_made AS opp_tpm,
  tg.opp_three_points_att AS opp_tpa,
  tg.opp_free_throws_made AS opp_ftm,
  tg.opp_free_throws_att AS opp_fta,
  tg.opp_offensive_rebounds AS opp_orb,
  tg.opp_defensive_rebounds AS opp_drb,
  tg.opp_assists AS opp_ast,
  tg.opp_steals AS opp_stl,
  tg.opp_blocks AS opp_blk,
  tg.opp_personal_fouls AS opp_pf,
  tg.opp_turnovers + COALESCE(tg.opp_team_turnovers, 0) AS opp_tov,
  (
    {{ possessions(
      'tg.field_goals_att',
      'tg.offensive_rebounds',
      'tg.turnovers + COALESCE(tg.team_turnovers, 0)',
      'tg.free_throws_att'
    ) }}
  ) AS poss,
  (
    {{ possessions(
      'tg.opp_field_goals_att',
      'tg.opp_offensive_rebounds',
      'tg.opp_turnovers + COALESCE(tg.opp_team_turnovers, 0)',
      'tg.opp_free_throws_att'
    ) }}
  ) AS opp_poss,
  (
    tg.field_goals_att IS NOT NULL AND tg.offensive_rebounds IS NOT NULL
    AND tg.turnovers IS NOT NULL AND tg.free_throws_att IS NOT NULL
    AND tg.opp_field_goals_att IS NOT NULL AND tg.opp_offensive_rebounds IS NOT NULL
    AND tg.opp_turnovers IS NOT NULL AND tg.opp_free_throws_att IS NOT NULL
    -- 822 rows (mostly vs non-D1 opponents) carry zero-filled box scores with points scored: treat as missing
    AND tg.field_goals_att > 0 AND tg.opp_field_goals_att > 0
  ) AS has_box_stats
FROM {{ source('ncaa_basketball', 'mbb_teams_games_sr') }} AS tg
JOIN {{ ref('stg_games') }} AS g ON g.game_id = tg.game_id
