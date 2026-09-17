{{ config(materialized='table') }}

-- Grain: scenario x team x bracket slot the team can reach. Owner: ML2 (task T8).
-- A team's position fixes the slot it plays in each round; this shows how often it gets there, how often it wins
-- that game, and its most likely opponent there.
WITH team_slots AS (
  SELECT
    g.scenario,
    g.season,
    g.slot_id,
    g.ncaa_round_order,
    side.team_id,
    side.opponent_id,
    g.winner_team_id = side.team_id AS won
  FROM {{ ref('sim_games') }} AS g,
    UNNEST([
      STRUCT(g.team_a_id AS team_id, g.team_b_id AS opponent_id),
      STRUCT(g.team_b_id AS team_id, g.team_a_id AS opponent_id)
    ]) AS side
),

opponents AS (
  SELECT
    scenario,
    team_id,
    slot_id,
    opponent_id,
    COUNT(*) AS runs
  FROM team_slots
  GROUP BY scenario, team_id, slot_id, opponent_id
)

SELECT
  s.scenario,
  ANY_VALUE(s.season) AS season,
  s.team_id,
  s.slot_id,
  ANY_VALUE(s.ncaa_round_order) AS ncaa_round_order,
  COUNT(*) / {{ var('n_sims') }} AS p_reach,
  COUNTIF(s.won) / {{ var('n_sims') }} AS p_win,
  ANY_VALUE(o.likely_opponent_id) AS likely_opponent_id,
  ANY_VALUE(o.likely_opponent_runs) / {{ var('n_sims') }} AS p_likely_opponent
FROM team_slots AS s
LEFT JOIN (
  SELECT
    scenario,
    team_id,
    slot_id,
    ARRAY_AGG(opponent_id ORDER BY runs DESC, opponent_id LIMIT 1)[OFFSET(0)] AS likely_opponent_id,
    MAX(runs) AS likely_opponent_runs
  FROM opponents
  GROUP BY scenario, team_id, slot_id
) AS o
  ON o.scenario = s.scenario
  AND o.team_id = s.team_id
  AND o.slot_id = s.slot_id
GROUP BY s.scenario, s.team_id, s.slot_id
