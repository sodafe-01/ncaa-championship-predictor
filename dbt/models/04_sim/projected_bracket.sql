{{ config(materialized='table') }}

-- Grain: one row per slot (67) of the projected 2018-19 bracket, in stg_bracket's exact shape. Owner: ML2 (task T10).
-- Round-of-64 pairings follow the standard seed order (1-16, 8-9, 5-12, 4-13, 6-11, 3-14, 7-10, 2-15);
-- side a is the better seed. Final Four: EAST vs MIDWEST (F4_1), WEST vs SOUTH (F4_2), matching the S-curve
-- (overall 1 seed in EAST, 2 in WEST, 3 in SOUTH, 4 in MIDWEST). No games are played, so actual_* are NULL.
WITH field AS (
  SELECT
    team_id,
    projected_adj_net,
    first_four_pair,
    seed,
    region
  FROM {{ ref('projected_field') }}
),

entries AS (
  SELECT
    region,
    seed,
    IF(COUNT(*) = 1, ANY_VALUE(team_id), NULL) AS team_id,
    ANY_VALUE(first_four_pair) AS first_four_pair
  FROM field
  GROUP BY region, seed
),

r64_template AS (
  SELECT
    region,
    region_order,
    pair_offset + 1 AS slot_num,
    pair.seed_a,
    pair.seed_b
  FROM UNNEST(['EAST', 'WEST', 'SOUTH', 'MIDWEST']) AS region WITH OFFSET AS region_order
  CROSS JOIN UNNEST([
    STRUCT(1 AS seed_a, 16 AS seed_b), (8, 9), (5, 12), (4, 13), (6, 11), (3, 14), (7, 10), (2, 15)
  ]) AS pair WITH OFFSET AS pair_offset
),

r64 AS (
  SELECT
    t.region,
    t.region_order,
    t.slot_num,
    CONCAT(t.region, '_R64_', CAST(t.slot_num AS STRING)) AS slot_id,
    t.seed_a,
    t.seed_b,
    ea.team_id AS a_team_id,
    ea.first_four_pair AS a_pair,
    eb.team_id AS b_team_id,
    eb.first_four_pair AS b_pair
  FROM r64_template AS t
  INNER JOIN entries AS ea
    ON ea.region = t.region
    AND ea.seed = t.seed_a
  INNER JOIN entries AS eb
    ON eb.region = t.region
    AND eb.seed = t.seed_b
),

ff_feeds AS (
  SELECT slot_id AS next_slot_id, 'a' AS next_slot_side, a_pair AS first_four_pair, region, region_order, slot_num, seed_a AS seed
  FROM r64
  WHERE a_pair IS NOT NULL
  UNION ALL
  SELECT slot_id, 'b', b_pair, region, region_order, slot_num, seed_b
  FROM r64
  WHERE b_pair IS NOT NULL
),

-- FF1-FF4 numbered by the round-of-64 slot they feed (region order, then slot number)
ff AS (
  SELECT
    CONCAT('FF', CAST(ROW_NUMBER() OVER (ORDER BY region_order, slot_num, next_slot_side) AS STRING)) AS slot_id,
    next_slot_id,
    next_slot_side,
    first_four_pair,
    region,
    seed
  FROM ff_feeds
),

ff_teams AS (
  SELECT
    first_four_pair,
    ARRAY_AGG(team_id ORDER BY projected_adj_net DESC, team_id)[OFFSET(0)] AS team_a_id,
    ARRAY_AGG(team_id ORDER BY projected_adj_net DESC, team_id)[OFFSET(1)] AS team_b_id
  FROM field
  WHERE first_four_pair IS NOT NULL
  GROUP BY first_four_pair
),

regions AS (
  SELECT region
  FROM UNNEST(['EAST', 'WEST', 'SOUTH', 'MIDWEST']) AS region
),

