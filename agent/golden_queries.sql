-- Golden / example queries for the NCAA Championship Analyst Data Agent.
-- Register these as example questions -> SQL to improve NL->SQL reliability.
-- Fully-qualified names use the shared source dataset and our texas_longhorns views.

-- 1. Teams with the most NCAA tournament wins, 1985-2017
SELECT win_market, win_name, COUNT(*) AS tourney_wins
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
GROUP BY win_market, win_name
ORDER BY tourney_wins DESC
LIMIT 20;

-- 2. Historical win rate of a #1 seed vs a #16 seed
SELECT
  COUNTIF(SAFE_CAST(REGEXP_EXTRACT(win_seed, r'[0-9]+') AS INT64) = 1) AS one_seed_wins,
  COUNTIF(SAFE_CAST(REGEXP_EXTRACT(win_seed, r'[0-9]+') AS INT64) = 16) AS sixteen_seed_wins
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
WHERE round = 1
  AND {SAFE_CAST(REGEXP_EXTRACT(win_seed, r'[0-9]+') AS INT64),
       SAFE_CAST(REGEXP_EXTRACT(lose_seed, r'[0-9]+') AS INT64)} IS NOT NULL;

-- 3. Championship-game appearances by team and season (final round)
WITH max_round AS (
  SELECT season, MAX(round) AS final_round
  FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
  GROUP BY season
)
SELECT g.season, g.win_market AS champion, g.lose_market AS runner_up, g.win_pts, g.lose_pts
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games` g
JOIN max_round m ON g.season = m.season AND g.round = m.final_round
ORDER BY g.season DESC;

-- 4. Every tournament game for a given team (replace @team)
DECLARE team STRING DEFAULT 'Texas';
SELECT season, round, game_date,
  IF(win_market = team, 'W', 'L') AS result,
  IF(win_market = team, lose_market, win_market) AS opponent,
  win_pts, lose_pts
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
WHERE win_market = team OR lose_market = team
ORDER BY season, round;

-- 5. Which seeds most often reach the Final Four (round 5 = national semifinal)
SELECT SAFE_CAST(REGEXP_EXTRACT(win_seed, r'[0-9]+') AS INT64) AS seed, COUNT(*) AS final_four_wins
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
WHERE round >= 5
GROUP BY seed
ORDER BY final_four_wins DESC;

-- 6. Champion vs runner-up regular-season win% by season
WITH max_round AS (
  SELECT season, MAX(round) AS final_round
  FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games` GROUP BY season
),
finals AS (
  SELECT g.season, g.win_team_id AS champ_id, g.lose_team_id AS runner_id
  FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games` g
  JOIN max_round m ON g.season = m.season AND g.round = m.final_round
)
SELECT f.season,
  c.win_pct AS champion_win_pct,
  r.win_pct AS runner_up_win_pct
FROM finals f
LEFT JOIN `da-hackathon-2026.texas_longhorns.feat_team_season` c
  ON c.team_id = f.champ_id AND c.season = f.season
LEFT JOIN `da-hackathon-2026.texas_longhorns.feat_team_season` r
  ON r.team_id = f.runner_id AND r.season = f.season
ORDER BY f.season DESC;

-- 7. How often the higher seed wins, by round
SELECT round,
  ROUND(AVG(CASE
    WHEN SAFE_CAST(REGEXP_EXTRACT(win_seed, r'[0-9]+') AS INT64)
       < SAFE_CAST(REGEXP_EXTRACT(lose_seed, r'[0-9]+') AS INT64) THEN 1 ELSE 0 END), 3)
    AS higher_seed_win_rate
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_tournament_games`
GROUP BY round ORDER BY round;

-- 8. A team's neutral-site record (replace @team)
DECLARE t STRING DEFAULT 'Texas';
SELECT COUNTIF(win_team = TRUE) -- placeholder; see mbb_teams_games_sr for W/L flag
FROM (SELECT market AS win_team FROM `da-hackathon-2026.ncaa_basketball.mbb_teams_games_sr`
      WHERE neutral_site = TRUE AND market = t);

-- 9. Rank teams by predicted championship probability
SELECT market, name, conf_name, ROUND(champion_probability * 100, 2) AS champ_pct
FROM `da-hackathon-2026.texas_longhorns.v_champion_probabilities`
ORDER BY champ_pct DESC
LIMIT 20;

-- 10. Scouting summary for a team (requires v_team_scouting / Vertex connection)
SELECT market, name, ROUND(champion_probability * 100, 2) AS champ_pct, scouting_summary
FROM `da-hackathon-2026.texas_longhorns.v_team_scouting`
WHERE market = 'Texas';
