# DevPulseIntel

A fully Snowflake-native analytics platform built on the Stack Overflow Developer Survey 2024 dataset (~65,000 respondents). DevPulseIntel demonstrates end-to-end data engineering and AI/ML capabilities using exclusively Snowflake-native services — no external orchestrators, no external storage, no local compute.

---

## What It Demonstrates

| Snowflake Capability | Implementation |
|---|---|
| **Snowpipe** | Auto-ingest from internal stage into `RAW.RAW_SURVEY_RESPONSES` |
| **Dynamic Tables** | Medallion architecture — RAW → CLEAN → ANALYTICS, declarative refresh |
| **Cortex LLM** | SENTIMENT on job satisfaction text, COMPLETE for role standardization, CLASSIFY_TEXT for skill clustering |
| **Cortex ML** | FORECAST model using years of experience as a pseudo-time predictor axis |
| **Cortex Search** | Semantic retrieval service over enriched developer profiles |
| **Streamlit in Snowflake** | Four-view analytics application, natively deployed, zero external hosting |

---

## The Four Views

### 1. Salary Explorer
Filter by country, developer role, years of experience, and technology stack. Compare salary distributions and see Cortex ML-predicted salary benchmarks.

### 2. AI Adoption Dashboard
Visualize AI tool adoption rates across developer roles and regions. See which tools are most used, which are most wanted, and sentiment toward AI as a job threat.

### 3. Skill Demand Analyzer
Explore Cortex-classified skill clusters. See which combinations of languages and frameworks form the most common talent profiles globally and in specific markets.

### 4. Semantic Search
Ask natural language questions about developer profiles using Cortex Search. Results are ranked by semantic similarity, not keyword match.

---

## Project Structure

```
DevPulseIntel/
├── BRD.md                    # Business Requirements Document
├── architecture.md           # Full architecture with object inventory
├── setup.md                  # Step-by-step environment setup guide
├── README.md                 # This file
│
├── sql/
│   ├── 01_staging.sql        # Stage and Snowpipe configuration
│   ├── 02_raw_load.sql       # COPY INTO raw table
│   ├── 03_dynamic_tables.sql # CLEAN and ANALYTICS Dynamic Tables
│   ├── 04_cortex_enrich.sql  # SENTIMENT, COMPLETE, CLASSIFY_TEXT enrichment
│   ├── 05_cortex_ml.sql      # Cortex ML FORECAST model
│   └── 06_cortex_search.sql  # Cortex Search service
│
└── streamlit/
    └── app.py                # Streamlit in Snowflake application
```

---

## Quick Start

1. **Download data** — https://survey.stackoverflow.co/ → 2024 full data
2. **Follow** [`setup.md`](./setup.md) — complete step-by-step instructions
3. **Run SQL scripts** in order from `01_staging.sql` to `06_cortex_search.sql`
4. **Deploy** `streamlit/app.py` as a Streamlit in Snowflake app

Full setup takes approximately 2 hours end-to-end.

---

## Cost Profile

This project is designed for **one-time load with zero ongoing compute cost.**

| Component | Approach | Cost Driver |
|---|---|---|
| Warehouse compute | XS warehouse, auto-suspend 60s | One-time build only |
| Dynamic Tables | `TARGET_LAG = '9999 days'` | No scheduled refresh |
| Cortex LLM | Applied to sampled subset (≤10% of rows) | Token cost, not compute |
| Cortex ML FORECAST | Single model training run | One-time |
| Cortex Search | Indexed once at creation | Storage-based |
| Streamlit app | Serverless, no warehouse | Per-session only |

### Cost Retrospective

The original BRD success criterion specified **total spend under $5**. The actual spend was approximately **$88** — 17x over target. This was a design flaw, not an execution failure.

**Root cause:** `COMPLETE` and `CLASSIFY_TEXT` bill per token. Running both across 65,000 respondents without sampling was never compatible with a $5 budget. `AI_SERVICES` alone cost ~$70.

**What should have been in the design from the start:**

```sql
-- Sample before enrichment — demonstrate capability on a representative subset
INSERT INTO ENRICHED.ENRICHED_RESPONSES
SELECT
    RESPONSE_ID,
    SNOWFLAKE.CORTEX.SENTIMENT(JOB_SATISFACTION)      AS JOB_SAT_SENTIMENT_SCORE,
    SNOWFLAKE.CORTEX.COMPLETE('mistral-7b', ...)       AS STANDARDIZED_ROLE,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(LANGUAGE_WORKED, ...) AS SKILL_CLUSTER
FROM ANALYTICS.DT_ANALYTICS_DEVELOPERS
    SAMPLE (10 PERCENT);   -- ← This line prevents the $70 bill
```

**The lesson:** Cortex LLM cost is a function of row count × prompt length × tokens per call — not warehouse size. Budget LLM enrichment per row before running at scale, and always apply a `SAMPLE()` clause in development.

The revised BRD criterion reflects the production-realistic approach: apply LLM enrichment to a sampled subset, document the cost model, treat it as a conscious engineering tradeoff. The capability demonstration is unchanged — the cost governance design is improved.

---

## Skills Demonstrated

```
Snowflake Data Engineering
├── Staged Ingestion (Internal Stage, COPY INTO, Snowpipe)
├── Declarative Pipelines (Dynamic Tables, Medallion Architecture)
├── SQL (DDL, DML, window functions, type casting, null handling)
└── Cost Management (warehouse sizing, auto-suspend, LLM sampling strategy)

Snowflake AI / ML (Cortex)
├── LLM Functions (SENTIMENT, COMPLETE, CLASSIFY_TEXT)
├── Machine Learning (Cortex ML FORECAST)
└── Semantic Search (Cortex Search Service)

Application Development
└── Streamlit in Snowflake (multi-view app, native deployment)

Data Engineering Fundamentals
├── Medallion Architecture (RAW → CLEAN → ANALYTICS → ENRICHED)
├── Schema-on-Read → Schema-on-Write transition
├── Metadata tracking (_LOAD_TIMESTAMP, _SOURCE_FILE_NAME)
├── Idempotent SQL (CREATE OR REPLACE, IF NOT EXISTS)
└── LLM cost governance (token budgeting, sampling before enrichment)
```

---

## Author

[Your Name]
[Your LinkedIn]
[Your GitHub]

---

*Built on Snowflake Trial · Data: Stack Overflow Developer Survey 2024 (ODbL) · May 2026*
