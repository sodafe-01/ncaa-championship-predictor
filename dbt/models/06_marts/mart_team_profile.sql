-- Grain: one row per season x D1 team (351 per season, 2014-2017). Owner: DE2 (story DE-10).
-- Ratings and style come from the pre_ncaa report card; the season record from full; NCAA results from stg_games.
WITH pre AS (
  SELECT
    season,
    season_label,
    team_id,
    market,
    alias,
    conf_alias,
    wins,
    losses,
    adj_oe,
    adj_de,
    adj_net,
    rank_adj_net,
    tempo,
    efg_pct,
    tov_pct,
    orb_pct,
    ftr,
    opp_efg_pct,
    three_par,
    three_pct,
    sos_adj_net,
    conference_strength,
    last10_net,
    ap_rank_last,
    ret_min_share,
    ret_basis,
    experience_index,
    program_win_pct_5y,
    pctl_adj_oe,
    pctl_adj_de,
    pctl_adj_net,
    pctl_tempo,
    pctl_efg_pct,
    pctl_tov_pct,
    pctl_orb_pct,
    pctl_three_par
  FROM {{ ref('f_team_season') }}
  WHERE scope = 'pre_ncaa'
),

full_season AS (
  SELECT
    season,
    team_id,
    wins,
    losses,
    win_pct
  FROM {{ ref('f_team_season') }}
  WHERE scope = 'full'
),

ncaa_team_games AS (
  SELECT
    g.season,
    team_id,
    g.ncaa_round,
    g.ncaa_round_order,
    g.winner_team_id = team_id AS won
  FROM {{ ref('stg_games') }} AS g,
    UNNEST([g.home_team_id, g.away_team_id]) AS team_id
  WHERE g.postseason_kind = 'NCAA'
),

ncaa AS (
  SELECT
    season,
    team_id,
    COUNTIF(won AND ncaa_round != 'FF') AS ncaa_wins,
    ARRAY_AGG(ncaa_round ORDER BY ncaa_round_order DESC LIMIT 1)[OFFSET(0)] AS ncaa_last_round,
    LOGICAL_OR(won AND ncaa_round = 'FINAL') AS is_champion
  FROM ncaa_team_games
  GROUP BY season, team_id
)

SELECT
  p.season,
  p.season_label,
  p.team_id,
  t.display_name AS team_name,
  p.market AS school,
  p.alias,
  p.conf_alias AS conference,
  t.color_hex,
  t.logo_medium AS logo_url,
  f.wins,
  f.losses,
  f.win_pct,
  p.wins AS pre_tourney_wins,
  p.losses AS pre_tourney_losses,
  p.adj_oe AS adj_offense,
  p.adj_de AS adj_defense,
  p.adj_net AS adj_margin,
  p.rank_adj_net AS strength_rank,
  p.tempo,
  p.efg_pct,
  p.tov_pct AS turnover_pct,
  p.orb_pct AS off_rebound_pct,
  p.ftr AS ft_rate,
  p.opp_efg_pct,
  p.three_par AS three_point_rate,
  p.three_pct AS three_point_pct,
  p.sos_adj_net AS schedule_strength,
  p.conference_strength,
  p.last10_net AS last10_margin,
  p.ap_rank_last AS ap_rank_before_tourney,
  p.ret_min_share AS returning_minutes_share,
  p.ret_basis AS returning_basis,
  p.experience_index,
  p.program_win_pct_5y,
  p.pctl_adj_oe AS pctl_offense,
  p.pctl_adj_de AS pctl_defense,
  p.pctl_adj_net AS pctl_margin,
  p.pctl_tempo,
  p.pctl_efg_pct AS pctl_shooting,
  p.pctl_tov_pct AS pctl_ball_security,
  p.pctl_orb_pct AS pctl_off_rebounding,
  p.pctl_three_par AS pctl_three_point_rate,
  n.team_id IS NOT NULL AS made_ncaa,
  tt.seed AS ncaa_seed,
  COALESCE(n.ncaa_wins, 0) AS ncaa_wins,
  n.ncaa_last_round,
  COALESCE(n.is_champion, FALSE) AS is_champion
FROM pre AS p
INNER JOIN full_season AS f
  ON f.season = p.season
  AND f.team_id = p.team_id
LEFT JOIN {{ ref('stg_teams') }} AS t
  ON t.team_id = p.team_id
LEFT JOIN ncaa AS n
  ON n.season = p.season
  AND n.team_id = p.team_id
LEFT JOIN {{ ref('stg_tournament_teams') }} AS tt
  ON tt.season = p.season
  AND tt.team_id = p.team_id
