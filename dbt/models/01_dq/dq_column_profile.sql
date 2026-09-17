-- Grain: one row per scanned table x column, latest Knowledge Catalog profile scan. Owner: DE1 (story DE-04).
-- percent_null / percent_unique keep the scan's 0-100 scale; sample_fraction shows mbb_pbp_sr was sampled.
WITH latest_scan AS (
  SELECT
    s.data_source.table_id AS table_name,
    s.column_name,
    s.column_type,
    s.column_mode,
    s.percent_null,
    s.percent_unique,
    s.min_value,
    s.max_value,
    s.average_value,
    s.standard_deviation,
    s.quartile_lower,
    s.quartile_median,
    s.quartile_upper,
    s.top_n,
    s.job_rows_scanned,
    s.job_start_time
  FROM {{ source('ncaa_scans', 'ncaa_basketball_20_sample_scans') }} AS s
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY s.data_source.table_id, s.column_name
    ORDER BY s.job_start_time DESC
  ) = 1
)

SELECT
  l.table_name,
  l.column_name,
  l.column_type,
  l.column_mode,
  l.percent_null,
  l.percent_unique,
  l.min_value,
  l.max_value,
  l.average_value,
  l.standard_deviation,
  l.quartile_lower,
  l.quartile_median,
  l.quartile_upper,
  l.top_n AS top_values,
  l.job_rows_scanned AS rows_scanned,
  t.row_count AS table_row_count,
  SAFE_DIVIDE(l.job_rows_scanned, t.row_count) AS sample_fraction,
  l.job_start_time AS scanned_at,
  l.percent_null > 50 AS is_high_null
FROM latest_scan AS l
LEFT JOIN {{ source('ncaa_basketball', 'tables_meta') }} AS t ON t.table_id = l.table_name
