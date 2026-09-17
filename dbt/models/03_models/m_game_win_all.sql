{#- Forward models trained on every matchup row through 2017-18, for the 2018-19 pick. Owner: ML1 (task T6). -#}
{%- set full_features = ['home_indicator', 'd_adj_oe', 'd_adj_de', 'd_adj_net', 'd_tempo', 'd_efg_pct', 'd_tov_pct',
  'd_orb_pct', 'd_ftr', 'd_opp_efg_pct', 'd_opp_tov_pct', 'd_drb_pct', 'd_opp_ftr', 'd_three_par',
  'd_sos_adj_net', 'd_last10_net', 'd_program_win_pct_5y', 'd_win_pct'] -%}
{%- set model_prefix = this.database ~ "." ~ this.schema ~ "." -%}
{#- ref() stays literal Jinja in hook strings: hooks are stored at parse time and rendered at run time. -#}
{%- set source_rows = " FROM {{ ref('f_matchups') }} WHERE season <= " ~ var('last_season') -%}
-- depends_on: {{ ref('f_matchups') }}
{%- set hooks = [
  "CREATE OR REPLACE MODEL `" ~ model_prefix ~ "m_game_win_lr_all` OPTIONS (model_type = 'LOGISTIC_REG', "
    ~ "input_label_cols = ['label_a_wins'], data_split_method = 'NO_SPLIT', l2_reg = 1.0, enable_global_explain = TRUE) AS "
    ~ "SELECT label_a_wins, " ~ full_features | join(', ') ~ source_rows,
  "CREATE OR REPLACE MODEL `" ~ model_prefix ~ "m_game_win_bt_all` OPTIONS (model_type = 'BOOSTED_TREE_CLASSIFIER', "
    ~ "input_label_cols = ['label_a_wins'], data_split_method = 'NO_SPLIT', max_iterations = 30, max_tree_depth = 4, "
    ~ "learn_rate = 0.1, subsample = 0.8, enable_global_explain = TRUE) AS "
    ~ "SELECT label_a_wins, " ~ full_features | join(', ') ~ source_rows,
  "CREATE OR REPLACE MODEL `" ~ model_prefix ~ "m_game_win_rt_all` OPTIONS (model_type = 'LOGISTIC_REG', "
    ~ "input_label_cols = ['label_a_wins'], data_split_method = 'NO_SPLIT', enable_global_explain = TRUE) AS "
    ~ "SELECT label_a_wins, home_indicator, d_adj_net" ~ source_rows
] -%}
{{ config(materialized='table', pre_hook=hooks) }}

-- Grain: model x feature, global feature importance of the forward models.
SELECT 'logistic_reg' AS model_name, feature, attribution
FROM ML.GLOBAL_EXPLAIN(MODEL `{{ model_prefix }}m_game_win_lr_all`)
UNION ALL
SELECT 'boosted_tree' AS model_name, feature, attribution
FROM ML.GLOBAL_EXPLAIN(MODEL `{{ model_prefix }}m_game_win_bt_all`)
UNION ALL
SELECT 'rating_only' AS model_name, feature, attribution
FROM ML.GLOBAL_EXPLAIN(MODEL `{{ model_prefix }}m_game_win_rt_all`)
