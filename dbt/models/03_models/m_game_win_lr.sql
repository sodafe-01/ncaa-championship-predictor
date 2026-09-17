{#- Walk-forward logistic regression, one BQML model per backtest season. Owner: ML1 (task T6).
    Hook strings keep ref() as literal Jinja: hooks are stored at parse time, when ref() still points at this
    model, and are rendered again at run time. -#}
{%- set seasons = [2014, 2015, 2016, 2017] -%}
{%- set features = ['home_indicator', 'd_adj_oe', 'd_adj_de', 'd_adj_net', 'd_tempo', 'd_efg_pct', 'd_tov_pct',
  'd_orb_pct', 'd_ftr', 'd_opp_efg_pct', 'd_opp_tov_pct', 'd_drb_pct', 'd_opp_ftr', 'd_three_par',
  'd_sos_adj_net', 'd_last10_net', 'd_program_win_pct_5y', 'd_win_pct'] -%}
{%- set hooks = [] -%}
{%- for s in seasons -%}
  {%- do hooks.append(
    "CREATE OR REPLACE MODEL `" ~ this.database ~ "." ~ this.schema ~ ".m_game_win_lr_s" ~ s ~ "` "
    ~ "OPTIONS (model_type = 'LOGISTIC_REG', input_label_cols = ['label_a_wins'], data_split_method = 'NO_SPLIT', "
    ~ "l2_reg = 1.0, enable_global_explain = TRUE) AS "
    ~ "SELECT label_a_wins, " ~ features | join(', ') ~ " FROM {{ ref('f_matchups') }}"
    ~ " WHERE season < " ~ s ~ " OR (season = " ~ s ~ " AND is_training_row)"
  ) -%}
{%- endfor -%}
{{ config(materialized='table', pre_hook=hooks) }}

-- Grain: backtest season x NCAA tournament row (game_id x team_a_id). Model for season s never saw its tournament.
{% for s in seasons %}
SELECT
  {{ s }} AS season,
  'logistic_reg' AS model_name,
  game_id,
  team_a_id,
  team_b_id,
  label_a_wins,
  (SELECT p.prob FROM UNNEST(predicted_label_a_wins_probs) AS p WHERE p.label = 1) AS p_a_wins
FROM ML.PREDICT(
  MODEL `{{ this.database }}.{{ this.schema }}.m_game_win_lr_s{{ s }}`,
  (
    SELECT game_id, team_a_id, team_b_id, label_a_wins, {{ features | join(', ') }}
    FROM {{ ref('f_matchups') }}
    WHERE season = {{ s }} AND is_tournament_row
  )
)
{% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
