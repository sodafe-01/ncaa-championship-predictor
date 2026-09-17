{#- Walk-forward rating-only logistic regression (the forecast family). Owner: ML1 (task T6). -#}
{%- set seasons = [2014, 2015, 2016, 2017] -%}
{%- set features = ['home_indicator', 'd_adj_net'] -%}
{%- set hooks = [] -%}
{%- for s in seasons -%}
  {%- do hooks.append(
    "CREATE OR REPLACE MODEL `" ~ this.database ~ "." ~ this.schema ~ ".m_game_win_rt_s" ~ s ~ "` "
    ~ "OPTIONS (model_type = 'LOGISTIC_REG', input_label_cols = ['label_a_wins'], data_split_method = 'NO_SPLIT', "
    ~ "enable_global_explain = TRUE) AS "
    ~ "SELECT label_a_wins, " ~ features | join(', ') ~ " FROM {{ ref('f_matchups') }}"
    ~ " WHERE season < " ~ s ~ " OR (season = " ~ s ~ " AND is_training_row)"
  ) -%}
{%- endfor -%}
{{ config(materialized='table', pre_hook=hooks) }}

-- Grain: backtest season x NCAA tournament row (game_id x team_a_id). Model for season s never saw its tournament.
{% for s in seasons %}
SELECT
  {{ s }} AS season,
  'rating_only' AS model_name,
  game_id,
  team_a_id,
  team_b_id,
  label_a_wins,
  (SELECT p.prob FROM UNNEST(predicted_label_a_wins_probs) AS p WHERE p.label = 1) AS p_a_wins
FROM ML.PREDICT(
  MODEL `{{ this.database }}.{{ this.schema }}.m_game_win_rt_s{{ s }}`,
  (
    SELECT game_id, team_a_id, team_b_id, label_a_wins, {{ features | join(', ') }}
    FROM {{ ref('f_matchups') }}
    WHERE season = {{ s }} AND is_tournament_row
  )
)
{% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
