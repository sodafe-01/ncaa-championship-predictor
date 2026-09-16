-- Load column/table descriptions so the BigQuery Data Agent has grounded context.
-- Read-only source tables live in da-hackathon-2026.ncaa_basketball; we describe
-- our own artifacts in __PROJECT__.__DATASET__.

ALTER TABLE `__PROJECT__.__DATASET__.feat_team_season`
SET OPTIONS (
  description = "One row per D-I team-season. Modeling spine: regular-season record and win_pct, joined to team/conference dimension. Keys: team_id (STRING), season (INT64)."
);
