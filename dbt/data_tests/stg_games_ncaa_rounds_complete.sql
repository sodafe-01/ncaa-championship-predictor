-- Every season has a complete NCAA tournament: FF 4, R64 32, R32 16, S16 8, E8 4, F4 2, FINAL 1
WITH rounds AS (
  SELECT 'FF' AS ncaa_round, 4 AS n UNION ALL SELECT 'R64', 32 UNION ALL SELECT 'R32', 16
  UNION ALL SELECT 'S16', 8 UNION ALL SELECT 'E8', 4 UNION ALL SELECT 'F4', 2 UNION ALL SELECT 'FINAL', 1
),
expected AS (
  SELECT season, ncaa_round, n
  FROM UNNEST(GENERATE_ARRAY(2013, {{ var('last_season') }})) AS season CROSS JOIN rounds
),
actual AS (
  SELECT season, ncaa_round, COUNT(*) AS n
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
  GROUP BY season, ncaa_round
)
SELECT COALESCE(e.season, a.season) AS season, COALESCE(e.ncaa_round, a.ncaa_round) AS ncaa_round,
  e.n AS expected_games, a.n AS actual_games
FROM expected e
FULL OUTER JOIN actual a ON a.season = e.season AND a.ncaa_round = e.ncaa_round
WHERE e.n IS DISTINCT FROM a.n
