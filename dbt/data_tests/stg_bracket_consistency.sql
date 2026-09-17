-- One row per violation of the bracket's structure
WITH b AS (SELECT * FROM {{ ref('stg_bracket') }}),
side_feed AS (
  SELECT p.season, p.slot_id, p.actual_team_a_id AS actual_team, f.actual_winner_team_id AS feeder_winner
  FROM b p JOIN b f ON f.season = p.season AND f.slot_id = p.side_a_from_slot
  UNION ALL
  SELECT p.season, p.slot_id, p.actual_team_b_id, f.actual_winner_team_id
  FROM b p JOIN b f ON f.season = p.season AND f.slot_id = p.side_b_from_slot
),
direct_teams AS (
  SELECT b.season, team_id
  FROM b, UNNEST([b.side_a_team_id, b.side_b_team_id]) AS team_id
  WHERE team_id IS NOT NULL
)
SELECT 'side team is not the winner of its feeder slot' AS failed_check, season, slot_id AS detail
FROM side_feed WHERE actual_team IS DISTINCT FROM feeder_winner
UNION ALL
SELECT 'not 68 directly placed teams', season, CAST(COUNT(DISTINCT team_id) AS STRING)
FROM direct_teams GROUP BY season HAVING COUNT(DISTINCT team_id) != 68
UNION ALL
SELECT 'not 4 First Four winners feeding the round of 64', season,
  CAST(COUNTIF(side_a_from_slot LIKE 'FF%') + COUNTIF(side_b_from_slot LIKE 'FF%') AS STRING)
FROM b WHERE ncaa_round = 'R64' GROUP BY season
HAVING COUNTIF(side_a_from_slot LIKE 'FF%') + COUNTIF(side_b_from_slot LIKE 'FF%') != 4
UNION ALL
SELECT 'bracket champion differs from the real final', b.season, b.actual_winner_team_id
FROM b JOIN {{ ref('stg_games') }} g ON g.season = b.season AND g.ncaa_round = 'FINAL'
WHERE b.slot_id = 'FINAL' AND b.actual_winner_team_id IS DISTINCT FROM g.winner_team_id
