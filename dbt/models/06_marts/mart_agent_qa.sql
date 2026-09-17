-- Grain: one row per rehearsed agent question (8). Owner: DE2 (story DE-11); questions: agent/examples.md (T16).
-- Answers were verified against the built marts; after a rebuild, rerun each expected_sql and update both files.
SELECT
  question_id,
  question,
  expected_sql,
  expected_answer,
  DATE '2026-09-16' AS verified_on,
  notes
FROM UNNEST([
  STRUCT(
    1 AS question_id,
    """Who are the top 10 favorites to win the 2018-19 championship?""" AS question,
    """SELECT odds_rank, team_name, conference, seed, ROUND(p_champion, 3) AS p_champion, ROUND(p_final_four, 3) AS p_final_four, ROUND(adj_margin, 1) AS projected_margin, ROUND(adj_margin_low, 1) AS low, ROUND(adj_margin_high, 1) AS high FROM `da-hackathon-2026.texas_longhorns.mart_title_odds` WHERE scenario = 'proj_2018' ORDER BY odds_rank LIMIT 10""" AS expected_sql,
    """Villanova is the pick: 38.6% to win the title and 64.3% to reach the Final Four, projected margin +32.8 (band +24.5 to +41.2). Then Duke 14.5%, Michigan State 8.9%, Virginia 7.4%, Kentucky 4.3%, Kansas 3.3%, Tennessee 2.6%, Michigan 2.1%, Purdue 2.1% and North Carolina 1.9%.""" AS expected_answer,
    """A forecast from 10,000 simulations of a projected bracket. Projected ratings use class-based returning shares that miss early NBA departures and transfers; quote the band.""" AS notes
  ),
  (
    2,
    """Which 2018-19 contenders are most dependent on three-point shooting?""",
    """SELECT o.team_name, o.odds_rank, ROUND(p.three_point_rate, 3) AS three_point_rate, ROUND(p.three_point_pct, 3) AS three_point_pct FROM `da-hackathon-2026.texas_longhorns.mart_title_odds` AS o JOIN `da-hackathon-2026.texas_longhorns.mart_team_profile` AS p ON p.team_id = o.team_id AND p.season = 2017 WHERE o.scenario = 'proj_2018' AND o.odds_rank <= 16 ORDER BY p.three_point_rate DESC LIMIT 5""",
    """Among the top 16 contenders, by share of 2017-18 shots taken from three: Villanova 46.6% (making 39.8%), Michigan 43.2% (36.3%), Auburn 43.1% (36.6%), Kansas 41.6% (40.3%) and Purdue 40.2% (42.0%).""",
    """Style numbers are from the 2017-18 pre-tournament profile; the 2018-19 rosters are not in the data."""
  ),
  (
    3,
    """Where did our model rank the eventual champion before each tournament?""",
    """SELECT season_label, champion_name, champion_odds_rank, ROUND(champion_p_champion, 3) AS champion_p_champion FROM `da-hackathon-2026.texas_longhorns.mart_backtest` WHERE is_chosen_model ORDER BY season""",
    """Using only pre-tournament data: Duke (March 2015) ranked 4th at 10.3%, Villanova (2016) 6th at 5.2% and North Carolina (2017) 3rd at 11.7%. In the March 2018 extension, Villanova ranked 2nd at 20.8%.""",
    """March 2015-2017 are the core backtests; March 2018 is an extension with no seeds."""
  ),
  (
    4,
    """Did the model beat the seed baseline in the core backtests?""",
    """SELECT season_label, ROUND(log_loss, 3) AS log_loss, ROUND(seed_baseline_log_loss, 3) AS seed_baseline_log_loss, ROUND(record_baseline_log_loss, 3) AS record_baseline_log_loss, beat_seed_baseline, beat_record_baseline FROM `da-hackathon-2026.texas_longhorns.mart_backtest` WHERE is_chosen_model AND is_core_season ORDER BY season""",
    """Yes, in all three core tournaments (lower log loss is better): 0.504 vs 0.532 (2014-15), 0.553 vs 0.637 (2015-16) and 0.514 vs 0.554 (2016-17). It also beat the better-record baseline (0.759, 0.612, 0.738).""",
    """Walk-forward: each season's model was trained only on games before that tournament."""
  ),
  (
    5,
    """Which conferences were strongest in 2017-18?""",
    """SELECT conference_rank, conference, ROUND(avg_adj_margin, 1) AS avg_adj_margin, best_team_name, ncaa_bids FROM `da-hackathon-2026.texas_longhorns.mart_conference_season` WHERE season = 2017 ORDER BY conference_rank LIMIT 5""",
    """By average adjusted margin: Big 12 +17.0 (best team Kansas, 7 bids), Big East +15.8 (Villanova, 6), ACC +15.7 (Virginia, 9), Big Ten +14.7 (Purdue, 4) and SEC +14.4 (Tennessee, 8).""",
    """Conference membership is the best available source record, not audited historical membership."""
  ),
  (
    6,
    """What are the strengths and weaknesses of our 2018-19 pick?""",
    """SELECT s.team_name, s.strengths, s.weaknesses, s.style, s.top_drivers FROM `da-hackathon-2026.texas_longhorns.mart_team_scouting` AS s JOIN `da-hackathon-2026.texas_longhorns.mart_title_odds` AS o ON o.scenario = s.scenario AND o.team_id = s.team_id WHERE s.scenario = 'proj_2018' AND o.odds_rank = 1""",
    """Villanova's 2017-18 profile: strengths are an elite offense (126.1 adjusted, 1.00 percentile), shooting (0.597 effective field-goal percentage, 1.00 percentile) and a +33.2 adjusted margin (rank 1). Weaknesses are getting to the free-throw line (0.14 percentile) and average offensive rebounding (0.59 percentile). The model's top drivers against the field are adjusted offense (+14.8), adjusted margin (+18.4) and schedule strength (+5.27).""",
    """The scouting text is generated by Gemini from the team's numbers only, without its name; it describes the 2017-18 profile."""
  ),
  (
    7,
    """How have pace and three-point shooting changed since 2014-15?""",
    """SELECT season_label, ROUND(avg_tempo, 1) AS avg_tempo, ROUND(avg_three_point_rate, 3) AS avg_three_point_rate, ROUND(avg_efg_pct, 3) AS avg_efg_pct FROM `da-hackathon-2026.texas_longhorns.mart_league_season` ORDER BY season""",
    """Average pace rose from 66.5 possessions per game in 2014-15 to 70.6 in 2015-16 and has held near 71 since. Three-point attempt share climbed every season, from 34.3% to 37.4%, and effective field-goal percentage from 0.490 to 0.509.""",
    """League averages of the 351 Division I teams' pre-tournament numbers."""
  ),
  (
    8,
    """How often did the worse seed win NCAA tournament games?""",
    """SELECT season_label, ROUND(ncaa_upset_rate, 3) AS ncaa_upset_rate FROM `da-hackathon-2026.texas_longhorns.mart_league_season` ORDER BY season""",
    """From the round of 64 on: 19.0% of games in 2014-15, 31.7% in 2015-16 and 22.2% in 2016-17. There is no rate for 2017-18 because the data has no 2018 seeds.""",
    """Seeds come from the historical tournament table, which ends with March 2017."""
  )
])
