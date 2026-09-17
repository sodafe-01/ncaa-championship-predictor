-- Grain: scenario x tournament team (68 per scenario). Owner: DE2 (story DE-11).
-- Backtests (backtest_2014 = March 2015 ... backtest_2017 = March 2018) use pre-tournament ratings and the real
-- bracket; proj_2018 is the 2018-19 forecast on projected ratings and the projected bracket.
WITH odds AS (
  SELECT
    scenario,
    season,
    team_id,
    seed,
    region,
    p_r32,
    p_s16,
    p_e8,
    p_f4,
    p_final,
    p_champ
  FROM {{ ref('sim_results') }}
)

SELECT
  o.scenario,
  o.season,
  {{ season_label('o.season') }} AS season_label,
  STARTS_WITH(o.scenario, 'proj_') AS is_forecast,
  o.team_id,
  t.display_name AS team_name,
  COALESCE(tp.conference, pf.conf_alias) AS conference,
  t.color_hex,
  t.logo_medium AS logo_url,
  o.seed,
  o.region,
  o.p_r32 AS p_round_of_32,
  o.p_s16 AS p_sweet_16,
  o.p_e8 AS p_elite_8,
  o.p_f4 AS p_final_four,
  o.p_final,
  o.p_champ AS p_champion,
  RANK() OVER (PARTITION BY o.scenario ORDER BY o.p_champ DESC) AS odds_rank,
  COALESCE(tp.adj_margin, pr.projected_adj_net) AS adj_margin,
  pr.projected_low AS adj_margin_low,
  pr.projected_high AS adj_margin_high,
  COALESCE(tp.strength_rank, pr.projected_rank) AS strength_rank,
  tp.ncaa_last_round AS actual_last_round,
  tp.is_champion AS is_actual_champion
FROM odds AS o
LEFT JOIN {{ ref('stg_teams') }} AS t
  ON t.team_id = o.team_id
LEFT JOIN {{ ref('mart_team_profile') }} AS tp
  ON NOT STARTS_WITH(o.scenario, 'proj_')
  AND tp.season = o.season
  AND tp.team_id = o.team_id
LEFT JOIN {{ ref('projected_field') }} AS pf
  ON STARTS_WITH(o.scenario, 'proj_')
  AND pf.team_id = o.team_id
LEFT JOIN {{ ref('f_team_projection') }} AS pr
  ON STARTS_WITH(o.scenario, 'proj_')
  AND pr.team_id = o.team_id
