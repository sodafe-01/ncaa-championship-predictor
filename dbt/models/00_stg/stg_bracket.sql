{{ config(materialized='table') }}

-- Grain: one row per season x bracket slot (67 per season, 2013-2017). Owner: DE1 (story DE-08).
-- Built top-down from the real results: side a of every slot is the listed home team of its game, and
-- the slot feeding a side is the previous-round game won by that side's team.
WITH ncaa AS (
  SELECT
    season,
    season_label,
    game_id,
    ncaa_round,
    ncaa_round_order,
    ncaa_region,
    home_team_id,
    away_team_id,
    winner_team_id
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
),

final_slot AS (
  SELECT
    n.*,
    'FINAL' AS slot_id,
    CAST(NULL AS INT64) AS slot_num,
    CAST(NULL AS STRING) AS region,
    CAST(NULL AS STRING) AS next_slot_id,
    CAST(NULL AS STRING) AS next_slot_side
  FROM ncaa AS n
  WHERE n.ncaa_round = 'FINAL'
),

f4_slots AS (
  SELECT
    n.*,
    IF(n.winner_team_id = p.home_team_id, 'F4_1', 'F4_2') AS slot_id,
    IF(n.winner_team_id = p.home_team_id, 1, 2) AS slot_num,
    CAST(NULL AS STRING) AS region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN final_slot AS p
    ON p.season = n.season
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'F4'
),

e8_slots AS (
  SELECT
    n.*,
    CONCAT(n.ncaa_region, '_E8') AS slot_id,
    CAST(NULL AS INT64) AS slot_num,
    n.ncaa_region AS region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN f4_slots AS p
    ON p.season = n.season
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'E8'
),

s16_slots AS (
  SELECT
    n.*,
    CONCAT(n.ncaa_region, '_S16_', IF(n.winner_team_id = p.home_team_id, '1', '2')) AS slot_id,
    IF(n.winner_team_id = p.home_team_id, 1, 2) AS slot_num,
    n.ncaa_region AS region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN e8_slots AS p
    ON p.season = n.season
    AND p.region = n.ncaa_region
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'S16'
),

-- {REGION}_S16_n: side a <- R32_(2n-1), side b <- R32_(2n)
r32_slots AS (
  SELECT
    n.*,
    CONCAT(n.ncaa_region, '_R32_', CAST(2 * p.slot_num - IF(n.winner_team_id = p.home_team_id, 1, 0) AS STRING)) AS slot_id,
    2 * p.slot_num - IF(n.winner_team_id = p.home_team_id, 1, 0) AS slot_num,
    n.ncaa_region AS region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN s16_slots AS p
    ON p.season = n.season
    AND p.region = n.ncaa_region
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'R32'
),

-- {REGION}_R32_n: side a <- R64_(2n-1), side b <- R64_(2n)
r64_slots AS (
  SELECT
    n.*,
    CONCAT(n.ncaa_region, '_R64_', CAST(2 * p.slot_num - IF(n.winner_team_id = p.home_team_id, 1, 0) AS STRING)) AS slot_id,
    2 * p.slot_num - IF(n.winner_team_id = p.home_team_id, 1, 0) AS slot_num,
    n.ncaa_region AS region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN r32_slots AS p
    ON p.season = n.season
    AND p.region = n.ncaa_region
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'R64'
),

-- FF1-FF4 numbered by the R64 slot they feed: region order EAST, WEST, SOUTH, MIDWEST, then slot number
ff_slots AS (
  SELECT
    n.*,
    CONCAT(
      'FF',
      CAST(ROW_NUMBER() OVER (
        PARTITION BY n.season
        ORDER BY
          CASE p.region WHEN 'EAST' THEN 1 WHEN 'WEST' THEN 2 WHEN 'SOUTH' THEN 3 WHEN 'MIDWEST' THEN 4 END,
          p.slot_num
      ) AS STRING)
    ) AS slot_id,
    CAST(NULL AS INT64) AS slot_num,
    p.region,
    p.slot_id AS next_slot_id,
    IF(n.winner_team_id = p.home_team_id, 'a', 'b') AS next_slot_side
  FROM ncaa AS n
  INNER JOIN r64_slots AS p
    ON p.season = n.season
    AND n.winner_team_id IN (p.home_team_id, p.away_team_id)
  WHERE n.ncaa_round = 'FF'
),

slots AS (
  SELECT * FROM final_slot
  UNION ALL SELECT * FROM f4_slots
  UNION ALL SELECT * FROM e8_slots
  UNION ALL SELECT * FROM s16_slots
  UNION ALL SELECT * FROM r32_slots
  UNION ALL SELECT * FROM r64_slots
  UNION ALL SELECT * FROM ff_slots
),

sides AS (
  SELECT
    s.season,
    s.season_label,
    s.slot_id,
    s.ncaa_round,
    s.ncaa_round_order,
    s.region,
    s.next_slot_id,
    s.next_slot_side,
    fa.slot_id AS side_a_from_slot,
    fb.slot_id AS side_b_from_slot,
    IF(fa.slot_id IS NULL, s.home_team_id, NULL) AS side_a_team_id,
    IF(fb.slot_id IS NULL, s.away_team_id, NULL) AS side_b_team_id,
    s.game_id,
    s.home_team_id AS actual_team_a_id,
    s.away_team_id AS actual_team_b_id,
    s.winner_team_id AS actual_winner_team_id
  FROM slots AS s
  LEFT JOIN slots AS fa
    ON fa.season = s.season
    AND fa.next_slot_id = s.slot_id
    AND fa.next_slot_side = 'a'
  LEFT JOIN slots AS fb
    ON fb.season = s.season
    AND fb.next_slot_id = s.slot_id
    AND fb.next_slot_side = 'b'
)

SELECT
  sd.season,
  sd.season_label,
  sd.slot_id,
  sd.ncaa_round,
  sd.ncaa_round_order,
  sd.region,
  sd.next_slot_id,
  sd.next_slot_side,
  sd.side_a_team_id,
  sd.side_a_from_slot,
  sd.side_b_team_id,
  sd.side_b_from_slot,
  ta.seed AS side_a_seed,
  tb.seed AS side_b_seed,
  sd.game_id,
  sd.actual_team_a_id,
  sd.actual_team_b_id,
  sd.actual_winner_team_id
FROM sides AS sd
LEFT JOIN {{ ref('stg_tournament_teams') }} AS ta
  ON ta.season = sd.season
  AND ta.team_id = sd.side_a_team_id
LEFT JOIN {{ ref('stg_tournament_teams') }} AS tb
  ON tb.season = sd.season
  AND tb.team_id = sd.side_b_team_id
