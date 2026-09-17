-- One row per structural violation of the projected 2018-19 bracket
WITH b AS (SELECT * FROM {{ ref('projected_bracket') }}),
direct_teams AS (
  SELECT team_id
  FROM b, UNNEST([b.side_a_team_id, b.side_b_team_id]) AS team_id
  WHERE team_id IS NOT NULL
),
feeds AS (
  SELECT f.slot_id AS feeder, f.next_slot_id, f.next_slot_side, p.side_a_from_slot, p.side_b_from_slot
  FROM b AS f
  LEFT JOIN b AS p ON p.slot_id = f.next_slot_id
  WHERE f.next_slot_id IS NOT NULL
)
SELECT 'direct teams are not the 68 teams of the projected field' AS failed_check, CAST(COUNT(DISTINCT d.team_id) AS STRING) AS detail
FROM direct_teams AS d
INNER JOIN {{ ref('projected_field') }} AS pf ON pf.team_id = d.team_id
HAVING COUNT(DISTINCT d.team_id) != 68 OR (SELECT COUNT(*) FROM direct_teams) != 68
UNION ALL
SELECT 'slot does not feed the side that points back to it', feeder
FROM feeds
WHERE IF(next_slot_side = 'a', side_a_from_slot, side_b_from_slot) IS DISTINCT FROM feeder
UNION ALL
SELECT 'region does not have one entry per seed line', CONCAT(region, ' ', CAST(COUNT(*) AS STRING))
FROM (
  SELECT region, seed
  FROM {{ ref('projected_field') }}
  GROUP BY region, seed
)
GROUP BY region
HAVING COUNT(*) != 16