slots AS (
  SELECT
    f.slot_id,
    'FF' AS ncaa_round,
    0 AS ncaa_round_order,
    f.region,
    f.next_slot_id,
    f.next_slot_side,
    t.team_a_id AS side_a_team_id,
    CAST(NULL AS STRING) AS side_a_from_slot,
    t.team_b_id AS side_b_team_id,
    CAST(NULL AS STRING) AS side_b_from_slot,
    f.seed AS side_a_seed,
    f.seed AS side_b_seed
  FROM ff AS f
  INNER JOIN ff_teams AS t
    ON t.first_four_pair = f.first_four_pair

  UNION ALL

  SELECT
    r.slot_id,
    'R64',
    1,
    r.region,
    CONCAT(r.region, '_R32_', CAST(CAST(CEIL(r.slot_num / 2) AS INT64) AS STRING)),
    IF(MOD(r.slot_num, 2) = 1, 'a', 'b'),
    r.a_team_id,
    fa.slot_id,
    r.b_team_id,
    fb.slot_id,
    IF(r.a_team_id IS NOT NULL, r.seed_a, NULL),
    IF(r.b_team_id IS NOT NULL, r.seed_b, NULL)
  FROM r64 AS r
  LEFT JOIN ff AS fa
    ON fa.next_slot_id = r.slot_id
    AND fa.next_slot_side = 'a'
  LEFT JOIN ff AS fb
    ON fb.next_slot_id = r.slot_id
    AND fb.next_slot_side = 'b'

  UNION ALL

  SELECT
    CONCAT(g.region, '_R32_', CAST(n AS STRING)),
    'R32',
    2,
    g.region,
    CONCAT(g.region, '_S16_', CAST(CAST(CEIL(n / 2) AS INT64) AS STRING)),
    IF(MOD(n, 2) = 1, 'a', 'b'),
    NULL,
    CONCAT(g.region, '_R64_', CAST(2 * n - 1 AS STRING)),
    NULL,
    CONCAT(g.region, '_R64_', CAST(2 * n AS STRING)),
    NULL,
    NULL
  FROM regions AS g
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 4)) AS n

  UNION ALL

  SELECT
    CONCAT(g.region, '_S16_', CAST(n AS STRING)),
    'S16',
    3,
    g.region,
    CONCAT(g.region, '_E8'),
    IF(n = 1, 'a', 'b'),
    NULL,
    CONCAT(g.region, '_R32_', CAST(2 * n - 1 AS STRING)),
    NULL,
    CONCAT(g.region, '_R32_', CAST(2 * n AS STRING)),
    NULL,
    NULL
  FROM regions AS g
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 2)) AS n

  UNION ALL

  SELECT
    CONCAT(g.region, '_E8'),
    'E8',
    4,
    g.region,
    IF(g.region IN ('EAST', 'MIDWEST'), 'F4_1', 'F4_2'),
    IF(g.region IN ('EAST', 'WEST'), 'a', 'b'),
    NULL,
    CONCAT(g.region, '_S16_1'),
    NULL,
    CONCAT(g.region, '_S16_2'),
    NULL,
    NULL
  FROM regions AS g

  UNION ALL

  SELECT 'F4_1', 'F4', 5, NULL, 'FINAL', 'a', NULL, 'EAST_E8', NULL, 'MIDWEST_E8', NULL, NULL
  UNION ALL
  SELECT 'F4_2', 'F4', 5, NULL, 'FINAL', 'b', NULL, 'WEST_E8', NULL, 'SOUTH_E8', NULL, NULL
  UNION ALL
  SELECT 'FINAL', 'FINAL', 6, NULL, NULL, NULL, NULL, 'F4_1', NULL, 'F4_2', NULL, NULL
)

SELECT
  {{ var('forecast_season') }} AS season,
  {{ season_label(var('forecast_season')) }} AS season_label,
  slot_id,
  ncaa_round,
  ncaa_round_order,
  region,
  next_slot_id,
  next_slot_side,
  side_a_team_id,
  side_a_from_slot,
  side_b_team_id,
  side_b_from_slot,
  side_a_seed,
  side_b_seed,
  CAST(NULL AS STRING) AS game_id,
  CAST(NULL AS STRING) AS actual_team_a_id,
  CAST(NULL AS STRING) AS actual_team_b_id,
  CAST(NULL AS STRING) AS actual_winner_team_id
FROM slots
