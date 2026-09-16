{{
  config(materialized="table")
}}

WITH ncaa_openers AS (
  SELECT
    season,
    MIN(scheduled_date) AS first_ncaa_date
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
  GROUP BY season
),

scopes AS (
  SELECT 'pre_ncaa' AS scope
  UNION ALL
  SELECT 'full' AS scope
),

d1_teams AS (
  SELECT
    season,
    team_id,
    ANY_VALUE(market) AS market,
    ANY_VALUE(alias) AS alias
  FROM {{ ref('stg_team_games') }}
  WHERE division_alias = 'D1'
    AND season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
  GROUP BY season, team_id
),

spine AS (
  SELECT
    t.season,
    s.scope,
    t.team_id,
    t.market,
    t.alias
  FROM d1_teams AS t
  CROSS JOIN scopes AS s
),

in_scope AS (
  SELECT
    tg.season,
    sc.scope,
    tg.team_id,
    tg.conf_alias,
    tg.win
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN ncaa_openers AS n
    ON n.season = tg.season
  CROSS JOIN scopes AS sc
  WHERE tg.is_closed
    AND tg.win IS NOT NULL
    AND tg.division_alias = 'D1'
    AND tg.season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
    AND (
      sc.scope = 'full'
      OR tg.scheduled_date < n.first_ncaa_date
    )
),

conf_mode AS (
  SELECT
    season,
    scope,
    team_id,
    conf_alias
  FROM (
    SELECT
      season,
      scope,
      team_id,
      conf_alias,
      ROW_NUMBER() OVER (
        PARTITION BY season, scope, team_id
        ORDER BY COUNT(*) DESC, conf_alias
      ) AS rn
    FROM in_scope
    GROUP BY season, scope, team_id, conf_alias
  )
  WHERE rn = 1
),

agg AS (
  SELECT
    season,
    scope,
    team_id,
    COUNT(*) AS games,
    COUNTIF(win) AS wins,
    COUNT(*) - COUNTIF(win) AS losses
  FROM in_scope
  GROUP BY season, scope, team_id
)

SELECT
  sp.season,
  {{ season_label('sp.season') }} AS season_label,
  sp.scope,
  sp.team_id,
  sp.market,
  sp.alias,
  cm.conf_alias,
  COALESCE(a.games, 0) AS games,
  COALESCE(a.wins, 0) AS wins,
  COALESCE(a.losses, 0) AS losses,
  SAFE_DIVIDE(a.wins, a.games) AS win_pct,
  CAST(NULL AS INT64) AS d1_games,
  CAST(NULL AS FLOAT64) AS tempo,
  CAST(NULL AS FLOAT64) AS raw_oe,
  CAST(NULL AS FLOAT64) AS raw_de,
  CAST(NULL AS FLOAT64) AS raw_net,
  CAST(NULL AS FLOAT64) AS adj_oe,
  CAST(NULL AS FLOAT64) AS adj_de,
  CAST(NULL AS FLOAT64) AS adj_net,
  CAST(NULL AS FLOAT64) AS sos_adj_net,
  CAST(NULL AS FLOAT64) AS conference_strength,
  CAST(NULL AS FLOAT64) AS efg_pct,
  CAST(NULL AS FLOAT64) AS tov_pct,
  CAST(NULL AS FLOAT64) AS orb_pct,
  CAST(NULL AS FLOAT64) AS ftr,
  CAST(NULL AS FLOAT64) AS opp_efg_pct,
  CAST(NULL AS FLOAT64) AS opp_tov_pct,
  CAST(NULL AS FLOAT64) AS drb_pct,
  CAST(NULL AS FLOAT64) AS opp_ftr,
  CAST(NULL AS FLOAT64) AS three_par,
  CAST(NULL AS FLOAT64) AS three_pct,
  CAST(NULL AS FLOAT64) AS ft_pct,
  CAST(NULL AS FLOAT64) AS last10_net,
  CAST(NULL AS INT64) AS ap_rank_last,
  CAST(NULL AS FLOAT64) AS experience_index,
  CAST(NULL AS FLOAT64) AS ret_min_share,
  CAST(NULL AS FLOAT64) AS ret_pts_share,
  CAST(NULL AS STRING) AS ret_basis,
  CAST(NULL AS FLOAT64) AS program_win_pct_5y,
  CAST(NULL AS INT64) AS rank_adj_net,
  CAST(NULL AS FLOAT64) AS pctl_adj_oe,
  CAST(NULL AS FLOAT64) AS pctl_adj_de,
  CAST(NULL AS FLOAT64) AS pctl_adj_net,
  CAST(NULL AS FLOAT64) AS pctl_tempo,
  CAST(NULL AS FLOAT64) AS pctl_efg_pct,
  CAST(NULL AS FLOAT64) AS pctl_tov_pct,
  CAST(NULL AS FLOAT64) AS pctl_orb_pct,
  CAST(NULL AS FLOAT64) AS pctl_ftr,
  CAST(NULL AS FLOAT64) AS pctl_three_par,
  CAST(NULL AS FLOAT64) AS pctl_opp_efg_pct
FROM spine AS sp
LEFT JOIN agg AS a
  ON a.season = sp.season
  AND a.scope = sp.scope
  AND a.team_id = sp.team_id
LEFT JOIN conf_mode AS cm
  ON cm.season = sp.season
  AND cm.scope = sp.scope
  AND cm.team_id = sp.team_id
