{{ config(materialized='table') }}

-- Grain: one row per team, projected 2018-19 strength from 2017-18 inputs. Owner: ML2 (task T10).
-- 2017-18 returning shares are class-based and overstate returns: shift them down by the average gap between
-- the class estimate (2017) and observed returning shares (2014-2016) before projecting.
WITH proxy_shift AS (
  SELECT
    AVG(IF(season = {{ var('last_season') }}, ret_min_share, NULL))
      - AVG(IF(season < {{ var('last_season') }}, ret_min_share, NULL)) AS min_shift,
    AVG(IF(season = {{ var('last_season') }}, ret_pts_share, NULL))
      - AVG(IF(season < {{ var('last_season') }}, ret_pts_share, NULL)) AS pts_shift
  FROM {{ ref('f_roster_continuity') }}
),

inputs AS (
  SELECT
    cur.team_id,
    cur.market,
    cur.alias,
    cur.conf_alias,
    cur.adj_net,
    prev.adj_net AS prior_adj_net,
    cur.ret_min_share AS ret_min_share_class_proxy,
    LEAST(GREATEST(cur.ret_min_share - ps.min_shift, 0), 1) AS ret_min_share,
    LEAST(GREATEST(cur.ret_pts_share - ps.pts_shift, 0), 1) AS ret_pts_share,
    cur.conference_strength
  FROM {{ ref('f_team_season') }} AS cur
  LEFT JOIN {{ ref('f_team_season') }} AS prev
    ON prev.team_id = cur.team_id
    AND prev.season = cur.season - 1
    AND prev.scope = 'full'
  CROSS JOIN proxy_shift AS ps
  WHERE cur.season = {{ var('last_season') }}
    AND cur.scope = 'full'
),

projected AS (
  SELECT
    p.*,
    e.rmse
  FROM ML.PREDICT(
    MODEL `{{ this.database }}.{{ this.schema }}.m_next_season`,
    (SELECT * FROM inputs)
  ) AS p
  CROSS JOIN {{ ref('m_next_season_eval') }} AS e
)

SELECT
  {{ var('forecast_season') }} AS season,
  {{ season_label(var('forecast_season')) }} AS season_label,
  {{ var('last_season') }} AS based_on_season,
  team_id,
  market,
  alias,
  conf_alias,
  adj_net AS current_adj_net,
  prior_adj_net,
  ret_min_share_class_proxy,
  ret_min_share,
  ret_pts_share,
  conference_strength,
  predicted_next_adj_net AS projected_adj_net,
  predicted_next_adj_net - 1.2816 * rmse AS projected_low,
  predicted_next_adj_net + 1.2816 * rmse AS projected_high,
  RANK() OVER (ORDER BY predicted_next_adj_net DESC) AS projected_rank
FROM projected
