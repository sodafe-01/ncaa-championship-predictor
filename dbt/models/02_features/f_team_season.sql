{{
  config(materialized="table")
}}

-- Grain: one row per season × scope × D1 team, model-ready seasons only. Owner: DE2 (stories DE-02, DE-07).
-- Record columns: every closed game with a result (DE-02 logic). Efficiency columns: valid rows of
-- f_team_game_efficiency, neutralized for home court, then 10 passes of opponent adjustment.

WITH scopes AS (
  SELECT 'pre_ncaa' AS scope
  UNION ALL
  SELECT 'full' AS scope
),

model_seasons AS (
  SELECT season
  FROM {{ ref('dq_season_gate') }}
  WHERE model_ready
),

ncaa_openers AS (
  SELECT
    season,
    MIN(scheduled_date) AS first_ncaa_date
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA'
  GROUP BY season
),

d1_teams AS (
  SELECT
    tg.season,
    tg.team_id,
    MIN(tg.market) AS market,
    MIN(tg.alias) AS alias
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN model_seasons AS ms
    ON ms.season = tg.season
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

-- Record (DE-02) --------------------------------------------------------------------------------

scoped_games AS (
  SELECT
    tg.season,
    sc.scope,
    tg.game_id,
    tg.scheduled_date,
    tg.team_id,
    tg.conf_alias,
    tg.win
  FROM {{ ref('stg_team_games') }} AS tg
  INNER JOIN model_seasons AS ms
    ON ms.season = tg.season
  INNER JOIN ncaa_openers AS n
    ON n.season = tg.season
  CROSS JOIN scopes AS sc
  WHERE tg.is_closed
    AND tg.division_alias = 'D1'
    AND (
      sc.scope = 'full'
      OR tg.scheduled_date < n.first_ncaa_date
    )
),

record_games AS (
  SELECT
    season,
    scope,
    team_id,
    win
  FROM scoped_games
  WHERE win IS NOT NULL
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
    FROM scoped_games
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
    COUNTIF(NOT win) AS losses
  FROM record_games
  GROUP BY season, scope, team_id
),

-- AP rank on the team's side of its last closed game in scope
ap_last AS (
  SELECT
    season,
    scope,
    team_id,
    ap_rank AS ap_rank_last
  FROM (
    SELECT
      sg.season,
      sg.scope,
      sg.team_id,
      IF(sg.team_id = g.home_team_id, g.home_ap_rank, g.away_ap_rank) AS ap_rank,
      ROW_NUMBER() OVER (
        PARTITION BY sg.season, sg.scope, sg.team_id
        ORDER BY sg.scheduled_date DESC, g.gametime DESC, sg.game_id DESC
      ) AS rn
    FROM scoped_games AS sg
    INNER JOIN {{ ref('stg_games') }} AS g
      ON g.game_id = sg.game_id
  )
  WHERE rn = 1
),

-- Efficiency (DE-07) ----------------------------------------------------------------------------

eff_rows AS (
  SELECT
    e.season,
    sc.scope,
    e.game_id,
    e.team_id,
    e.opp_id,
    e.venue_type,
    e.game_seq,
    e.points,
    e.opp_points,
    e.game_poss,
    e.oe,
    e.de,
    e.fgm,
    e.fga,
    e.tpm,
    e.tpa,
    e.ftm,
    e.fta,
    e.orb,
    e.drb,
    e.tov,
    e.opp_fgm,
    e.opp_fga,
    e.opp_tpm,
    e.opp_fta,
    e.opp_orb,
    e.opp_drb,
    e.opp_tov
  FROM {{ ref('f_team_game_efficiency') }} AS e
  INNER JOIN model_seasons AS ms
    ON ms.season = e.season
  CROSS JOIN scopes AS sc
  WHERE e.is_valid_efficiency_row
    AND (sc.scope = 'full' OR e.in_pre_ncaa_scope)
),

season_sums AS (
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
  FROM eff_rows
  GROUP BY season, scope, team_id
),

-- lg = league average oe; hca = home-court factor from non-neutral rows
league AS (
  SELECT
    season,
    scope,
    AVG(oe) AS lg,
    SQRT(
      SAFE_DIVIDE(
        AVG(IF(venue_type = 'home', oe, NULL)),
        AVG(IF(venue_type = 'away', oe, NULL))
      )
    ) - 1 AS hca
  FROM eff_rows
  GROUP BY season, scope
),

neutral_rows AS (
  SELECT
    r.season,
    r.scope,
    r.team_id,
    r.opp_id,
    r.game_poss,
    l.lg,
    CASE r.venue_type
      WHEN 'home' THEN SAFE_DIVIDE(r.oe, 1 + l.hca)
      WHEN 'away' THEN r.oe * (1 + l.hca)
      ELSE r.oe
    END AS oe_n,
    CASE r.venue_type
      WHEN 'home' THEN r.de * (1 + l.hca)
      WHEN 'away' THEN SAFE_DIVIDE(r.de, 1 + l.hca)
      ELSE r.de
    END AS de_n
  FROM eff_rows AS r
  INNER JOIN league AS l
    ON l.season = r.season
    AND l.scope = r.scope
),

adj_0 AS (
  SELECT
    season,
    scope,
    team_id,
    AVG(oe_n) AS adj_oe,
    AVG(de_n) AS adj_de
  FROM neutral_rows
  GROUP BY season, scope, team_id
),

{% for k in range(1, 11) %}
-- Pass {{ k }}: each game's efficiency against the opponent's pass-{{ k - 1 }} rating, possession-weighted
adj_{{ k }}_raw AS (
  SELECT
    n.season,
    n.scope,
    n.team_id,
    ANY_VALUE(n.lg) AS lg,
    SAFE_DIVIDE(
      SUM(SAFE_DIVIDE(n.game_poss * n.oe_n * n.lg, o.adj_de)),
      SUM(n.game_poss)
    ) AS adj_oe,
    SAFE_DIVIDE(
      SUM(SAFE_DIVIDE(n.game_poss * n.de_n * n.lg, o.adj_oe)),
      SUM(n.game_poss)
    ) AS adj_de
  FROM neutral_rows AS n
  INNER JOIN adj_{{ k - 1 }} AS o
    ON o.season = n.season
    AND o.scope = n.scope
    AND o.team_id = n.opp_id
  GROUP BY n.season, n.scope, n.team_id
),

-- Rescale so the team averages of adj_oe and adj_de both equal the league average
adj_{{ k }} AS (
  SELECT
    season,
    scope,
    team_id,
    SAFE_DIVIDE(adj_oe * lg, AVG(adj_oe) OVER (PARTITION BY season, scope)) AS adj_oe,
    SAFE_DIVIDE(adj_de * lg, AVG(adj_de) OVER (PARTITION BY season, scope)) AS adj_de
  FROM adj_{{ k }}_raw
),

{% endfor %}
final_adj AS (
  SELECT
    season,
    scope,
    team_id,
    adj_oe,
    adj_de,
    adj_oe - adj_de AS adj_net
  FROM adj_10
),

sos AS (
  SELECT
    r.season,
    r.scope,
    r.team_id,
    AVG(o.adj_net) AS sos_adj_net
  FROM eff_rows AS r
  INNER JOIN final_adj AS o
    ON o.season = r.season
    AND o.scope = r.scope
    AND o.team_id = r.opp_id
  GROUP BY r.season, r.scope, r.team_id
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
      ) AS rn
    FROM eff_rows
  )
  WHERE rn <= 10
  GROUP BY season, scope, team_id
),

