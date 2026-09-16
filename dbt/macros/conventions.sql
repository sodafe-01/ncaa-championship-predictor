{# Shared labeling and metric expressions. Pass SQL snippets as strings. #}

{% macro season_label(season_expr) %}
CONCAT(CAST({{ season_expr }} AS STRING), '-', SUBSTR(CAST(({{ season_expr }}) + 1 AS STRING), 3, 2))
{% endmacro %}

{% macro postseason_kind(tournament_expr, tournament_type_expr) %}
CASE
  WHEN {{ tournament_expr }} IS NULL THEN 'REG'
  WHEN {{ tournament_expr }} = 'Conference' THEN 'CONF'
  WHEN UPPER({{ tournament_type_expr }}) = 'CIT' THEN 'CIT'
  WHEN UPPER({{ tournament_type_expr }}) = 'CBI' THEN 'CBI'
  WHEN {{ tournament_type_expr }} = 'NIT'
    OR (
      {{ tournament_type_expr }} LIKE '%Bracket'
      AND {{ tournament_type_expr }} NOT LIKE '%Regional%'
    )
    THEN 'NIT'
  WHEN {{ tournament_type_expr }} IN (
    'East Regional',
    'West Regional',
    'South Regional',
    'Midwest Regional',
    'First Four',
    'Final Four',
    'National Championship'
  ) THEN 'NCAA'
  ELSE 'OTHER'
END
{% endmacro %}

{% macro ncaa_round(season_expr, tournament_type_expr, tournament_round_expr) %}
CASE
  WHEN {{ tournament_type_expr }} = 'First Four' THEN 'FF'
  WHEN {{ tournament_type_expr }} = 'National Championship' THEN 'FINAL'
  WHEN {{ tournament_type_expr }} = 'Final Four' THEN 'F4'
  WHEN {{ tournament_type_expr }} IN (
    'East Regional', 'West Regional', 'South Regional', 'Midwest Regional'
  ) THEN
    CASE
      WHEN {{ tournament_round_expr }} IN ('Sweet 16') THEN 'S16'
      WHEN {{ tournament_round_expr }} IN ('Elite 8', 'Elite Eight') THEN 'E8'
      WHEN ({{ season_expr }}) <= 2014 AND {{ tournament_round_expr }} = 'Second Round' THEN 'R64'
      WHEN ({{ season_expr }}) <= 2014 AND {{ tournament_round_expr }} = 'Third Round' THEN 'R32'
      WHEN ({{ season_expr }}) >= 2015 AND {{ tournament_round_expr }} = 'First Round' THEN 'R64'
      WHEN ({{ season_expr }}) >= 2015 AND {{ tournament_round_expr }} = 'Second Round' THEN 'R32'
    END
END
{% endmacro %}

{% macro ncaa_round_order(ncaa_round_expr) %}
CASE {{ ncaa_round_expr }}
  WHEN 'FF' THEN 0
  WHEN 'R64' THEN 1
  WHEN 'R32' THEN 2
  WHEN 'S16' THEN 3
  WHEN 'E8' THEN 4
  WHEN 'F4' THEN 5
  WHEN 'FINAL' THEN 6
END
{% endmacro %}

{% macro ncaa_region(tournament_type_expr) %}
CASE {{ tournament_type_expr }}
  WHEN 'East Regional' THEN 'EAST'
  WHEN 'West Regional' THEN 'WEST'
  WHEN 'South Regional' THEN 'SOUTH'
  WHEN 'Midwest Regional' THEN 'MIDWEST'
END
{% endmacro %}

{% macro hist_round_to_ncaa_round(round_expr) %}
CASE {{ round_expr }}
  WHEN 68 THEN 'FF'
  WHEN 64 THEN 'R64'
  WHEN 32 THEN 'R32'
  WHEN 16 THEN 'S16'
  WHEN 8 THEN 'E8'
  WHEN 4 THEN 'F4'
  WHEN 2 THEN 'FINAL'
END
{% endmacro %}

{% macro possessions(fga_expr, orb_expr, tov_expr, fta_expr) %}
({{ fga_expr }}) - ({{ orb_expr }}) + ({{ tov_expr }}) + 0.44 * ({{ fta_expr }})
{% endmacro %}

{% macro class_rank(class_expr) %}
CASE UPPER({{ class_expr }})
  WHEN 'FR' THEN 1
  WHEN 'SO' THEN 2
  WHEN 'JR' THEN 3
  WHEN 'SR' THEN 4
  WHEN 'GR' THEN 5
END
{% endmacro %}
