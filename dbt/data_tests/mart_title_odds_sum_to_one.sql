-- Title odds in each scenario sum to 1 (within 0.01)
SELECT scenario, SUM(p_champion) AS total_p_champion
FROM {{ ref('mart_title_odds') }}
GROUP BY scenario
HAVING ABS(SUM(p_champion) - 1) > 0.01
