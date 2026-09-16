-- OPTIONAL: AI.GENERATE scouting narratives grounded in real team features.
-- Requires a BigQuery -> Vertex AI connection. Set __CONNECTION__ (e.g.
-- "projects/da-hackathon-2026/locations/us/connections/vertex_ai") before running.
-- Not deployed by CI automatically; run manually once the connection exists:
--   PROJECT=... DATASET=... CONNECTION=... bash bq/deploy.sh bq/sql/05_v_team_scouting.sql
CREATE OR REPLACE VIEW `__PROJECT__.__DATASET__.v_team_scouting` AS
SELECT
  p.season,
  p.team_id,
  p.market,
  p.name,
  p.champion_probability,
  AI.GENERATE(
    prompt => FORMAT(
      "You are an NCAA basketball scout. In 2-3 sentences, give the strength, weakness, and X-factor for %s %s. Championship probability: %.1f%%. Ground the summary only in these facts and do not invent statistics.",
      p.market, p.name, p.champion_probability * 100
    ),
    connection_id => '__CONNECTION__',
    endpoint => 'gemini-2.0-flash'
  ).result AS scouting_summary
FROM `__PROJECT__.__DATASET__.v_champion_probabilities` AS p;
