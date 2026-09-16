-- Build a balanced matchup training set from historical tournament games (1985-2017).
-- Each tournament game yields one matchup; we add both orientations (A vs B and B vs A)
-- so the model sees symmetric, unbiased labels.
CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.matchup_training` AS
WITH g AS (
  SELECT
    season,
    win_team_id,
    lose_team_id,
    SAFE_CAST(REGEXP_EXTRACT(win_seed,  r'[0-9]+') AS INT64) AS win_seed,
    SAFE_CAST(REGEXP_EXTRACT(lose_seed, r'[0-9]+') AS INT64) AS lose_seed
  FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
),
feat AS (
  SELECT season, team_id, win_pct FROM `__PROJECT__.__DATASET__.feat_team_season`
)
-- Orientation 1: winner is team A (label = 1)
SELECT
  g.season,
  (g.lose_seed - g.win_seed)              AS seed_diff,     -- positive favors A
  (fa.win_pct - fb.win_pct)               AS win_pct_diff,  -- positive favors A
  1                                       AS label
FROM g
LEFT JOIN feat fa ON fa.team_id = g.win_team_id  AND fa.season = g.season
LEFT JOIN feat fb ON fb.team_id = g.lose_team_id AND fb.season = g.season
UNION ALL
-- Orientation 2: loser is team A (label = 0)
SELECT
  g.season,
  (g.win_seed - g.lose_seed)              AS seed_diff,
  (fb.win_pct - fa.win_pct)               AS win_pct_diff,
  0                                       AS label
FROM g
LEFT JOIN feat fa ON fa.team_id = g.win_team_id  AND fa.season = g.season
LEFT JOIN feat fb ON fb.team_id = g.lose_team_id AND fb.season = g.season;
