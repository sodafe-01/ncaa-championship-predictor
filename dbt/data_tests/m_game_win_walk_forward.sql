-- Every walk-forward training window (the filter the m_game_win_* pre-hooks use) ends before that
-- season's first NCAA tournament game, so no backtest model sees its own tournament.
{% for s in [2014, 2015, 2016, 2017] %}
SELECT {{ s }} AS backtest_season, MAX(m.scheduled_date) AS last_training_date, ANY_VALUE(n.first_ncaa_date) AS first_ncaa_date
FROM {{ ref('f_matchups') }} AS m
CROSS JOIN (
  SELECT MIN(scheduled_date) AS first_ncaa_date
  FROM {{ ref('stg_games') }}
  WHERE postseason_kind = 'NCAA' AND season = {{ s }}
) AS n
WHERE m.season < {{ s }} OR (m.season = {{ s }} AND m.is_training_row)
HAVING MAX(m.scheduled_date) >= ANY_VALUE(n.first_ncaa_date)
{% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
