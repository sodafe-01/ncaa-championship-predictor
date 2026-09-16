{% test unique_combination_of_columns(model, combination_of_columns) %}
SELECT
  {{ combination_of_columns | join(', ') }}
FROM {{ model }}
GROUP BY {{ combination_of_columns | join(', ') }}
HAVING COUNT(*) > 1
{% endtest %}

{% test expression_is_true(model, expression, where=None) %}
SELECT *
FROM {{ model }}
WHERE NOT ({{ expression }})
{%- if where %}
  AND ({{ where }})
{%- endif %}
{% endtest %}

{% test row_count_between(model, min_count, max_count, group_by=None, where=None) %}
WITH counted AS (
  SELECT
    {%- if group_by %}
    {{ group_by | join(', ') }},
    {%- endif %}
    COUNT(*) AS n
  FROM {{ model }}
  {%- if where %}
  WHERE {{ where }}
  {%- endif %}
  {%- if group_by %}
  GROUP BY {{ group_by | join(', ') }}
  {%- endif %}
)
SELECT *
FROM counted
WHERE n < {{ min_count }} OR n > {{ max_count }}
{% endtest %}

{% test accepted_range(model, column_name, min_value, max_value, where=None) %}
SELECT *
FROM {{ model }}
WHERE {{ column_name }} IS NOT NULL
  AND (
    {{ column_name }} < {{ min_value }}
    OR {{ column_name }} > {{ max_value }}
  )
{%- if where %}
  AND ({{ where }})
{%- endif %}
{% endtest %}
