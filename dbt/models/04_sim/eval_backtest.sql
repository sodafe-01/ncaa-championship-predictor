{{ config(materialized='table') }}

-- Grain: backtest season x model family. Owner: ML2 (task T9).
-- Core tournaments: seasons 2014-2016 (March 2015-2017); 2017 (March 2018) is the extension, with no seed baseline.
-- Metrics use both orderings of each tournament game (as ML.EVALUATE does). Baselines use only pre-tournament data:
--   better seed: the historical better-seed win rate in tournaments before that season (stg_tournament_results);
--   better record: how often the better pre-tournament record won in that season's walk-forward training rows.
WITH predictions AS (
  SELECT
    season,
    model_name,
    game_id,
    team_a_id,
    team_b_id,
    label_a_wins,
    p_a_wins,
    is_chosen_model
  FROM {{ ref('m_game_win') }}
),

model_metrics AS (
  SELECT
    season,
    model_name,
    LOGICAL_OR(is_chosen_model) AS is_chosen_model,
    COUNT(DISTINCT game_id) AS games_scored,
    AVG(-(label_a_wins * LN(GREATEST(p_a_wins, 1e-15)) + (1 - label_a_wins) * LN(GREATEST(1 - p_a_wins, 1e-15))))
      AS logloss,
    AVG(POW(p_a_wins - label_a_wins, 2)) AS brier,
    AVG(IF((p_a_wins > 0.5) = (label_a_wins = 1), 1, 0)) AS accuracy
  FROM predictions
  GROUP BY season, model_name
),

tournament_rows AS (
  SELECT
    m.season,
    m.game_id,
    m.team_a_id,
    m.team_b_id,
    m.label_a_wins,
    m.d_win_pct,
    sa.seed AS seed_a,
    sb.seed AS seed_b
  FROM {{ ref('f_matchups') }} AS m
  LEFT JOIN {{ ref('stg_tournament_teams') }} AS sa
    ON sa.season = m.season
    AND sa.team_id = m.team_a_id
  LEFT JOIN {{ ref('stg_tournament_teams') }} AS sb
    ON sb.season = m.season
    AND sb.team_id = m.team_b_id
  WHERE m.is_tournament_row
),

backtest_seasons AS (
  SELECT DISTINCT season
  FROM predictions
),

seed_rates AS (
  SELECT
    s.season,
    AVG(IF(h.win_seed < h.lose_seed, 1, 0)) AS better_seed_win_rate
  FROM backtest_seasons AS s
  INNER JOIN {{ ref('stg_tournament_results') }} AS h
    ON h.season < s.season
    AND h.win_seed != h.lose_seed
  GROUP BY s.season
),

record_rates AS (
  SELECT
    s.season,
    AVG(IF(m.d_win_pct > 0, m.label_a_wins, NULL)) AS better_record_win_rate
  FROM backtest_seasons AS s
  INNER JOIN {{ ref('f_matchups') }} AS m
    ON m.season < s.season
    OR (m.season = s.season AND m.is_training_row)
  GROUP BY s.season
),

baseline_probs AS (
  SELECT
    t.season,
    t.label_a_wins,
    CASE
      WHEN t.seed_a IS NULL OR t.seed_b IS NULL THEN NULL
      WHEN t.seed_a < t.seed_b THEN sr.better_seed_win_rate
      WHEN t.seed_a > t.seed_b THEN 1 - sr.better_seed_win_rate
      ELSE 0.5
    END AS p_seed,
    CASE
      WHEN t.d_win_pct > 0 THEN rr.better_record_win_rate
      WHEN t.d_win_pct < 0 THEN 1 - rr.better_record_win_rate
      ELSE 0.5
    END AS p_record
  FROM tournament_rows AS t
  INNER JOIN backtest_seasons AS bs
    ON bs.season = t.season
  LEFT JOIN seed_rates AS sr
    ON sr.season = t.season
  LEFT JOIN record_rates AS rr
    ON rr.season = t.season
),

baselines AS (
  SELECT
    season,
    IF(
      COUNTIF(p_seed IS NULL) > 0,
      NULL,
      AVG(-(label_a_wins * LN(GREATEST(p_seed, 1e-15)) + (1 - label_a_wins) * LN(GREATEST(1 - p_seed, 1e-15))))
    ) AS seed_baseline_logloss,
    AVG(-(label_a_wins * LN(GREATEST(p_record, 1e-15)) + (1 - label_a_wins) * LN(GREATEST(1 - p_record, 1e-15))))
      AS record_baseline_logloss
  FROM baseline_probs
  GROUP BY season
),

champions AS (
  SELECT
    g.season,
    g.winner_team_id AS champion_team_id,
    r.p_champ AS champion_p_champ,
    r.odds_rank AS champion_rank
  FROM {{ ref('stg_games') }} AS g
  LEFT JOIN (
    SELECT
      season,
      team_id,
      p_champ,
      RANK() OVER (PARTITION BY scenario ORDER BY p_champ DESC) AS odds_rank
    FROM {{ ref('sim_results') }}
    WHERE STARTS_WITH(scenario, 'backtest_')
  ) AS r
    ON r.season = g.season
    AND r.team_id = g.winner_team_id
  WHERE g.ncaa_round = 'FINAL'
)

SELECT
  m.season,
  {{ season_label('m.season') }} AS season_label,
  m.season BETWEEN 2014 AND 2016 AS is_core_season,
  m.model_name,
  m.is_chosen_model,
  m.games_scored,
  m.logloss,
  m.brier,
  m.accuracy,
  b.seed_baseline_logloss,
  b.record_baseline_logloss,
  m.logloss < b.seed_baseline_logloss AS beats_seed_baseline,
  m.logloss < b.record_baseline_logloss AS beats_record_baseline,
  c.champion_team_id,
  IF(m.is_chosen_model, c.champion_rank, NULL) AS champion_rank,
  IF(m.is_chosen_model, c.champion_p_champ, NULL) AS champion_p_champ
FROM model_metrics AS m
LEFT JOIN baselines AS b
  ON b.season = m.season
LEFT JOIN champions AS c
  ON c.season = m.season
