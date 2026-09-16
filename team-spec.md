# Our game plan, explained simply

**66degrees NCAA AI Hackathon · team texas_longhorns · 6 people**

The NCAA "hired" us as its new data team. They want to know what's strong in the league, what's weak, and who wins the next championship, backed by data and built with Google's AI tools. Here's what we're building, who does what, how we build it, how we start, and what we hand the judges.

| Data ends  | "Next champion" means | We build in                 | We deliver                                   |
| ---------- | --------------------- | --------------------------- | -------------------------------------------- |
| April 2018 | The 2018-19 season    | BigQuery, `texas_longhorns` | Dashboard, chat assistant, 5-10 min briefing |

---

## The big idea: a forecast, not a guess

Think of a weather forecast. Nobody knows for sure whether it will rain tomorrow, but "70% chance of rain" is still useful. We'll do the same for basketball. Instead of shouting one team's name, we'll say something like "Team X wins it all 18% of the time, and here's why."

Our data stops in April 2018, right after Villanova won the title. So we pretend it's that spring and answer the question the front office would ask: **who wins next season's title, the 2018-19 championship?**

## Why we can't just pick the best team

| Season  | Champion  | Rank right before its tournament |
| ------- | --------- | -------------------------------- |
| 2013-14 | UConn     | **#17**                          |
| 2014-15 | Duke      | **#8**                           |
| 2015-16 | Villanova | **#4**                           |
| 2016-17 | UNC       | **#18**                          |
| 2017-18 | Villanova | **#3**                           |

_Where each champion in our data ranked right before its tournament, out of about 350 teams, by how many more points it scored than it allowed per 100 trips down the court._

The best team usually doesn't win. Lose one bad night and you're out. Even #1 seeds won only 20 of the 33 titles from 1985 to 2017.

So the computer **plays the whole tournament 10,000 times**. Each game is settled by that matchup's odds, like rolling a weighted die, and we count how often each team cuts down the nets. That count is our forecast.

## How we'll know it works: practice tests

Before we trust the machine with next season, we test it on the 2015, 2016, 2017 and 2018 tournaments, where we already know the answers. For each one, the machine may only use games played before that tournament started. Then we grade it against two lazy methods: "the better seed always wins" (2015-2017, because the data has no 2018 seeds) and "the team with the better record always wins" (all four years).

> **No peeking.** We know who really won in 2019. Nobody tunes the machine toward that answer. Gemini knows it too, so every prompt tells it to use only our numbers. We compare with real life only at the very end, and that's a great moment for the pitch either way.

## Decisions we've locked, and why

| Decision                                                                              | Why                                                                                                                                           |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Predict the 2018-19 champion                                                          | The data ends in April 2018, so the next title is 2019.                                                                                       |
| Build a projected field of 68, then simulate                                          | The data has no 2018-19 bracket.                                                                                                              |
| Seeds never go inside the model                                                       | Seeds exist only through 2017, and never for the season we predict.                                                                           |
| `AI.GENERATE` with `output_schema`, not `AI.GENERATE_TABLE`                           | `AI.GENERATE_TABLE` needs a BigQuery connection we can't create. `AI.GENERATE` returns the same structured answers (tested).                  |
| dbt, not Dataform                                                                     | Dataform is Google's version, but we can't create Dataform repositories in this project. dbt runs from our laptops against BigQuery (tested). |
| Reuse the organizers' Knowledge Catalog work                                          | They already published a 151-term glossary, column descriptions, join relationships and example queries.                                      |
| The chat assistant in Agents Hub is the guaranteed demo; Gemini Enterprise is a bonus | We can view Gemini Enterprise apps but can't create one or call the assistant.                                                                |
| One dataset, every table name starts with its station's prefix                        | We can't create datasets, and six people share `texas_longhorns`.                                                                             |

## The machine: six stations

Our solution works like an assembly line. Raw data goes in at station 1. A forecast, a dashboard and a chat assistant come out after station 6. Each of us runs one station, and each station passes its finished tables to the next one, all inside BigQuery. The jobs follow the roles the event suggested.

### 1. Clean the ingredients - Data Engineer 1

Turns messy raw tables into tidy ones and fixes the traps, like one table naming a season by the year it starts and another by the year it ends, or NIT games hiding under the "NCAA" label. Rebuilds each year's bracket round by round, and turns the organizers' scan results into data-quality checks.

**Passes on:** tidy tables `stg_` · quality checks `dq_`

### 2. Grade every team - Data Engineer 2

Writes a report card for all 351 teams, every season: scoring and defense per trip down the court (adjusted for opponent strength), turnovers, rebounds, how tough the schedule was, recent form, and how much of the team comes back next year. **Publishes the report card's column names first**, so everyone else can start. At the end, serves up the final "menu" tables the dashboard and chat assistant read.

**Passes on:** report cards `f_` · menu tables `mart_`

### 3. Predict one game - ML Engineer 1

Teaches BigQuery ML to answer one question: if Team A plays Team B on a neutral court, what's the chance A wins? Trains a simple model and a stronger one, keeps whichever gives the most trustworthy odds, and asks it which stats mattered most so we can explain every forecast.

**Passes on:** game models `m_` · odds for every matchup `p_`

### 4. Play the tournament 10,000 times - ML Engineer 2

