{{ config(materialized='table') }}

-- Grain: backtest season x model family x NCAA tournament row. Owner: ML1 (task T6).
-- Chosen family: the full-feature family (logistic_reg or boosted_tree) with the lower average log loss
-- over the core tournaments (seasons 2014-2016).
WITH predictions AS (
  SELECT season, model_name, game_id, team_a_id, team_b_id, label_a_wins, p_a_wins FROM {{ ref('m_game_win_lr') }}
  UNION ALL
  SELECT season, model_name, game_id, team_a_id, team_b_id, label_a_wins, p_a_wins FROM {{ ref('m_game_win_bt') }}
  UNION ALL
  SELECT season, model_name, game_id, team_a_id, team_b_id, label_a_wins, p_a_wins FROM {{ ref('m_game_win_rt') }}
),

core_log_loss AS (
  SELECT
    model_name,
    AVG(
      -(label_a_wins * LN(GREATEST(p_a_wins, 1e-15)) + (1 - label_a_wins) * LN(GREATEST(1 - p_a_wins, 1e-15)))
    ) AS log_loss
  FROM predictions
  WHERE season BETWEEN 2014 AND 2016
    AND model_name IN ('logistic_reg', 'boosted_tree')
  GROUP BY model_name
),

chosen AS (
  SELECT model_name
  FROM core_log_loss
  ORDER BY log_loss, model_name
  LIMIT 1
)

SELECT
  p.season,
  p.model_name,
  p.game_id,
  p.team_a_id,
  p.team_b_id,
  p.label_a_wins,
  p.p_a_wins,
  p.model_name = c.model_name AS is_chosen_model
FROM predictions AS p
CROSS JOIN chosen AS c
