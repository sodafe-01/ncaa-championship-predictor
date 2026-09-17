-- Each scenario's title odds sum to 1 (within 0.01) and each round's odds sum to the number of teams in it
WITH totals AS (
  SELECT
    scenario,
    SUM(p_r64) AS r64,
    SUM(p_r32) AS r32,
    SUM(p_s16) AS s16,
    SUM(p_e8) AS e8,
    SUM(p_f4) AS f4,
    SUM(p_final) AS final_round,
    SUM(p_champ) AS champ
  FROM {{ ref('sim_results') }}
  GROUP BY scenario
)
SELECT *
FROM totals
WHERE ABS(champ - 1) > 0.01
   OR ABS(r64 - 64) > 1e-6
   OR ABS(r32 - 32) > 1e-6
   OR ABS(s16 - 16) > 1e-6
   OR ABS(e8 - 8) > 1e-6
   OR ABS(f4 - 4) > 1e-6
   OR ABS(final_round - 2) > 1e-6
