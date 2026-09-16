-- Out-of-sample backtest with a proper temporal split:
-- train on tournaments before 2010, evaluate on 2010+ (no leakage),
-- and compare the model to a "higher seed wins" baseline.
CREATE OR REPLACE MODEL `__PROJECT__.__DATASET__.matchup_model_backtest`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label'],
  auto_class_weights = TRUE
) AS
SELECT seed_diff, win_pct_diff, label
FROM `__PROJECT__.__DATASET__.matchup_training`
WHERE season < 2010 AND seed_diff IS NOT NULL AND win_pct_diff IS NOT NULL;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.backtest_results` AS
WITH test AS (
  SELECT season, seed_diff, win_pct_diff, label
  FROM `__PROJECT__.__DATASET__.matchup_training`
  WHERE season >= 2010 AND seed_diff IS NOT NULL AND win_pct_diff IS NOT NULL
),
pred AS (
  SELECT
    label,
    seed_diff,
    (SELECT prob FROM UNNEST(predicted_label_probs) WHERE label = 1) AS p_model
  FROM ML.PREDICT(
    MODEL `__PROJECT__.__DATASET__.matchup_model_backtest`,
    (SELECT season, seed_diff, win_pct_diff, label FROM test)
  )
)
SELECT
  COUNT(*) AS n_test_matchups,
  ROUND(AVG(IF((p_model >= 0.5) = (label = 1), 1, 0)), 4) AS model_accuracy,
  ROUND(AVG(IF((seed_diff > 0) = (label = 1), 1, 0)), 4) AS seed_baseline_accuracy
FROM pred;
