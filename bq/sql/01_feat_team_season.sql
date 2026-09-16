-- Feature spine: one row per Division-I team-season.
-- Source: da-hackathon-2026.ncaa_basketball (read-only shared dataset).
CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.feat_team_season` AS
SELECT
  s.season,
  s.team_id,
  t.market,
  t.name,
  t.conf_name,
  s.wins,
  s.losses,
  SAFE_DIVIDE(s.wins, NULLIF(s.wins + s.losses, 0)) AS win_pct
FROM `da-hackathon-2026.ncaa_basketball.mbb_historical_teams_seasons` AS s
LEFT JOIN `da-hackathon-2026.ncaa_basketball.mbb_teams` AS t
  ON t.id = s.team_id
WHERE s.division = 1;
