{{ config(materialized='table') }}

-- Grain: one row per team in the projected 2018-19 NCAA field (68). Owner: ML2 (task T10).
-- 32 automatic bids (best projected team per 2017-18 conference) + 36 at-large by projected rating.
-- First Four: the 4 lowest-rated automatic bids and the 4 lowest-rated at-large teams, paired by rating.
-- The 64 bracket entries (60 teams + 4 First Four pairs, a pair rated by its average) are seeded 1-16 by
-- rating and spread over regions in S-curve order (odd seed lines EAST, WEST, SOUTH, MIDWEST; even lines reversed).
WITH teams AS (
  SELECT
    team_id,
    market,
    conf_alias,
    projected_adj_net
  FROM {{ ref('f_team_projection') }}
),

auto_bids AS (
  SELECT team_id
  FROM teams
  QUALIFY ROW_NUMBER() OVER (PARTITION BY conf_alias ORDER BY projected_adj_net DESC, team_id) = 1
),

bids AS (
  SELECT
    t.*,
    IF(a.team_id IS NOT NULL, 'auto', 'at_large') AS bid_type
  FROM teams AS t
  LEFT JOIN auto_bids AS a
    ON a.team_id = t.team_id
  QUALIFY a.team_id IS NOT NULL
    OR ROW_NUMBER() OVER (PARTITION BY a.team_id IS NULL ORDER BY t.projected_adj_net DESC, t.team_id) <= 36
),

-- the bottom four of each bid type, paired 1-2 and 3-4 from the highest-rated of the four
first_four AS (
  SELECT
    team_id,
    bid_type,
    CAST(CEIL(ROW_NUMBER() OVER (PARTITION BY bid_type ORDER BY projected_adj_net DESC, team_id) / 2) AS INT64)
      AS pair_in_type
  FROM (
    SELECT
      team_id,
      bid_type,
      projected_adj_net
    FROM bids
    QUALIFY ROW_NUMBER() OVER (PARTITION BY bid_type ORDER BY projected_adj_net, team_id) <= 4
  )
),

entries AS (
  -- one bracket entry per directly placed team or First Four pair
  SELECT
    COALESCE(
      CONCAT('ff_', ff.bid_type, '_', CAST(ff.pair_in_type AS STRING)),
      b.team_id
    ) AS entry_id,
    AVG(b.projected_adj_net) AS entry_rating
  FROM bids AS b
  LEFT JOIN first_four AS ff
    ON ff.team_id = b.team_id
  GROUP BY entry_id
),

seeded AS (
  SELECT
    entry_id,
    entry_rating,
    CAST(CEIL(ROW_NUMBER() OVER (ORDER BY entry_rating DESC, entry_id) / 4) AS INT64) AS seed
  FROM entries
),

regioned AS (
  SELECT
    entry_id,
    seed,
    CASE
      WHEN MOD(seed, 2) = 1
        THEN ['EAST', 'WEST', 'SOUTH', 'MIDWEST'][OFFSET(line_pos - 1)]
      ELSE ['MIDWEST', 'SOUTH', 'WEST', 'EAST'][OFFSET(line_pos - 1)]
    END AS region
  FROM (
    SELECT
      entry_id,
      seed,
      ROW_NUMBER() OVER (PARTITION BY seed ORDER BY entry_rating DESC, entry_id) AS line_pos
    FROM seeded
  )
)

SELECT
  {{ var('forecast_season') }} AS season,
  'proj_{{ var('forecast_season') }}' AS scenario,
  b.team_id,
  b.market,
  b.conf_alias,
  b.projected_adj_net,
  b.bid_type,
  RANK() OVER (ORDER BY b.projected_adj_net DESC) AS field_rank,
  ff.team_id IS NOT NULL AS is_first_four,
  IF(ff.team_id IS NOT NULL, CONCAT('ff_', ff.bid_type, '_', CAST(ff.pair_in_type AS STRING)), NULL) AS first_four_pair,
  r.seed,
  r.region
FROM bids AS b
LEFT JOIN first_four AS ff
  ON ff.team_id = b.team_id
INNER JOIN regioned AS r
  ON r.entry_id = COALESCE(CONCAT('ff_', ff.bid_type, '_', CAST(ff.pair_in_type AS STRING)), b.team_id)
