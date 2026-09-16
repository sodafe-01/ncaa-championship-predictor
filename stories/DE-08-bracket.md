# DE-08 — Brackets: `stg_bracket`

**Lane:** DE1 · **Depends on:** DE-01, DE-03 · **Unblocks:** ML2's simulation over real brackets; ML2's projected 2018-19 bracket reuses this exact shape · **Task:** T3

## Goal

Rebuild each season's 67-game NCAA bracket as a tree of slots, so the simulator can play it round by round and backtests can compare with what really happened. The data has no bracket table and no 2018 seeds, so the tree comes from the real results.

## Files you own

- `models/00_stg/stg_bracket.sql` (put `{{ config(materialized='table') }}` at the top; the joins are too heavy for a view)
- `models/00_stg/_stg_bracket.yml`
- `data_tests/stg_bracket_consistency.sql`

## Inputs

`ref('stg_games')` (NCAA games with `ncaa_round`, `ncaa_region`, home/away ids and `winner_team_id`), `ref('stg_tournament_teams')` (seeds for 2013–2016).

## Output contract (shared with ML2's projected bracket)

Grain: `season` × `slot_id`. 67 slots per season, 2013–2017.

| Column | Type | Rule |
|---|---|---|
| season | INT64 | |
| season_label | STRING | |
| slot_id | STRING | `FF1`–`FF4`; `{REGION}_R64_1`–`8`; `{REGION}_R32_1`–`4`; `{REGION}_S16_1`–`2`; `{REGION}_E8`; `F4_1`, `F4_2`; `FINAL`. REGION = EAST, WEST, SOUTH, MIDWEST |
| ncaa_round | STRING | FF … FINAL |
| ncaa_round_order | INT64 | 0 … 6 |
| region | STRING | NULL for F4 and FINAL; for FF, the region of the R64 slot it feeds |
| next_slot_id | STRING | where the winner goes; NULL for FINAL |
| next_slot_side | STRING | 'a' or 'b': the side of `next_slot_id` the winner fills |
| side_a_team_id | STRING | team placed directly (R64 and FF only); NULL when side a is fed by another slot |
| side_a_from_slot | STRING | slot whose winner fills side a; NULL for a directly placed team |
| side_b_team_id, side_b_from_slot | STRING | same for side b |
| side_a_seed, side_b_seed | INT64 | seeds of directly placed teams from `stg_tournament_teams` (2013–2016); NULL for 2017-18 |
| game_id | STRING | the real game |
| actual_team_a_id, actual_team_b_id | STRING | who really played, aligned to the sides |
| actual_winner_team_id | STRING | |

Exactly one of `side_x_team_id` and `side_x_from_slot` is set on each side.

## How to build it (top-down from the final, using real results)

1. **FINAL:** side a = home team, side b = away team.
2. **F4:** the semifinal won by FINAL's side-a team is `F4_1` (`next_slot_side = 'a'`); the other is `F4_2` (`'b'`).
3. **E8:** for each F4 slot, the Elite Eight game won by its side-a team feeds side a, the other feeds side b. `slot_id = {REGION}_E8`.
4. **S16, within the region:** the Sweet 16 game won by the E8 slot's side-a team is `{REGION}_S16_1` (side a); the other is `_S16_2` (side b).
5. **R32:** `S16_n` side a ← `R32_(2n−1)`, side b ← `R32_(2n)`, matched by winners.
6. **R64:** `R32_n` side a ← `R64_(2n−1)`, side b ← `R64_(2n)`, matched by winners. Inside an R64 slot, side a = the home team.
7. **First Four:** if one R64 team won a First Four game that season, that side gets `side_x_team_id = NULL` and `side_x_from_slot` = that FF slot. Number the FF slots `FF1`–`FF4` by the R64 slot they feed (region order EAST, WEST, SOUTH, MIDWEST, then slot number). Inside an FF slot, side a = the home team.
8. **Seeds:** join `stg_tournament_teams` on (`season`, `team_id`) for directly placed teams.
9. **Actual teams:** for a fed side, the actual team is the winner of its from-slot.

