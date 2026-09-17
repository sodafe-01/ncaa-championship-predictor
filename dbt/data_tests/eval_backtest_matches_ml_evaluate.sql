-- depends_on: {{ ref('m_game_win_lr') }}
-- depends_on: {{ ref('m_game_win_bt') }}
-- depends_on: {{ ref('m_game_win_rt') }}
-- eval_backtest's log loss equals ML.EVALUATE on the same tournament rows for every family and season
{%- set model_prefix = target.project ~ "." ~ target.dataset ~ "." %}
{%- set features = ['home_indicator', 'd_adj_oe', 'd_adj_de', 'd_adj_net', 'd_tempo', 'd_efg_pct', 'd_tov_pct',
  'd_orb_pct', 'd_ftr', 'd_opp_efg_pct', 'd_opp_tov_pct', 'd_drb_pct', 'd_opp_ftr', 'd_three_par',
  'd_sos_adj_net', 'd_last10_net', 'd_program_win_pct_5y', 'd_win_pct'] %}
WITH ml_evaluate AS (
  {%- for s in [2014, 2015, 2016, 2017] %}
  {%- for family, code in [('logistic_reg', 'lr'), ('boosted_tree', 'bt'), ('rating_only', 'rt')] %}
  SELECT {{ s }} AS season, '{{ family }}' AS model_name, log_loss
  FROM ML.EVALUATE(
    MODEL `{{ model_prefix }}m_game_win_{{ code }}_s{{ s }}`,
    (
      SELECT label_a_wins, {{ features | join(', ') }}
      FROM {{ ref('f_matchups') }}
      WHERE season = {{ s }} AND is_tournament_row
    )
  )
  {{ 'UNION ALL' if not loop.last }}
  {%- endfor %}
  {{ 'UNION ALL' if not loop.last }}
  {%- endfor %}
)
SELECT e.season, e.model_name, e.logloss, m.log_loss AS ml_evaluate_log_loss
FROM {{ ref('eval_backtest') }} AS e
INNER JOIN ml_evaluate AS m
  ON m.season = e.season
  AND m.model_name = e.model_name
WHERE ABS(e.logloss - m.log_loss) > 1e-4
