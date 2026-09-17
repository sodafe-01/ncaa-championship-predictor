{{ config(materialized='table') }}

{#- Owner: ML1 (task T7). -#}
{%- set seasons = [2014, 2015, 2016, 2017] -%}
{%- set card_columns = ['adj_oe', 'adj_de', 'adj_net', 'tempo', 'efg_pct', 'tov_pct', 'orb_pct', 'ftr',
  'opp_efg_pct', 'opp_tov_pct', 'drb_pct', 'opp_ftr', 'three_par', 'sos_adj_net', 'last10_net',
  'program_win_pct_5y', 'win_pct'] -%}
{%- set model_prefix = this.database ~ "." ~ this.schema ~ "." -%}

-- Grain: scenario x explain_level x (game_id or team profile) x team x attribution rank (top 3), chosen family.
-- explain_level = 'game': each real NCAA tournament game, from each team's side (backtests only).
-- explain_level = 'team_profile': each tournament team's pre-tournament report card against the average of that
-- scenario's 68-team field on a neutral court. For the forecast, the chosen family's forward model explains the
-- 2017-18 report card (the latest measured profile; the projected rating change is not in these attributions).
WITH chosen AS (
  SELECT ANY_VALUE(model_name) AS model_name
  FROM {{ ref('m_game_win') }}
  WHERE is_chosen_model
),

game_rows AS (
  SELECT
    season,
    'game' AS explain_level,
    game_id,
    team_a_id AS team_id,
    team_b_id AS opponent_id,
    home_indicator,
    {%- for c in card_columns %}
    d_{{ c }}{{ ',' if not loop.last }}
    {%- endfor %}
  FROM {{ ref('f_matchups') }}
  WHERE is_tournament_row
    AND season IN ({{ seasons | join(', ') }})
),

field_teams AS (
  SELECT DISTINCT
    b.season AS scenario_season,
    b.season AS card_season,
    team_id
  FROM {{ ref('stg_bracket') }} AS b,
    UNNEST([b.side_a_team_id, b.side_b_team_id]) AS team_id
  WHERE team_id IS NOT NULL
    AND b.season IN ({{ seasons | join(', ') }})
  UNION ALL
  SELECT
    {{ var('forecast_season') }} AS scenario_season,
    {{ var('last_season') }} AS card_season,
    team_id
  FROM {{ ref('projected_field') }}
),

field_cards AS (
  SELECT
    t.scenario_season,
    t.team_id,
    {%- for c in card_columns %}
    f.{{ c }},
    AVG(f.{{ c }}) OVER (PARTITION BY t.scenario_season) AS avg_{{ c }}{{ ',' if not loop.last }}
    {%- endfor %}
  FROM field_teams AS t
  INNER JOIN {{ ref('f_team_season') }} AS f
    ON f.season = t.card_season
    AND f.team_id = t.team_id
    AND f.scope = 'pre_ncaa'
),

profile_rows AS (
  SELECT
    scenario_season AS season,
    'team_profile' AS explain_level,
    CAST(NULL AS STRING) AS game_id,
    team_id,
    CAST(NULL AS STRING) AS opponent_id,
    0 AS home_indicator,
    {%- for c in card_columns %}
    {{ c }} - avg_{{ c }} AS d_{{ c }}{{ ',' if not loop.last }}
    {%- endfor %}
  FROM field_cards
),

explained AS (
  {%- for s in seasons %}
  {%- for family, code in [('logistic_reg', 'lr'), ('boosted_tree', 'bt')] %}
  SELECT '{{ family }}' AS model_name, *
  FROM ML.EXPLAIN_PREDICT(
    MODEL `{{ model_prefix }}m_game_win_{{ code }}_s{{ s }}`,
    (
      SELECT * FROM game_rows WHERE season = {{ s }}
      UNION ALL
      SELECT * FROM profile_rows WHERE season = {{ s }}
    ),
    STRUCT(3 AS top_k_features)
  )
  UNION ALL
  {%- endfor %}
  {%- endfor %}
  {%- for family, code in [('logistic_reg', 'lr'), ('boosted_tree', 'bt')] %}
  SELECT '{{ family }}' AS model_name, *
  FROM ML.EXPLAIN_PREDICT(
    MODEL `{{ model_prefix }}m_game_win_{{ code }}_all`,
    (SELECT * FROM profile_rows WHERE season = {{ var('forecast_season') }}),
    STRUCT(3 AS top_k_features)
  )
  {{ 'UNION ALL' if not loop.last }}
  {%- endfor %}
)

SELECT
  IF(
    e.season = {{ var('forecast_season') }},
    CONCAT('proj_', CAST(e.season AS STRING)),
    CONCAT('backtest_', CAST(e.season AS STRING))
  ) AS scenario,
  e.season,
  e.model_name,
  e.explain_level,
  e.game_id,
  e.team_id,
  e.opponent_id,
  IF(e.predicted_label_a_wins = 1, e.probability, 1 - e.probability) AS p_team_wins,
  attribution_offset + 1 AS attribution_rank,
  fa.feature,
  fa.attribution,
  CASE fa.feature
    WHEN 'home_indicator' THEN CAST(e.home_indicator AS FLOAT64)
    {%- for c in card_columns %}
    WHEN 'd_{{ c }}' THEN e.d_{{ c }}
    {%- endfor %}
  END AS feature_value
FROM explained AS e
CROSS JOIN chosen AS c
CROSS JOIN UNNEST(e.top_feature_attributions) AS fa WITH OFFSET AS attribution_offset
WHERE e.model_name = c.model_name
