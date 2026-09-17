{#- Next-season rating model: holdout check + final fit. Owner: ML2 (task T10).
    Hooks are stored at parse time (when ref() still points at this model), so the hook copy of the
    transitions query keeps ref() as literal Jinja; the body copy uses the resolved relation. -#}
{%- set transitions_template =
  "SELECT cur.season, nxt.adj_net AS next_adj_net, cur.adj_net, prev.adj_net AS prior_adj_net, "
  ~ "cur.ret_min_share, cur.ret_pts_share, cur.conference_strength "
  ~ "FROM __FTS__ AS cur "
  ~ "JOIN __FTS__ AS nxt ON nxt.team_id = cur.team_id AND nxt.season = cur.season + 1 AND nxt.scope = 'pre_ncaa' "
  ~ "LEFT JOIN __FTS__ AS prev ON prev.team_id = cur.team_id AND prev.season = cur.season - 1 AND prev.scope = 'full' "
  ~ "WHERE cur.scope = 'full'"
-%}
{%- set hook_transitions_sql = transitions_template.replace('__FTS__', "{{ ref('f_team_season') }}") -%}
{%- set transitions_sql = transitions_template.replace('__FTS__', ref('f_team_season') | string) -%}
{%- set model_prefix = this.database ~ "." ~ this.schema ~ "." -%}
{%- set options = "OPTIONS (model_type = 'LINEAR_REG', input_label_cols = ['next_adj_net'], data_split_method = 'NO_SPLIT', enable_global_explain = TRUE)" -%}
{%- set hooks = [
  "CREATE OR REPLACE MODEL `" ~ model_prefix ~ "m_next_season_holdout` " ~ options
    ~ " AS SELECT next_adj_net, adj_net, prior_adj_net, ret_min_share, ret_pts_share, conference_strength FROM ("
    ~ hook_transitions_sql ~ ") WHERE season IN (2014, 2015)",
  "CREATE OR REPLACE MODEL `" ~ model_prefix ~ "m_next_season` " ~ options
    ~ " AS SELECT next_adj_net, adj_net, prior_adj_net, ret_min_share, ret_pts_share, conference_strength FROM ("
    ~ hook_transitions_sql ~ ") WHERE season IN (2014, 2015, 2016)"
] -%}
{{ config(materialized='table', pre_hook=hooks) }}

-- Grain: one row, the 2016-17 -> 2017-18 transition scored by a model that never saw it.
WITH holdout AS (
  SELECT
    predicted_next_adj_net,
    next_adj_net,
    adj_net
  FROM ML.PREDICT(
    MODEL `{{ model_prefix }}m_next_season_holdout`,
    ({{ transitions_sql }})
  )
  WHERE season = 2016
)

SELECT
  'holdout_2016_to_2017' AS evaluation,
  COUNT(*) AS teams_scored,
  SQRT(AVG(POW(predicted_next_adj_net - next_adj_net, 2))) AS rmse,
  AVG(ABS(predicted_next_adj_net - next_adj_net)) AS mae,
  1 - SUM(POW(predicted_next_adj_net - next_adj_net, 2))
    / SUM(POW(next_adj_net - (SELECT AVG(next_adj_net) FROM holdout), 2)) AS r2,
  SQRT(AVG(POW(adj_net - next_adj_net, 2))) AS carry_forward_rmse
FROM holdout
