# Agentic Architecture — Diagrams (Lucidchart-ready)

These diagrams describe the NCAA Championship Predictor agentic solution.
**Import into Lucidchart:** Insert → Diagram → *Mermaid* (or the Mermaid shape),
paste one code block at a time.

---

## 1. End-to-end agentic architecture

```mermaid
flowchart TB
    subgraph USER["Users"]
        EX["Executive / Analyst"]
    end

    subgraph ORCH["Reasoning & Orchestration"]
        GEM["Gemini Enterprise<br/>(conversation, reasoning, synthesis)"]
        AGENT["BigQuery Data Agent<br/>(NL to SQL, grounded in Knowledge Catalog)"]
    end

    subgraph GOV["Governed Semantic Layer — BigQuery"]
        CUR["Curated tables<br/>feat_/fct_/dim_"]
        BQML["BQML models<br/>ML.PREDICT"]
        AIGEN["AI.GENERATE routines<br/>scouting narratives"]
        SIM["Bracket simulation<br/>champion probabilities"]
    end

    subgraph SRC["Sources (read-only)"]
        RAW["ncaa_basketball<br/>raw tables"]
        SCAN["ncaa_basketball_scan_results<br/>Dataplex profiles"]
        CAT["Knowledge Catalog<br/>NCAA Basketball Glossary"]
    end

    EX -->|"Who wins & why?"| GEM
    GEM -->|delegates data questions| AGENT
    AGENT -->|trusted SQL| CUR
    AGENT --> BQML
    AGENT --> AIGEN
    CUR --> SIM
    BQML --> SIM
    SIM -->|P(champion) per team| AGENT
    AIGEN -->|grounded narrative| AGENT
    AGENT -->|results + evidence| GEM
    GEM -->|answer + confidence| EX

    RAW --> CUR
    SCAN --> CUR
    CAT --> AGENT
    CAT --> AIGEN

    classDef user fill:#EE6C4D,stroke:#0B2545,color:#fff;
    classDef orch fill:#0B2545,stroke:#0B2545,color:#fff;
    classDef gov fill:#3D5A80,stroke:#0B2545,color:#fff;
    classDef src fill:#E0FBFC,stroke:#3D5A80,color:#0B2545;
    class EX user;
    class GEM,AGENT orch;
    class CUR,BQML,AIGEN,SIM gov;
    class RAW,SCAN,CAT src;
```

---

## 2. Grounding chain (how every claim traces to data)

```mermaid
flowchart LR
    Q["User question"] --> A["BigQuery Data Agent"]
    A --> M["Knowledge Catalog<br/>metadata + glossary"]
    M --> T["Curated tables<br/>feat_team_season / fct_*"]
    T --> P["BQML ML.PREDICT<br/>matchup odds"]
    P --> S["Bracket simulation<br/>P(champion)"]
    S --> N["AI.GENERATE<br/>narrative grounded in features"]
    N --> R["Answer with evidence<br/>(numbers + why)"]

    classDef step fill:#3D5A80,stroke:#0B2545,color:#fff;
    class Q,A,M,T,P,S,N,R step;
```

---

## 3. Request sequence (runtime)

```mermaid
sequenceDiagram
    actor Exec as Executive
    participant Gem as Gemini Enterprise
    participant Agent as BigQuery Data Agent
    participant BQ as BigQuery (curated + BQML)

    Exec->>Gem: "Who wins the championship, and why?"
    Gem->>Agent: Decompose into data questions
    Agent->>BQ: NL to SQL over governed model
    BQ-->>Agent: Champion probabilities + features
    Agent->>BQ: AI.GENERATE scouting narrative
    BQ-->>Agent: Grounded strengths / weaknesses
    Agent-->>Gem: Results + evidence (query-traceable)
    Gem-->>Exec: Prediction + confidence + reasoning
```

---

## 4. Consulting reuse pattern (66degrees)

```mermaid
flowchart TB
    subgraph PATTERN["Reusable accelerator"]
        C1["Knowledge Catalog<br/>discovery"] --> C2["Curated semantic layer"]
        C2 --> C3["BQML predictions"]
        C3 --> C4["Data Agent + Gemini"]
    end

    PATTERN --> U1["Churn / retention"]
    PATTERN --> U2["Demand forecasting"]
    PATTERN --> U3["Risk / fraud scoring"]
    PATTERN --> U4["Pipeline win-probability"]

    classDef p fill:#0B2545,stroke:#0B2545,color:#fff;
    classDef u fill:#EE6C4D,stroke:#0B2545,color:#fff;
    class C1,C2,C3,C4 p;
    class U1,U2,U3,U4 u;
```
