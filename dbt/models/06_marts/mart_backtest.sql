-- Grain: backtest season x model family. Owner: DE2 (story DE-11).
-- Core: seasons 2014-2016 (March 2015-2017 tournaments); season 2017 (March 2018) is the extension, no seed baseline.
SELECT
  e.season,
  e.season_label,
  e.is_core_season,
  e.model_name,
  e.is_chosen_model,
  e.games_scored,
  e.logloss AS log_loss,
  e.brier,
  e.accuracy,
  e.seed_baseline_logloss AS seed_baseline_log_loss,
  e.record_baseline_logloss AS record_baseline_log_loss,
  e.beats_seed_baseline AS beat_seed_baseline,
  e.beats_record_baseline AS beat_record_baseline,
  t.display_name AS champion_name,
  e.champion_rank AS champion_odds_rank,
  e.champion_p_champ AS champion_p_champion
FROM {{ ref('eval_backtest') }} AS e
LEFT JOIN {{ ref('stg_teams') }} AS t
  ON t.team_id = e.champion_team_id
