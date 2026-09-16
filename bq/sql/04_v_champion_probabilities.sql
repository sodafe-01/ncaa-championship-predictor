-- Championship-probability proxy for the most recent available season.
-- Each team's strength = model P(beat an average team); normalized across the
-- field to a championship probability. Swap in a full bracket Monte-Carlo later.
CREATE OR REPLACE VIEW `__PROJECT__.__DATASET__.v_champion_probabilities` AS
WITH latest AS (
  SELECT MAX(season) AS season FROM `__PROJECT__.__DATASET__.feat_team_season`
),
base AS (
  SELECT
    f.season,
    f.team_id,
    f.market,
    f.name,
    f.conf_name,
    0 AS seed_diff,
    f.win_pct - AVG(f.win_pct) OVER (PARTITION BY f.season) AS win_pct_diff
  FROM `__PROJECT__.__DATASET__.feat_team_season` AS f
  JOIN latest AS l USING (season)
  WHERE f.win_pct IS NOT NULL
),
scored AS (
  SELECT
    season, team_id, market, name, conf_name,
    (SELECT prob FROM UNNEST(predicted_label_probs) WHERE label = 1) AS beat_avg_prob
  FROM ML.PREDICT(
    MODEL `__PROJECT__.__DATASET__.matchup_model`,
    (SELECT season, team_id, market, name, conf_name, seed_diff, win_pct_diff FROM base)
  )
)
SELECT
  season,
  team_id,
  market,
  name,
  conf_name,
  beat_avg_prob,
  SAFE_DIVIDE(beat_avg_prob, SUM(beat_avg_prob) OVER ()) AS champion_probability
FROM scored
ORDER BY champion_probability DESC;
