-- Grain: one row per season x conference (2014-2017). Owner: DE2 (story DE-10).
-- Conference = the report card's most common per-game conf_alias (best available, not audited membership).
SELECT
  season,
  ANY_VALUE(season_label) AS season_label,
  conference,
  COUNT(*) AS teams,
  AVG(adj_margin) AS avg_adj_margin,
  RANK() OVER (PARTITION BY season ORDER BY AVG(adj_margin) DESC) AS conference_rank,
  ARRAY_AGG(team_name ORDER BY adj_margin DESC LIMIT 1)[OFFSET(0)] AS best_team_name,
  MAX(adj_margin) AS best_team_adj_margin,
  COUNTIF(strength_rank <= 25) AS top25_teams,
  COUNTIF(made_ncaa) AS ncaa_bids,
  SUM(ncaa_wins) AS ncaa_wins,
  COUNTIF(ncaa_last_round IN ('F4', 'FINAL')) AS final_four_teams,
  LOGICAL_OR(is_champion) AS champion_from_conference
FROM {{ ref('mart_team_profile') }}
GROUP BY season, conference
