-- For tournaments 2014-2017, the historical champion equals the winner of the Sportradar final
SELECT t.tournament_year, t.team_id AS historical_champion, g.winner_team_id AS sportradar_champion
FROM {{ ref('stg_tournament_teams') }} t
JOIN {{ ref('stg_games') }} g ON g.season = t.season AND g.ncaa_round = 'FINAL'
WHERE t.is_champion AND t.team_id IS DISTINCT FROM g.winner_team_id
