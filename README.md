# NCAA Championship Predictor — 66degrees Hackathon

An AI-driven agentic solution to analyze NCAA league strengths/weaknesses, predict the championship winner, and deliver an executive briefing — built on Google Cloud.

## Tech Stack

- **Data Layer:** GCP BigQuery datasets mapped via Knowledge Catalog
- **ML:** BQML predictive models (matchup + bracket simulation)
- **AI:** `AI.GENERATE` routines for grounded scouting narratives
- **Agentic:** BigQuery Data Agents + Gemini Enterprise

## Contents

| Path | Description |
|------|-------------|
| `NCAA_Execution_Plan.md` | Full phase-by-phase execution plan (roles, phases, assessment matrix) |
| `deck/` | Executive pitch deck (HTML slides → PowerPoint) |
| `deck/NCAA_Execution_Plan.pptx` | Generated 10-slide executive briefing |

## Building the Deck

```bash
cd deck
npm install
npx playwright install chromium
node build.js        # writes NCAA_Execution_Plan.pptx
node preview.js      # optional: render PNG previews of slides
```

## Plan Overview

1. **Data Discovery & Engineering** — Catalog metadata scan → curated BigQuery feature layer
2. **ML & AI Implementation** — BQML matchup model, bracket Monte-Carlo sim, `AI.GENERATE` scouting cards
3. **Agentic Architecture** — Gemini Enterprise ↔ BigQuery Data Agent ↔ governed semantic layer
4. **Executive Pitch** — 5–10 min prediction-first briefing
5. **Assessment Matrix** — mapped to judging criteria (Technical Execution, Discovery & Growth, Value & Impact, Storytelling)

See [`NCAA_Execution_Plan.md`](./NCAA_Execution_Plan.md) for the complete plan.
