{{ config(materialized='table') }}

{#- Owner: ML1 (task T7). Report-card columns behind each d_* model feature (team A value minus team B value). -#}
{%- set seasons = [2014, 2015, 2016, 2017] -%}
{%- set card_columns = ['adj_oe', 'adj_de', 'adj_net', 'tempo', 'efg_pct', 'tov_pct', 'orb_pct', 'ftr',
  'opp_efg_pct', 'opp_tov_pct', 'drb_pct', 'opp_ftr', 'three_par', 'sos_adj_net', 'last10_net',
  'program_win_pct_5y', 'win_pct'] -%}
{%- set model_prefix = this.database ~ "." ~ this.schema ~ "." -%}

-- Grain: scenario x team_a x team_b over each scenario's 68 tournament teams, neutral court.
-- Backtests (backtest_<season>): the chosen walk-forward family for that season on pre_ncaa report cards.
-- Forecast (proj_<forecast season>): the rating-only forward model on projected ratings.
-- p_a_wins is symmetrized: (p(a,b) + 1 - p(b,a)) / 2, so p(a,b) + p(b,a) = 1 exactly.
WITH chosen AS (
  SELECT ANY_VALUE(model_name) AS model_name
  FROM {{ ref('m_game_win') }}
  WHERE is_chosen_model
),

backtest_teams AS (
  SELECT DISTINCT
    b.season,
    team_id
  FROM {{ ref('stg_bracket') }} AS b,
    UNNEST([b.side_a_team_id, b.side_b_team_id]) AS team_id
  WHERE team_id IS NOT NULL
    AND b.season IN ({{ seasons | join(', ') }})
),

backtest_pairs AS (
  SELECT
    t1.season,
    t1.team_id AS team_a_id,
    t2.team_id AS team_b_id,
    0 AS home_indicator,
    {%- for c in card_columns %}
    a.{{ c }} - b.{{ c }} AS d_{{ c }}{{ ',' if not loop.last }}
    {%- endfor %}
  FROM backtest_teams AS t1
  INNER JOIN backtest_teams AS t2
    ON t2.season = t1.season
    AND t2.team_id != t1.team_id
  INNER JOIN {{ ref('f_team_season') }} AS a
    ON a.season = t1.season AND a.team_id = t1.team_id AND a.scope = 'pre_ncaa'
  INNER JOIN {{ ref('f_team_season') }} AS b
    ON b.season = t2.season AND b.team_id = t2.team_id AND b.scope = 'pre_ncaa'
),

forecast_pairs AS (
  SELECT
    a.team_id AS team_a_id,
    b.team_id AS team_b_id,
    0 AS home_indicator,
    a.projected_adj_net - b.projected_adj_net AS d_adj_net
  FROM {{ ref('projected_field') }} AS a
  INNER JOIN {{ ref('projected_field') }} AS b
    ON b.team_id != a.team_id
),

raw AS (
  {%- for s in seasons %}
  {%- for family, code in [('logistic_reg', 'lr'), ('boosted_tree', 'bt')] %}
  SELECT
    {{ s }} AS season,
    '{{ family }}' AS model_name,
    team_a_id,
    team_b_id,
    (SELECT p.prob FROM UNNEST(predicted_label_a_wins_probs) AS p WHERE p.label = 1) AS p_raw
  FROM ML.PREDICT(
    MODEL `{{ model_prefix }}m_game_win_{{ code }}_s{{ s }}`,
    (SELECT * FROM backtest_pairs WHERE season = {{ s }})
  )
  UNION ALL
  {%- endfor %}
  {%- endfor %}
  SELECT
    {{ var('forecast_season') }} AS season,
    'rating_only' AS model_name,
    team_a_id,
    team_b_id,
    (SELECT p.prob FROM UNNEST(predicted_label_a_wins_probs) AS p WHERE p.label = 1) AS p_raw
  FROM ML.PREDICT(
    MODEL `{{ model_prefix }}m_game_win_rt_all`,
    (SELECT * FROM forecast_pairs)
  )
),

selected AS (
  SELECT r.*
  FROM raw AS r
  CROSS JOIN chosen AS c
  WHERE r.season = {{ var('forecast_season') }}
    OR r.model_name = c.model_name
)

SELECT
  IF(
    s.season = {{ var('forecast_season') }},
    CONCAT('proj_', CAST(s.season AS STRING)),
    CONCAT('backtest_', CAST(s.season AS STRING))
  ) AS scenario,
  s.season,
  s.model_name,
  s.team_a_id,
  s.team_b_id,
  (s.p_raw + 1 - r.p_raw) / 2 AS p_a_wins
FROM selected AS s
INNER JOIN selected AS r
  ON r.season = s.season
  AND r.team_a_id = s.team_b_id
  AND r.team_b_id = s.team_a_id
