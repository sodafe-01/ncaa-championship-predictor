{{
  config(materialized="table")
}}

SELECT
  e.game_id,
  e.season,
  e.scheduled_date,
  e.postseason_kind,
  e.ncaa_round,
  e.in_pre_ncaa_scope,
  e.in_pre_ncaa_scope AS is_training_row,
  e.postseason_kind = 'NCAA' AS is_tournament_row,
  e.team_id AS team_a_id,
  e.opp_id AS team_b_id,
  e.venue_type AS venue_a,
  CASE
    WHEN e.venue_type = 'neutral' THEN 0
    WHEN e.venue_type = 'home' THEN 1
    WHEN e.venue_type = 'away' THEN -1
  END AS home_indicator,
  IF(e.win, 1, 0) AS label_a_wins,
  e.margin AS margin_a,
  a.adj_net AS a_adj_net,
  b.adj_net AS b_adj_net,
  a.adj_oe - b.adj_oe AS d_adj_oe,
  a.adj_de - b.adj_de AS d_adj_de,
  a.adj_net - b.adj_net AS d_adj_net,
  a.tempo - b.tempo AS d_tempo,
  a.efg_pct - b.efg_pct AS d_efg_pct,
  a.tov_pct - b.tov_pct AS d_tov_pct,
  a.orb_pct - b.orb_pct AS d_orb_pct,
  a.ftr - b.ftr AS d_ftr,
  a.opp_efg_pct - b.opp_efg_pct AS d_opp_efg_pct,
  a.opp_tov_pct - b.opp_tov_pct AS d_opp_tov_pct,
  a.drb_pct - b.drb_pct AS d_drb_pct,
  a.opp_ftr - b.opp_ftr AS d_opp_ftr,
  a.three_par - b.three_par AS d_three_par,
  a.sos_adj_net - b.sos_adj_net AS d_sos_adj_net,
  a.last10_net - b.last10_net AS d_last10_net,
  a.program_win_pct_5y - b.program_win_pct_5y AS d_program_win_pct_5y,
  a.win_pct - b.win_pct AS d_win_pct
FROM {{ ref('f_team_game_efficiency') }} AS e
INNER JOIN {{ ref('f_team_season') }} AS a
  ON a.season = e.season
  AND a.team_id = e.team_id
  AND a.scope = 'pre_ncaa'
INNER JOIN {{ ref('f_team_season') }} AS b
  ON b.season = e.season
  AND b.team_id = e.opp_id
  AND b.scope = 'pre_ncaa'
