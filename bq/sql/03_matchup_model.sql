-- BQML matchup classifier: P(team A beats team B) from seed and win% differentials.
CREATE OR REPLACE MODEL `__PROJECT__.__DATASET__.matchup_model`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label'],
  auto_class_weights = TRUE
) AS
SELECT
  seed_diff,
  win_pct_diff,
  label
FROM `__PROJECT__.__DATASET__.matchup_training`
WHERE seed_diff IS NOT NULL AND win_pct_diff IS NOT NULL;