A practical SQL shape: first map each NCAA `game_id` to its `slot_id` round by round (steps 1–7), then derive sides and feeders by joining the slot map to itself on winners.

## Tests first

`models/00_stg/_stg_bracket.yml` (describe every column):

```yaml
version: 2
models:
  - name: stg_bracket
    data_tests:
      - unique_combination_of_columns: {arguments: {combination_of_columns: [season, slot_id]}}
      - row_count_between: {arguments: {min_count: 67, max_count: 67, group_by: [season]}}
      - expression_is_true: {arguments: {expression: "next_slot_id IS NOT NULL", where: "ncaa_round != 'FINAL'"}}
      - expression_is_true:
          arguments: {expression: "(side_a_team_id IS NULL) != (side_a_from_slot IS NULL) AND (side_b_team_id IS NULL) != (side_b_from_slot IS NULL)"}
      - expression_is_true:
          arguments: {expression: "side_a_from_slot IS NULL AND side_b_from_slot IS NULL", where: "ncaa_round = 'FF'"}
      - expression_is_true:
          arguments: {expression: "side_a_from_slot IS NOT NULL AND side_b_from_slot IS NOT NULL", where: "ncaa_round_order >= 2"}
      - expression_is_true:
          arguments: {expression: "side_a_seed + side_b_seed = 17", where: "ncaa_round = 'R64' AND side_a_seed IS NOT NULL AND side_b_seed IS NOT NULL"}
    columns:
      - name: next_slot_side
        data_tests:
          - accepted_values: {arguments: {values: ['a', 'b']}}
```

`data_tests/stg_bracket_consistency.sql`:

```sql
-- One row per violation of the bracket's structure
WITH b AS (SELECT * FROM {{ ref('stg_bracket') }}),
side_feed AS (
  SELECT p.season, p.slot_id, p.actual_team_a_id AS actual_team, f.actual_winner_team_id AS feeder_winner
  FROM b p JOIN b f ON f.season = p.season AND f.slot_id = p.side_a_from_slot
  UNION ALL
  SELECT p.season, p.slot_id, p.actual_team_b_id, f.actual_winner_team_id
  FROM b p JOIN b f ON f.season = p.season AND f.slot_id = p.side_b_from_slot
),
direct_teams AS (
  SELECT b.season, team_id
  FROM b, UNNEST([b.side_a_team_id, b.side_b_team_id]) AS team_id
  WHERE team_id IS NOT NULL
)
SELECT 'side team is not the winner of its feeder slot' AS failed_check, season, slot_id AS detail
FROM side_feed WHERE actual_team IS DISTINCT FROM feeder_winner
UNION ALL
SELECT 'not 68 directly placed teams', season, CAST(COUNT(DISTINCT team_id) AS STRING)
FROM direct_teams GROUP BY season HAVING COUNT(DISTINCT team_id) != 68
UNION ALL
SELECT 'not 4 First Four winners feeding the round of 64', season,
  CAST(COUNTIF(side_a_from_slot LIKE 'FF%') + COUNTIF(side_b_from_slot LIKE 'FF%') AS STRING)
FROM b WHERE ncaa_round = 'R64' GROUP BY season
HAVING COUNTIF(side_a_from_slot LIKE 'FF%') + COUNTIF(side_b_from_slot LIKE 'FF%') != 4
UNION ALL
SELECT 'bracket champion differs from the real final', b.season, b.actual_winner_team_id
FROM b JOIN {{ ref('stg_games') }} g ON g.season = b.season AND g.ncaa_round = 'FINAL'
WHERE b.slot_id = 'FINAL' AND b.actual_winner_team_id IS DISTINCT FROM g.winner_team_id
```

## Done when

```bash
scripts/dbt.sh build --select stg_bracket
scripts/verify.sh
```

## Report back

- Slots per season.
- The 2017-18 champion's path: slot ids from R64 to FINAL.
- Result of the seed-sum check for 2013–2016.

## Out of scope

The projected 2018-19 field and bracket (ML2, T10), which reuse this shape.
