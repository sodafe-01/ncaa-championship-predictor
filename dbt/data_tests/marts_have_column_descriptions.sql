-- depends_on: {{ ref('mart_team_profile') }}
-- depends_on: {{ ref('mart_conference_season') }}
-- depends_on: {{ ref('mart_league_season') }}
-- Every mart column must carry a description (persist_docs copies YAML descriptions to BigQuery)
SELECT table_name, column_name
FROM `{{ target.project }}.{{ target.dataset }}`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE STARTS_WITH(table_name, 'mart_')
  AND (description IS NULL OR TRIM(description) = '')
