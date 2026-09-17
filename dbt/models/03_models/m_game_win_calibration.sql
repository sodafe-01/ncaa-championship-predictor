{{ config(materialized='table') }}

-- Grain: model family x probability tenth, core tournaments (seasons 2014-2016). Owner: ML1 (task T6).
SELECT
  model_name,
  LEAST(CAST(FLOOR(p_a_wins * 10) AS INT64), 9) AS prob_bucket,
  COUNT(*) AS rows_scored,
  AVG(p_a_wins) AS avg_predicted,
  AVG(label_a_wins) AS actual_win_rate
FROM {{ ref('m_game_win') }}
WHERE season BETWEEN 2014 AND 2016
GROUP BY model_name, prob_bucket
