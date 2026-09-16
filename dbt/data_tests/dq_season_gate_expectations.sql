-- Verified expectations: 2013-14 unusable (box scores 66% missing); 2014-15..2017-18 model-ready; class only in 2017-18
SELECT season, stats_usable, class_usable, ncaa_complete, model_ready
FROM {{ ref('dq_season_gate') }}
WHERE NOT ncaa_complete
   OR (season = 2013 AND (stats_usable OR model_ready))
   OR (season BETWEEN 2014 AND 2017 AND NOT model_ready)
   OR (season < 2017 AND class_usable)
   OR (season = 2017 AND NOT class_usable)
