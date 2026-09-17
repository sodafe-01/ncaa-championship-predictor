-- Grain: scenario x tournament team (68 per scenario). Owner: DE2 (story DE-11).
-- AI scouting report (Gemini, numbers only) plus the win model's top drivers for the team against an average
-- tournament team (ML.EXPLAIN_PREDICT, team-profile rows of m_explain_topk).
WITH drivers AS (
  SELECT
    scenario,
    team_id,
    STRING_AGG(
      CONCAT(
        CASE feature
          WHEN 'home_indicator' THEN 'home court'
          WHEN 'd_adj_oe' THEN 'adjusted offense'
          WHEN 'd_adj_de' THEN 'adjusted defense (points allowed)'
          WHEN 'd_adj_net' THEN 'adjusted margin'
          WHEN 'd_tempo' THEN 'tempo'
          WHEN 'd_efg_pct' THEN 'effective field-goal %'
          WHEN 'd_tov_pct' THEN 'turnover rate'
          WHEN 'd_orb_pct' THEN 'offensive rebounding'
          WHEN 'd_ftr' THEN 'free-throw rate'
          WHEN 'd_opp_efg_pct' THEN 'opponents\' effective field-goal %'
          WHEN 'd_opp_tov_pct' THEN 'turnovers forced'
          WHEN 'd_drb_pct' THEN 'defensive rebounding'
          WHEN 'd_opp_ftr' THEN 'opponents\' free-throw rate'
          WHEN 'd_three_par' THEN 'three-point attempt rate'
          WHEN 'd_sos_adj_net' THEN 'schedule strength'
          WHEN 'd_last10_net' THEN 'last-10-game margin'
          WHEN 'd_program_win_pct_5y' THEN 'five-year program win %'
          WHEN 'd_win_pct' THEN 'win %'
          ELSE feature
        END,
        FORMAT(' %+.3g vs field average', feature_value),
        IF(attribution >= 0, ' (raises win chance)', ' (lowers win chance)')
      ),
      '; '
      ORDER BY attribution_rank
    ) AS top_drivers
  FROM {{ ref('m_explain_topk') }}
  WHERE explain_level = 'team_profile'
  GROUP BY scenario, team_id
)

SELECT
  s.scenario,
  s.season,
  s.team_id,
  t.display_name AS team_name,
  CONCAT('• ', ARRAY_TO_STRING(s.strengths, '\n• ')) AS strengths,
  CONCAT('• ', ARRAY_TO_STRING(s.weaknesses, '\n• ')) AS weaknesses,
  s.style,
  s.x_factor,
  d.top_drivers,
  s.generated_at
FROM {{ ref('ai_team_scouting') }} AS s
LEFT JOIN {{ ref('stg_teams') }} AS t
  ON t.team_id = s.team_id
LEFT JOIN drivers AS d
  ON d.scenario = s.scenario
  AND d.team_id = s.team_id