-- Roster and program (DE-06, history) -----------------------------------------------------------

-- Class exists only where the gate marks it usable (2017-18)
experience AS (
  SELECT
    p.season,
    sc.scope,
    p.team_id,
    SAFE_DIVIDE(SUM(p.class_rank * p.minutes), SUM(p.minutes)) AS experience_index
  FROM {{ ref('stg_player_games') }} AS p
  INNER JOIN {{ ref('dq_season_gate') }} AS q
    ON q.season = p.season
    AND q.model_ready
    AND q.class_usable
  INNER JOIN ncaa_openers AS n
    ON n.season = p.season
  CROSS JOIN scopes AS sc
  WHERE p.played
    AND p.is_closed
    AND p.class_rank IS NOT NULL
    AND p.minutes IS NOT NULL
    AND (sc.scope = 'full' OR p.scheduled_date < n.first_ncaa_date)
  GROUP BY p.season, sc.scope, p.team_id
),

program AS (
  SELECT
    t.season,
    t.team_id,
    SAFE_DIVIDE(SUM(h.wins), SUM(h.wins + h.losses)) AS program_win_pct_5y
  FROM d1_teams AS t
  INNER JOIN {{ ref('stg_team_season_history') }} AS h
    ON h.team_id = t.team_id
    AND h.season BETWEEN t.season - 5 AND t.season - 1
  GROUP BY t.season, t.team_id
),

