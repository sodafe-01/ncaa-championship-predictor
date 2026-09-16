{{
  config(materialized="table")
}}

WITH ready_seasons AS (
  SELECT season
  FROM {{ ref('dq_season_gate') }}
  WHERE model_ready
    AND season BETWEEN {{ var('first_model_season') }} AND {{ var('last_season') }}
),

ncaa_openers AS (
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
    tg.season,
    tg.team_id,
    ANY_VALUE(tg.market) AS market,
    ANY_VALUE(tg.alias) AS alias
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN ready_seasons AS r
    ON r.season = tg.season
  WHERE tg.division_alias = 'D1'
  GROUP BY tg.season, tg.team_id
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
    tg.game_id,
    tg.scheduled_date,
    tg.conf_alias,
    tg.win,
    tg.is_home
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN ncaa_openers AS n
    ON n.season = tg.season
  INNER JOIN ready_seasons AS r
    ON r.season = tg.season
  CROSS JOIN scopes AS sc
  WHERE tg.is_closed
    AND tg.division_alias = 'D1'
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

record_agg AS (
  SELECT
    season,
    scope,
    team_id,
    COUNT(*) AS games,
    COUNTIF(win) AS wins,
    COUNT(*) - COUNTIF(win) AS losses
  FROM in_scope
  GROUP BY season, scope, team_id
),

last_closed AS (
  SELECT
    season,
    scope,
    team_id,
    is_home,
    game_id
  FROM (
    SELECT
      season,
      scope,
      team_id,
      is_home,
      game_id,
      ROW_NUMBER() OVER (
        PARTITION BY season, scope, team_id
        ORDER BY scheduled_date DESC, game_id DESC
      ) AS rn
    FROM in_scope
  )
  WHERE rn = 1
),

ap_rank_last AS (
  SELECT
    lc.season,
    lc.scope,
    lc.team_id,
    IF(lc.is_home, g.home_ap_rank, g.away_ap_rank) AS ap_rank_last
  FROM last_closed AS lc
  INNER JOIN {{ ref('stg_games') }} AS g
    ON g.game_id = lc.game_id
),

eff_scoped AS (
  SELECT
    e.*,
    sc.scope
  FROM {{ ref('f_team_game_efficiency') }} AS e
  INNER JOIN ready_seasons AS r
    ON r.season = e.season
  CROSS JOIN scopes AS sc
  WHERE sc.scope = 'full'
    OR e.in_pre_ncaa_scope
),

eff_valid AS (
  SELECT *
  FROM eff_scoped
  WHERE is_valid_efficiency_row
),

hca AS (
  SELECT
    season,
    scope,
    SQRT(
      SAFE_DIVIDE(
        AVG(IF(is_home AND NOT is_neutral, oe, NULL)),
        AVG(IF(NOT is_home AND NOT is_neutral, oe, NULL))
      )
    ) - 1 AS hca
  FROM eff_valid
  GROUP BY season, scope
),

neutralized AS (
  SELECT
    e.*,
    h.hca,
    CASE
      WHEN e.is_neutral THEN e.oe
      WHEN e.is_home THEN e.oe / (1 + h.hca)
      ELSE e.oe * (1 + h.hca)
    END AS oe_n,
    CASE
      WHEN e.is_neutral THEN e.de
      WHEN e.is_home THEN e.de * (1 + h.hca)
      ELSE e.de / (1 + h.hca)
    END AS de_n
  FROM eff_valid AS e
  INNER JOIN hca AS h
    ON h.season = e.season
    AND h.scope = e.scope
),

league AS (
  SELECT
    season,
    scope,
    AVG(oe) AS lg
  FROM eff_valid
  GROUP BY season, scope
),

eff_agg AS (
  SELECT
    season,
    scope,
    team_id,
    COUNT(*) AS d1_games,
    AVG(game_poss) AS tempo,
    100 * SAFE_DIVIDE(SUM(points), SUM(game_poss)) AS raw_oe,
    100 * SAFE_DIVIDE(SUM(opp_points), SUM(game_poss)) AS raw_de,
    SAFE_DIVIDE(SUM(fgm) + 0.5 * SUM(tpm), SUM(fga)) AS efg_pct,
    SAFE_DIVIDE(SUM(tov), SUM(game_poss)) AS tov_pct,
    SAFE_DIVIDE(SUM(orb), SUM(orb) + SUM(opp_drb)) AS orb_pct,
    SAFE_DIVIDE(SUM(fta), SUM(fga)) AS ftr,
    SAFE_DIVIDE(SUM(opp_fgm) + 0.5 * SUM(opp_tpm), SUM(opp_fga)) AS opp_efg_pct,
    SAFE_DIVIDE(SUM(opp_tov), SUM(game_poss)) AS opp_tov_pct,
    SAFE_DIVIDE(SUM(drb), SUM(drb) + SUM(opp_orb)) AS drb_pct,
    SAFE_DIVIDE(SUM(opp_fta), SUM(opp_fga)) AS opp_ftr,
    SAFE_DIVIDE(SUM(tpa), SUM(fga)) AS three_par,
    SAFE_DIVIDE(SUM(tpm), SUM(tpa)) AS three_pct,
    SAFE_DIVIDE(SUM(ftm), SUM(fta)) AS ft_pct
  FROM eff_valid
  GROUP BY season, scope, team_id
),

last10 AS (
  SELECT
    season,
    scope,
    team_id,
    100 * SAFE_DIVIDE(SUM(points) - SUM(opp_points), SUM(game_poss)) AS last10_net
  FROM (
    SELECT
      season,
      scope,
      team_id,
      points,
      opp_points,
      game_poss,
      ROW_NUMBER() OVER (
        PARTITION BY season, scope, team_id
        ORDER BY game_seq DESC
      ) AS rn_desc
    FROM eff_scoped
  )
  WHERE rn_desc <= 10
  GROUP BY season, scope, team_id
),

ratings_0 AS (
  SELECT
    season,
    scope,
    team_id,
    AVG(oe_n) AS adj_oe,
    AVG(de_n) AS adj_de
  FROM neutralized
  GROUP BY season, scope, team_id
),

{% for k in range(1, 11) %}
pass_{{ k }}_games AS (
  SELECT
    n.season,
    n.scope,
    n.team_id,
    n.game_poss,
    n.oe_n * l.lg / opp.adj_de AS g_oe,
    n.de_n * l.lg / opp.adj_oe AS g_de
  FROM neutralized AS n
  INNER JOIN league AS l
    ON l.season = n.season
    AND l.scope = n.scope
  INNER JOIN ratings_{{ k - 1 }} AS opp
    ON opp.season = n.season
    AND opp.scope = n.scope
    AND opp.team_id = n.opp_id
),

pass_{{ k }}_raw AS (
  SELECT
    season,
    scope,
    team_id,
    SAFE_DIVIDE(SUM(g_oe * game_poss), SUM(game_poss)) AS adj_oe,
    SAFE_DIVIDE(SUM(g_de * game_poss), SUM(game_poss)) AS adj_de
  FROM pass_{{ k }}_games
  GROUP BY season, scope, team_id
),

ratings_{{ k }} AS (
  SELECT
    r.season,
    r.scope,
    r.team_id,
    r.adj_oe * l.lg / AVG(r.adj_oe) OVER (PARTITION BY r.season, r.scope) AS adj_oe,
    r.adj_de * l.lg / AVG(r.adj_de) OVER (PARTITION BY r.season, r.scope) AS adj_de
  FROM pass_{{ k }}_raw AS r
  INNER JOIN league AS l
    ON l.season = r.season
    AND l.scope = r.scope
){% if not loop.last %},{% endif %}
{% endfor %}
,

final_ratings AS (
  SELECT
    season,
    scope,
    team_id,
    adj_oe,
    adj_de,
    adj_oe - adj_de AS adj_net
  FROM ratings_10
),

sos AS (
  SELECT
    n.season,
    n.scope,
    n.team_id,
    AVG(opp.adj_net) AS sos_adj_net
  FROM neutralized AS n
  INNER JOIN final_ratings AS opp
    ON opp.season = n.season
    AND opp.scope = n.scope
    AND opp.team_id = n.opp_id
  GROUP BY n.season, n.scope, n.team_id
),

experience AS (
  SELECT
    pg.season,
    sc.scope,
    pg.team_id,
    SAFE_DIVIDE(SUM(pg.class_rank * pg.minutes), SUM(pg.minutes)) AS experience_index
  FROM {{ ref('stg_player_games') }} AS pg
  INNER JOIN ncaa_openers AS n
    ON n.season = pg.season
  INNER JOIN ready_seasons AS r
    ON r.season = pg.season
  CROSS JOIN scopes AS sc
  WHERE pg.played
    AND pg.is_closed
    AND pg.class_rank IS NOT NULL
    AND pg.season = {{ var('last_season') }}
    AND (
      sc.scope = 'full'
      OR pg.scheduled_date < n.first_ncaa_date
    )
  GROUP BY pg.season, sc.scope, pg.team_id
),

program_5y AS (
  SELECT
    t.season,
    t.team_id,
    SAFE_DIVIDE(SUM(h.wins), SUM(h.wins + h.losses)) AS program_win_pct_5y
  FROM d1_teams AS t
  LEFT JOIN {{ ref('stg_team_season_history') }} AS h
    ON h.team_id = t.team_id
    AND h.season BETWEEN t.season - 5 AND t.season - 1
  GROUP BY t.season, t.team_id
),

assembled AS (
  SELECT
    sp.season,
    {{ season_label('sp.season') }} AS season_label,
    sp.scope,
    sp.team_id,
    sp.market,
    sp.alias,
    cm.conf_alias,
    COALESCE(rec.games, 0) AS games,
    COALESCE(rec.wins, 0) AS wins,
    COALESCE(rec.losses, 0) AS losses,
    SAFE_DIVIDE(rec.wins, rec.games) AS win_pct,
    ea.d1_games,
    ea.tempo,
    ea.raw_oe,
    ea.raw_de,
    ea.raw_oe - ea.raw_de AS raw_net,
    fr.adj_oe,
    fr.adj_de,
    fr.adj_net,
    sos.sos_adj_net,
    ea.efg_pct,
    ea.tov_pct,
    ea.orb_pct,
    ea.ftr,
    ea.opp_efg_pct,
    ea.opp_tov_pct,
    ea.drb_pct,
    ea.opp_ftr,
    ea.three_par,
    ea.three_pct,
    ea.ft_pct,
    l10.last10_net,
    ap.ap_rank_last,
    ex.experience_index,
    rc.ret_min_share,
    rc.ret_pts_share,
    rc.ret_basis,
    p5.program_win_pct_5y
  FROM spine AS sp
  LEFT JOIN record_agg AS rec
    ON rec.season = sp.season
    AND rec.scope = sp.scope
    AND rec.team_id = sp.team_id
  LEFT JOIN conf_mode AS cm
    ON cm.season = sp.season
    AND cm.scope = sp.scope
    AND cm.team_id = sp.team_id
  LEFT JOIN eff_agg AS ea
    ON ea.season = sp.season
    AND ea.scope = sp.scope
    AND ea.team_id = sp.team_id
  LEFT JOIN final_ratings AS fr
    ON fr.season = sp.season
    AND fr.scope = sp.scope
    AND fr.team_id = sp.team_id
  LEFT JOIN sos
    ON sos.season = sp.season
    AND sos.scope = sp.scope
    AND sos.team_id = sp.team_id
  LEFT JOIN last10 AS l10
    ON l10.season = sp.season
    AND l10.scope = sp.scope
    AND l10.team_id = sp.team_id
  LEFT JOIN ap_rank_last AS ap
    ON ap.season = sp.season
    AND ap.scope = sp.scope
    AND ap.team_id = sp.team_id
  LEFT JOIN experience AS ex
    ON ex.season = sp.season
    AND ex.scope = sp.scope
    AND ex.team_id = sp.team_id
  LEFT JOIN {{ ref('f_roster_continuity') }} AS rc
    ON rc.season = sp.season
    AND rc.team_id = sp.team_id
  LEFT JOIN program_5y AS p5
    ON p5.season = sp.season
    AND p5.team_id = sp.team_id
)

SELECT
  season,
  season_label,
  scope,
  team_id,
  market,
  alias,
  conf_alias,
  games,
  wins,
  losses,
  win_pct,
  d1_games,
  tempo,
  raw_oe,
  raw_de,
  raw_net,
  adj_oe,
  adj_de,
  adj_net,
  sos_adj_net,
  efg_pct,
  tov_pct,
  orb_pct,
  ftr,
  opp_efg_pct,
  opp_tov_pct,
  drb_pct,
  opp_ftr,
  three_par,
  three_pct,
  ft_pct,
  last10_net,
  ap_rank_last,
  experience_index,
  ret_min_share,
  ret_pts_share,
  ret_basis,
  program_win_pct_5y,
  RANK() OVER (
    PARTITION BY season, scope
    ORDER BY adj_net DESC
  ) AS rank_adj_net,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY adj_oe ASC
  ) AS pctl_adj_oe,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY adj_de DESC
  ) AS pctl_adj_de,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY adj_net ASC
  ) AS pctl_adj_net,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY tempo ASC
  ) AS pctl_tempo,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY efg_pct ASC
  ) AS pctl_efg_pct,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY tov_pct DESC
  ) AS pctl_tov_pct,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY orb_pct ASC
  ) AS pctl_orb_pct,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY ftr ASC
  ) AS pctl_ftr,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY three_par ASC
  ) AS pctl_three_par,
  PERCENT_RANK() OVER (
    PARTITION BY season, scope
    ORDER BY opp_efg_pct DESC
  ) AS pctl_opp_efg_pct
FROM assembled
