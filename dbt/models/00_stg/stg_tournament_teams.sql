-- Grain: one row per team per historical NCAA tournament (64, 65 or 68 teams). Owner: DE1 (story DE-03).
-- Seed and region code are single-valued per (season, team_id) in the source; attach seeds by team, never by region.
WITH team_games AS (
  SELECT season, season_label, tournament_year, ncaa_round, ncaa_round_order,
    win_team_id AS team_id, win_seed AS seed, win_region_code AS region_code, TRUE AS won
  FROM {{ ref('stg_tournament_results') }}
  UNION ALL
  SELECT season, season_label, tournament_year, ncaa_round, ncaa_round_order,
    lose_team_id AS team_id, lose_seed AS seed, lose_region_code AS region_code, FALSE AS won
  FROM {{ ref('stg_tournament_results') }}
)

SELECT
  season,
  ANY_VALUE(season_label) AS season_label,
  ANY_VALUE(tournament_year) AS tournament_year,
  team_id,
  MIN(seed) AS seed,
  MIN(region_code) AS region_code,
  LOGICAL_OR(ncaa_round = 'FF') AS played_play_in,
  COUNTIF(won AND ncaa_round != 'FF') AS tournament_wins,
  ARRAY_AGG(ncaa_round ORDER BY ncaa_round_order DESC LIMIT 1)[OFFSET(0)] AS last_round,
  LOGICAL_OR(won AND ncaa_round = 'FINAL') AS is_champion
FROM team_games
GROUP BY season, team_id