-- Assemble --------------------------------------------------------------------------------------

report AS (
  SELECT
    sp.season,
    sp.scope,
    sp.team_id,
    sp.market,
    sp.alias,
    cm.conf_alias,
    COALESCE(a.games, 0) AS games,
    COALESCE(a.wins, 0) AS wins,
    COALESCE(a.losses, 0) AS losses,
    SAFE_DIVIDE(a.wins, a.games) AS win_pct,
    ss.d1_games,
    ss.tempo,
    ss.raw_oe,
    ss.raw_de,
    ss.raw_oe - ss.raw_de AS raw_net,
    fa.adj_oe,
    fa.adj_de,
    fa.adj_net,
    so.sos_adj_net,
    ss.efg_pct,
    ss.tov_pct,
    ss.orb_pct,
    ss.ftr,
    ss.opp_efg_pct,
    ss.opp_tov_pct,
    ss.drb_pct,
    ss.opp_ftr,
    ss.three_par,
    ss.three_pct,
    ss.ft_pct,
    l10.last10_net,
    ap.ap_rank_last,
    ex.experience_index,
    rc.ret_min_share,
    rc.ret_pts_share,
    rc.ret_basis,
    pg.program_win_pct_5y
  FROM spine AS sp
  LEFT JOIN agg AS a
    ON a.season = sp.season AND a.scope = sp.scope AND a.team_id = sp.team_id
  LEFT JOIN conf_mode AS cm
    ON cm.season = sp.season AND cm.scope = sp.scope AND cm.team_id = sp.team_id
  LEFT JOIN season_sums AS ss
    ON ss.season = sp.season AND ss.scope = sp.scope AND ss.team_id = sp.team_id
  LEFT JOIN final_adj AS fa
    ON fa.season = sp.season AND fa.scope = sp.scope AND fa.team_id = sp.team_id
  LEFT JOIN sos AS so
    ON so.season = sp.season AND so.scope = sp.scope AND so.team_id = sp.team_id
  LEFT JOIN last10 AS l10
    ON l10.season = sp.season AND l10.scope = sp.scope AND l10.team_id = sp.team_id
  LEFT JOIN ap_last AS ap
    ON ap.season = sp.season AND ap.scope = sp.scope AND ap.team_id = sp.team_id
  LEFT JOIN experience AS ex
    ON ex.season = sp.season AND ex.scope = sp.scope AND ex.team_id = sp.team_id
  LEFT JOIN {{ ref('f_roster_continuity') }} AS rc
    ON rc.season = sp.season AND rc.team_id = sp.team_id
  LEFT JOIN program AS pg
    ON pg.season = sp.season AND pg.team_id = sp.team_id
)

-- final select: contract column order (DE-02)
SELECT
  season,
  {{ season_label('season') }} AS season_label,
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
  AVG(adj_net) OVER (PARTITION BY season, scope, conf_alias) AS conference_strength,
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
  RANK() OVER (PARTITION BY season, scope ORDER BY adj_net DESC) AS rank_adj_net,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY adj_oe) AS pctl_adj_oe,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY adj_de DESC) AS pctl_adj_de,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY adj_net) AS pctl_adj_net,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY tempo) AS pctl_tempo,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY efg_pct) AS pctl_efg_pct,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY tov_pct DESC) AS pctl_tov_pct,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY orb_pct) AS pctl_orb_pct,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY ftr) AS pctl_ftr,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY three_par) AS pctl_three_par,
  PERCENT_RANK() OVER (PARTITION BY season, scope ORDER BY opp_efg_pct DESC) AS pctl_opp_efg_pct
FROM report