Plays each bracket over and over with those odds and counts how often each team wins each round. Grades the machine on the 2015-2018 tournaments. Then estimates next season's team strength, builds a likely field of 68 and plays that 10,000 times. Out comes our pick.

**Passes on:** tournament results `sim_` · practice-test grades `eval_`

### 5. Turn numbers into words - Analytics Engineer

Writes the Gemini prompts (`AI.GENERATE` with `output_schema`) that turn our numbers into short scouting reports, the league's strengths and weaknesses, and the executive summary. Builds the Looker Studio dashboard.

**Passes on:** written insights `ai_` · the dashboard

### 6. Answer questions, tell the story - Team Captain

Builds the Front Office Analyst, a chat assistant in [BigQuery Agents Hub](https://console.cloud.google.com/bigquery/agents_hub;caPath=%2Fbq2%2Fchat?project=da-hackathon-2026) that answers questions about our tables in plain English, starting from the organizers' glossary. Checks early whether the organizers' Gemini Enterprise app can use it. Owns Knowledge Catalog, the pitch, and the log of what we learned.

**Passes on:** the chat assistant · the briefing

_Each hand-off is a pass, like on a coach's whiteboard. A station's finished table is the ball._

### The glue: Data Engineers

Sets up the repo and the dbt project, merges everyone's work one piece at a time, and makes sure the demo can't break on stage.

## How we build it

- **Everything is SQL in one dbt project.** Each table is one `.sql` file holding one `SELECT`. dbt works out the run order, runs our checks, and writes our descriptions into BigQuery, where Knowledge Catalog and the chat assistant read them.
- **Always run dbt through `scripts/dbt.sh`.** dbt's normal login fails in this project (a missing permission), so the script hands dbt your gcloud access token instead.
- **Build only your own tables:** `scripts/dbt.sh build --select <your models>`.
- **Data-quality checks are dbt tests** (not null, unique, allowed values, row counts), plus a model built on the organizers' scan results.
- **Machine-learning models** are created by a dbt post-hook on the training-data table. Predictions are ordinary dbt models.
- **The tournament simulation is one SQL model:** 10,000 brackets × 63 games, one step per round, with seeded random numbers so the same seed always gives the same odds. No stored procedures, no Python.
- **Gemini outputs are dbt models tagged `ai`.** Normal runs skip them; we generate them on purpose and keep the results in tables.
- **Not using:** Dataform (no permission), schedulers like Airflow (one command is enough), a custom app, Cloud Run, notebooks.

```
models/
  00_stg/       stg_*          DE1   tidy views, brackets
  01_dq/        dq_*           DE1   data-quality checks
  02_features/  f_*            DE2   report cards, matchup rows
  03_models/    m_*, p_*       ML1   BQML training + predictions
  04_sim/       sim_*, eval_*  ML2   simulation, practice tests, next-season projection
  05_ai/        ai_*           AE    Gemini outputs
  06_marts/     mart_*         DE2   tables the dashboard and chat assistant read
prompts/  agents/  dashboards/  docs/
```

## What we end up with

### The front office report

_Dashboard · Looker Studio_

The pick and the title odds for the top contenders. Why: each contender's scouting report and the stats that drove the forecast. The league's strengths and weaknesses by conference. How the machine scored on its practice tests.

### The Front Office Analyst

_Chat assistant · Agents Hub_

Ask it something like "Which contenders rely most on three-pointers?" It writes the query, runs it on our tables and answers in plain English.

### The executive pitch

_Briefing · 5-10 minutes_

Three parts, as the judges asked. Architecture: what we built and why. Strategy: why we picked who we picked and what we learned. Consulting: how 66degrees reuses the same machine for clients, like a store forecasting what sells out or a bank flagging risky loans.

Behind all three: one command rebuilds everything from the raw data.

## How we get started

1. **Get into BigQuery.** Open [project da-hackathon-2026](https://console.cloud.google.com/bigquery?project=da-hackathon-2026) with your 66degrees account and check that you can see the `texas_longhorns` dataset. Working from a terminal? Run `scripts/gcp-login.sh`, then `scripts/dbt.sh debug`.
2. **Read two short docs.** `docs/spec.md` says what we're building. `docs/data-profile.md` says what the data can and can't do, and where the traps are. About 10 minutes.
3. **Claim a station.** Put your name next to your station in `docs/tasks.md`. Every task there comes with a check that proves it's done.
4. **Data Engineers set up the dbt project** (task T0): folders, `dbt_project.yml`, `profiles.yml`, and a first test that passes for everyone.
5. **Data engineers start right away.** DE1 writes the `stg_` views. DE2 writes the report card's column names and descriptions first and shares them. That list is what unblocks stations 3 to 6.
6. **Everyone builds at once.** Save every model in your station's folder in the team repo.
7. **Run it end to end, just past halfway.** The whole machine should run from start to finish once, even if it's ugly. Ugly and working beats pretty and half-built.

## Rules of the road

- Build only in `texas_longhorns`. Never touch another team's dataset.
- Change only your own station's tables and files. Every table name starts with its station's prefix.
- Run dbt through `scripts/dbt.sh`, and build only your own models.
- In our tables, season 2017 means the 2017-18 season.
- Save AI answers into tables ahead of time. Nothing is calculated live during the demo.
- Write down every new tool you tried and every wall you hit in `docs/learnings.md`. The judges score what we learned.
- After 80% of our time, no new features. Only fixes and polish.
- No peeking at anything that happened after April 2018 while building.
