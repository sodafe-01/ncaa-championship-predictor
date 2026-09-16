-- Grain: one row per team per season from the historical season records (source rows with a team_id). Owner: DE1 (story DE-03).
-- season is already the start year (same convention as Sportradar); the table ends with 2016-17.
SELECT
  season,
  {{ season_label('season') }} AS season_label,
  team_id,
  market,
  wins,
  losses,
  ties,
  wins / NULLIF(wins + losses, 0) AS win_pct,
  division,
  current_division
FROM {{ source('ncaa_basketball', 'mbb_historical_teams_seasons') }}
WHERE team_id IS NOT NULL
