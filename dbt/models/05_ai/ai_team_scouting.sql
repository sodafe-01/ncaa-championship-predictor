{{ config(materialized='table') }}

-- Grain: scenario x tournament team (68 per scenario). Owner: AE (task T11). Template: prompts/scout.md.
-- Gemini sees only the team's own numbers: no team name, no conference, no season outcome, so real-world
-- knowledge of later results (including the 2019 champion) cannot leak in. Build on purpose with
-- `scripts/dbt.sh build --select tag:ai`; the table is materialized so the demo never calls Gemini live.
WITH teams AS (
  SELECT
    r.scenario,
    r.season,
    r.team_id,
    IF(STARTS_WITH(r.scenario, 'proj_'), {{ var('last_season') }}, r.season) AS card_season
  FROM {{ ref('sim_results') }} AS r
),

cards AS (
  SELECT
    t.scenario,
    t.season,
    t.team_id,
    f.season_label AS card_season_label,
    f.wins,
    f.losses,
    f.adj_oe,
    f.adj_de,
    f.adj_net,
    f.rank_adj_net,
    f.tempo,
    f.efg_pct,
    f.tov_pct,
    f.orb_pct,
    f.ftr,
    f.three_par,
    f.three_pct,
    f.opp_efg_pct,
    f.sos_adj_net,
    f.last10_net,
    f.pctl_adj_oe,
    f.pctl_adj_de,
    f.pctl_tempo,
    f.pctl_efg_pct,
    f.pctl_tov_pct,
    f.pctl_orb_pct,
    f.pctl_ftr,
    f.pctl_three_par,
    f.pctl_opp_efg_pct,
    p.projected_adj_net,
    p.projected_low,
    p.projected_high,
    p.projected_rank,
    p.ret_min_share AS projected_ret_min_share
  FROM teams AS t
  INNER JOIN {{ ref('f_team_season') }} AS f
    ON f.season = t.card_season
    AND f.team_id = t.team_id
    AND f.scope = 'pre_ncaa'
  LEFT JOIN {{ ref('f_team_projection') }} AS p
    ON STARTS_WITH(t.scenario, 'proj_')
    AND p.team_id = t.team_id
),

prompts AS (
  SELECT
    scenario,
    season,
    team_id,
    CONCAT(
      'You are a college basketball scout writing for executives. Use ONLY the numbers below. ',
      'Do not use any outside knowledge about teams, players, coaches, seasons or tournament results, ',
      'and do not guess which team this is. Ratings are points per 100 possessions against an average ',
      'opponent on a neutral court. Percentiles compare the team with all 351 Division I teams that season ',
      '(1.00 = best unless noted).\n\n',
      'Profile before the NCAA tournament (', card_season_label, '):\n',
      FORMAT('- Record: %d-%d\n', wins, losses),
      FORMAT('- Adjusted offense: %.1f (percentile %.2f)\n', adj_oe, pctl_adj_oe),
      FORMAT('- Adjusted defense: %.1f points allowed (percentile %.2f; lower allowed is better)\n', adj_de, pctl_adj_de),
      FORMAT('- Adjusted margin: %+.1f (rank %d of 351)\n', adj_net, rank_adj_net),
      FORMAT('- Tempo: %.1f possessions per game (percentile %.2f, 1.00 = fastest)\n', tempo, pctl_tempo),
      FORMAT('- Effective field-goal percentage: %.3f (percentile %.2f)\n', efg_pct, pctl_efg_pct),
      FORMAT('- Turnovers per possession: %.3f (percentile %.2f, 1.00 = fewest)\n', tov_pct, pctl_tov_pct),
      FORMAT('- Offensive rebound rate: %.3f (percentile %.2f)\n', orb_pct, pctl_orb_pct),
      FORMAT('- Free throws attempted per shot: %.3f (percentile %.2f)\n', ftr, pctl_ftr),
      FORMAT('- Share of shots that are threes: %.3f (percentile %.2f, 1.00 = most threes)\n', three_par, pctl_three_par),
      FORMAT('- Three-point percentage: %.3f\n', three_pct),
      FORMAT('- Opponents\' effective field-goal percentage: %.3f (percentile %.2f, 1.00 = best defense)\n', opp_efg_pct, pctl_opp_efg_pct),
      FORMAT('- Strength of schedule (average opponent margin): %+.1f\n', sos_adj_net),
      FORMAT('- Net margin over the last 10 games: %+.1f\n', last10_net),
      IF(
        projected_adj_net IS NULL,
        '',
        CONCAT(
          '\nProjection for next season:\n',
          FORMAT('- Projected adjusted margin: %+.1f (80%% band %+.1f to %+.1f), projected rank %d\n',
            projected_adj_net, projected_low, projected_high, projected_rank),
          FORMAT('- Share of minutes expected back (class-based estimate): %.2f\n', projected_ret_min_share)
        )
      ),
      '\nReturn 2-3 strengths and 2-3 weaknesses as short phrases that cite the numbers, a one-sentence playing ',
      'style, and one x_factor sentence naming the single number most likely to decide its tournament games.'
    ) AS prompt
  FROM cards
),

generated AS (
  SELECT
    scenario,
    season,
    team_id,
    prompt,
    AI.GENERATE(
      prompt,
      endpoint => 'gemini-2.5-flash',
      model_params => JSON '{"generationConfig": {"temperature": 0, "thinkingConfig": {"thinkingBudget": 0}}}',
      output_schema => 'strengths ARRAY<STRING>, weaknesses ARRAY<STRING>, style STRING, x_factor STRING'
    ) AS g
  FROM prompts
)

SELECT
  scenario,
  season,
  {{ season_label('season') }} AS season_label,
  team_id,
  g.strengths,
  g.weaknesses,
  g.style,
  g.x_factor,
  g.status,
  prompt,
  'gemini-2.5-flash' AS endpoint,
  CURRENT_TIMESTAMP() AS generated_at
FROM generated
