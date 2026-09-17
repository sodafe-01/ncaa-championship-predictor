{{ config(materialized='table') }}

-- Grain: scenario x simulation x bracket slot (67 slots x var('n_sims') runs per scenario). Owner: ML2 (task T8).
-- One set-based model, one CTE per round: each round's sides are the directly placed teams or the previous round's
-- winners in the same run. Randomness is FARM_FINGERPRINT(sim_seed | scenario | sim | slot), so the same seed
-- always reproduces the same odds.
WITH brackets AS (
  SELECT
    CONCAT('backtest_', CAST(b.season AS STRING)) AS scenario,
    b.season,
    b.slot_id,
    b.ncaa_round_order,
    b.side_a_team_id,
    b.side_a_from_slot,
    b.side_b_team_id,
    b.side_b_from_slot
  FROM {{ ref('stg_bracket') }} AS b
  INNER JOIN {{ ref('dq_season_gate') }} AS q
    ON q.season = b.season
    AND q.model_ready
  UNION ALL
  SELECT
    CONCAT('proj_', CAST(season AS STRING)) AS scenario,
    season,
    slot_id,
    ncaa_round_order,
    side_a_team_id,
    side_a_from_slot,
    side_b_team_id,
    side_b_from_slot
  FROM {{ ref('projected_bracket') }}
),

sims AS (
  SELECT sim
  FROM UNNEST(GENERATE_ARRAY(1, {{ var('n_sims') }})) AS sim
),

{% for r in range(0, 7) %}
round_{{ r }} AS (
  SELECT
    x.scenario,
    x.season,
    x.sim,
    x.slot_id,
    x.ncaa_round_order,
    x.team_a_id,
    x.team_b_id,
    IF(
      (ABS(MOD(FARM_FINGERPRINT(CONCAT('{{ var('sim_seed') }}|', x.scenario, '|', CAST(x.sim AS STRING), '|', x.slot_id)), 1000000)) + 0.5)
        / 1000000 < p.p_a_wins,
      x.team_a_id,
      x.team_b_id
    ) AS winner_team_id
  FROM (
    SELECT
      s.scenario,
      s.season,
      sm.sim,
      s.slot_id,
      s.ncaa_round_order,
      {%- if r == 0 %}
      s.side_a_team_id AS team_a_id,
      s.side_b_team_id AS team_b_id
      {%- else %}
      COALESCE(ANY_VALUE(s.side_a_team_id), MAX(IF(prev.slot_id = s.side_a_from_slot, prev.winner_team_id, NULL))) AS team_a_id,
      COALESCE(ANY_VALUE(s.side_b_team_id), MAX(IF(prev.slot_id = s.side_b_from_slot, prev.winner_team_id, NULL))) AS team_b_id
      {%- endif %}
    FROM brackets AS s
    CROSS JOIN sims AS sm
    {%- if r > 0 %}
    LEFT JOIN round_{{ r - 1 }} AS prev
      ON prev.scenario = s.scenario
      AND prev.sim = sm.sim
      AND prev.slot_id IN (s.side_a_from_slot, s.side_b_from_slot)
    {%- endif %}
    WHERE s.ncaa_round_order = {{ r }}
    {%- if r > 0 %}
    GROUP BY s.scenario, s.season, sm.sim, s.slot_id, s.ncaa_round_order
    {%- endif %}
  ) AS x
  INNER JOIN {{ ref('p_matchup') }} AS p
    ON p.scenario = x.scenario
    AND p.team_a_id = x.team_a_id
    AND p.team_b_id = x.team_b_id
),

{% endfor %}
all_rounds AS (
  {%- for r in range(0, 7) %}
  SELECT * FROM round_{{ r }}
  {{ 'UNION ALL' if not loop.last }}
  {%- endfor %}
)

SELECT
  scenario,
  season,
  sim,
  slot_id,
  ncaa_round_order,
  team_a_id,
  team_b_id,
  winner_team_id
FROM all_rounds
