{{ config(materialized='table') }}

-- Grain: scenario x tournament team (68 per scenario). Owner: ML2 (task T8).
-- p_<round> = share of simulated tournaments in which the team plays in that round; p_champ = share it wins the final.
WITH bracket_teams AS (
  SELECT
    CONCAT('backtest_', CAST(b.season AS STRING)) AS scenario,
    b.region,
    side.team_id,
    side.seed
  FROM {{ ref('stg_bracket') }} AS b,
    UNNEST([
      STRUCT(b.side_a_team_id AS team_id, b.side_a_seed AS seed),
      STRUCT(b.side_b_team_id AS team_id, b.side_b_seed AS seed)
    ]) AS side
  WHERE side.team_id IS NOT NULL
  UNION ALL
  SELECT
    CONCAT('proj_', CAST(b.season AS STRING)) AS scenario,
    b.region,
    side.team_id,
    side.seed
  FROM {{ ref('projected_bracket') }} AS b,
    UNNEST([
      STRUCT(b.side_a_team_id AS team_id, b.side_a_seed AS seed),
      STRUCT(b.side_b_team_id AS team_id, b.side_b_seed AS seed)
    ]) AS side
  WHERE side.team_id IS NOT NULL
),

appearances AS (
  SELECT
    g.scenario,
    g.season,
    g.ncaa_round_order,
    team_id,
    COUNT(*) AS runs
  FROM {{ ref('sim_games') }} AS g,
    UNNEST([g.team_a_id, g.team_b_id]) AS team_id
  GROUP BY g.scenario, g.season, g.ncaa_round_order, team_id
),

titles AS (
  SELECT
    scenario,
    winner_team_id AS team_id,
    COUNT(*) AS runs
  FROM {{ ref('sim_games') }}
  WHERE ncaa_round_order = 6
  GROUP BY scenario, winner_team_id
)

SELECT
  a.scenario,
  ANY_VALUE(a.season) AS season,
  a.team_id,
  ANY_VALUE(bt.region) AS region,
  ANY_VALUE(bt.seed) AS seed,
  SUM(IF(a.ncaa_round_order = 1, a.runs, 0)) / {{ var('n_sims') }} AS p_r64,
  SUM(IF(a.ncaa_round_order = 2, a.runs, 0)) / {{ var('n_sims') }} AS p_r32,
  SUM(IF(a.ncaa_round_order = 3, a.runs, 0)) / {{ var('n_sims') }} AS p_s16,
  SUM(IF(a.ncaa_round_order = 4, a.runs, 0)) / {{ var('n_sims') }} AS p_e8,
  SUM(IF(a.ncaa_round_order = 5, a.runs, 0)) / {{ var('n_sims') }} AS p_f4,
  SUM(IF(a.ncaa_round_order = 6, a.runs, 0)) / {{ var('n_sims') }} AS p_final,
  COALESCE(ANY_VALUE(t.runs), 0) / {{ var('n_sims') }} AS p_champ,
  {{ var('n_sims') }} AS n_sims
FROM appearances AS a
LEFT JOIN bracket_teams AS bt
  ON bt.scenario = a.scenario
  AND bt.team_id = a.team_id
LEFT JOIN titles AS t
  ON t.scenario = a.scenario
  AND t.team_id = a.team_id
GROUP BY a.scenario, a.team_id
