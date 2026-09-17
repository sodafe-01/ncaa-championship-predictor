-- Grain: one row per season (2014-2017). Owner: DE2 (story DE-10).
-- Style averages and parity from pre-tournament team profiles; home court from regular-season D1 games.
WITH profiles AS (
  SELECT
    season,
    season_label,
    team_name,
    tempo,
    efg_pct,
    three_point_rate,
    three_point_pct,
    ft_rate,
    turnover_pct,
    adj_margin,
    strength_rank,
    is_champion,
    PERCENTILE_CONT(adj_margin, 0.5) OVER (PARTITION BY season) AS median_adj_margin
  FROM {{ ref('mart_team_profile') }}
),

teams AS (
  SELECT
    season,
    ANY_VALUE(season_label) AS season_label,
    COUNT(*) AS teams,
    AVG(tempo) AS avg_tempo,
    AVG(efg_pct) AS avg_efg_pct,
    AVG(three_point_rate) AS avg_three_point_rate,
    AVG(three_point_pct) AS avg_three_point_pct,
    AVG(ft_rate) AS avg_ft_rate,
    AVG(turnover_pct) AS avg_turnover_pct,
    STDDEV(adj_margin) AS parity_sd_adj_margin,
    AVG(IF(strength_rank <= 10, adj_margin, NULL)) AS top10_avg_adj_margin,
    ANY_VALUE(median_adj_margin) AS median_adj_margin,
    MAX(IF(is_champion, team_name, NULL)) AS champion_name,
    MAX(IF(is_champion, strength_rank, NULL)) AS champion_pre_tourney_rank
  FROM profiles
  GROUP BY season
),

-- Closed, decided, non-neutral regular-season D1-vs-D1 games (best-effort is_neutral from DE-01)
home_court AS (
  SELECT
    season,
    AVG(IF(winner_team_id = home_team_id, 1, 0)) AS home_win_pct,
    AVG(home_points - away_points) AS home_margin
  FROM {{ ref('stg_games') }}
  WHERE is_closed
    AND winner_team_id IS NOT NULL
    AND NOT is_neutral
    AND postseason_kind = 'REG'
    AND is_d1_matchup
  GROUP BY season
),

-- NCAA games with seeds attached by (season, team_id); no seeds for 2017-18
ncaa_games AS (
  SELECT
    g.season,
    g.ncaa_round_order,
    ABS(g.home_points - g.away_points) AS margin,
    ws.seed AS winner_seed,
    ls.seed AS loser_seed
  FROM {{ ref('stg_games') }} AS g
  LEFT JOIN {{ ref('stg_tournament_teams') }} AS ws
    ON ws.season = g.season
    AND ws.team_id = g.winner_team_id
  LEFT JOIN {{ ref('stg_tournament_teams') }} AS ls
    ON ls.season = g.season
    AND ls.team_id = IF(g.winner_team_id = g.home_team_id, g.away_team_id, g.home_team_id)
  WHERE g.postseason_kind = 'NCAA'
),

tournament AS (
  SELECT
    season,
    SAFE_DIVIDE(
      COUNTIF(ncaa_round_order >= 1 AND winner_seed > loser_seed),
      COUNTIF(ncaa_round_order >= 1 AND winner_seed IS NOT NULL AND loser_seed IS NOT NULL)
    ) AS ncaa_upset_rate,
    AVG(margin) AS ncaa_avg_margin
  FROM ncaa_games
  GROUP BY season
)

SELECT
  t.season,
  t.season_label,
  t.teams,
  t.avg_tempo,
  t.avg_efg_pct,
  t.avg_three_point_rate,
  t.avg_three_point_pct,
  t.avg_ft_rate,
  t.avg_turnover_pct,
  h.home_win_pct,
  h.home_margin,
  t.parity_sd_adj_margin,
  t.top10_avg_adj_margin - t.median_adj_margin AS top10_gap,
  n.ncaa_upset_rate,
  n.ncaa_avg_margin,
  t.champion_name,
  t.champion_pre_tourney_rank
FROM teams AS t
LEFT JOIN home_court AS h
  ON h.season = t.season
LEFT JOIN tournament AS n
  ON n.season = t.season
