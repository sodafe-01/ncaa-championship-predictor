-- At least 95% of teams in each core tournament have a pre-NCAA feature row.
-- Widen the season filter to 2017 when the March 2018 backtest extension is attempted.
WITH participants AS (
  SELECT g.season, team_id
  FROM {{ ref('stg_games') }} g,
    UNNEST([g.home_team_id, g.away_team_id]) AS team_id
  WHERE g.postseason_kind = 'NCAA' AND g.season BETWEEN 2014 AND 2016
  GROUP BY g.season, team_id
), coverage AS (
  SELECT p.season, COUNT(*) AS participants, COUNTIF(f.team_id IS NOT NULL) AS matched
  FROM participants p
  LEFT JOIN {{ ref('f_team_season') }} f
    ON f.season = p.season AND f.team_id = p.team_id AND f.scope = 'pre_ncaa'
  GROUP BY p.season
)
SELECT season, participants, matched, SAFE_DIVIDE(matched, participants) AS join_rate
FROM coverage
WHERE SAFE_DIVIDE(matched, participants) < 0.95
