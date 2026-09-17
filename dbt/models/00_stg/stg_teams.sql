-- Grain: one row per Division I team (351). Owner: DE1 (story DE-01).
-- Conference fields are the current master values, not historical membership.
SELECT
  t.id AS team_id,
  t.market,
  t.name,
  t.alias,
  CONCAT(t.market, ' ', t.name) AS display_name,
  t.school_ncaa,
  t.conf_alias,
  t.conf_name,
  t.code_ncaa,
  t.kaggle_team_id,
  t.venue_id,
  t.venue_name,
  t.venue_city,
  t.venue_state,
  t.venue_capacity,
  c.color AS color_hex,
  m.mascot,
  t.logo_small,
  t.logo_medium,
  t.logo_large
FROM {{ source('ncaa_basketball', 'mbb_teams') }} AS t
LEFT JOIN {{ source('ncaa_basketball', 'team_colors') }} AS c ON c.id = t.id
LEFT JOIN {{ source('ncaa_basketball', 'mascots') }} AS m ON m.id = t.id
