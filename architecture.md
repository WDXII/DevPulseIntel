# Architecture
## DevPulseIntel — Developer Ecosystem Intelligence Platform

---

## 1. Overview

DevPulseIntel is fully Snowflake-native. No external orchestration, no external storage, no external dashboards. Every object — from ingestion through to the deployed application — lives within a single Snowflake account.

```
CSV File (local)
     │
     │  PUT (Snowsight UI or SnowSQL)
     ▼
@INGESTION.RAW_STAGE  ←── INGESTION.SURVEY_PIPE (Snowpipe — configured, demonstrates pattern)
     │
     │  COPY INTO
     ▼
RAW.RAW_SURVEY_RESPONSES           (114 survey cols + 2 metadata, all VARCHAR)
     │
     │  Dynamic Table
     ▼
CLEAN.DT_CLEAN_RESPONSES           (typed, aliased, null-handled, 1:1 rows)
     │
     │  Dynamic Table
     ▼
ANALYTICS.DT_ANALYTICS_DEVELOPERS (professional devs only, business logic, derived cols)
     │
     ├─────────────────────────────────────┐
     │                                     │
     │  Cortex LLM Functions               │  Cortex ML FORECAST
     │  SENTIMENT / COMPLETE /             │  (salary by experience)
     │  CLASSIFY_TEXT                      │
     │  (applied to 10% sample)            │
     ▼                                     ▼
ENRICHED.ENRICHED_RESPONSES        ENRICHED.SALARY_FORECAST_RESULTS
(~6,500 sampled rows)              ENRICHED.SALARY_BENCHMARKS
     │
     ├─────────────────────────────────────┐
     │                                     │
     ▼                                     ▼
ENRICHED.DEVPULSE_SEARCH           Streamlit in Snowflake
(Cortex Search Service)            DEVPULSEINTEL_APP
```

---

## 2. Medallion Architecture

### Layer 0 — INGESTION (Stage + Pipe)
- **Philosophy:** Land the data. No transformation.
- Internal named stage holds the raw CSV.
- Snowpipe (`SURVEY_PIPE`) is configured and demonstrates event-driven ingestion capability even though data is static.

### Layer 1 — RAW (Standard Table)
- **Philosophy:** Source fidelity. Column names match the CSV headers exactly.
- All 114 survey columns stored as VARCHAR — no casting, no business logic.
- Two underscore-prefixed metadata columns: `_SOURCE_FILE_NAME` (from `METADATA$FILENAME`) and `_LOAD_TIMESTAMP` (table DEFAULT).
- This layer is the ground truth. If anything goes wrong downstream, you can always reprocess from here.

### Layer 2 — CLEAN (Dynamic Table)
- **Philosophy:** Make data usable. One row in, one row out.
- RAW column names (CSV-derived, e.g. `YEARSCODEPRO`) aliased to readable snake_case (`YEARS_CODE_PRO_INT`).
- Type casting applied: experience fields to INTEGER, salary to FLOAT with outlier removal.
- Reserved word `CHECK` renamed to `CHECK_COL` at RAW; aliased cleanly in CLEAN.
- This is the only layer that references RAW column names. Nothing below CLEAN needs to know how the CSV was named.

### Layer 3 — ANALYTICS (Dynamic Table)
- **Philosophy:** Make data useful. Business logic and filters applied.
- Professional developers only (excludes students, hobbyists).
- Derived columns: SALARY_BAND, EXPERIENCE_BUCKET, PRIMARY_LANGUAGE, PRIMARY_DEV_ROLE, USES_AI_TOOLS, JOB_SAT_SCORE.
- Both Dynamic Tables set to `TARGET_LAG = '9999 days'` — manual refresh only, no ongoing compute cost.

### Layer 4 — ENRICHED (Standard Tables)
- **Philosophy:** Run AI once, store forever. Never compute Cortex functions at query time.
- `ENRICHED_RESPONSES`: all Cortex LLM outputs as physical columns. Populated from ANALYTICS with a `SAMPLE (10 PERCENT)` clause (~6,500 professional developers).
- `SALARY_FORECAST_RESULTS`: Cortex ML FORECAST predictions.
- `SALARY_BENCHMARKS`: pre-aggregated percentile table for the Streamlit salary widget.
- `DEVPULSE_SEARCH`: Cortex Search service indexed on composite profile text.

---

## 3. Object Inventory

### 3.1 Database
| Name | Purpose |
|---|---|
| `DEVPULSEINTEL` | Single database for all project objects |

### 3.2 Schemas
| Name | Layer | Purpose |
|---|---|---|
| `INGESTION` | Ingestion | Stage, file format, Snowpipe |
| `RAW` | Layer 1 | Raw survey table |
| `CLEAN` | Layer 2 | Typed Dynamic Table |
| `ANALYTICS` | Layer 3 | Business logic Dynamic Table + supporting views |
| `ENRICHED` | Layer 4 | Cortex outputs, ML results, Search service, Streamlit app |

### 3.3 Warehouses
| Name | Size | Auto-Suspend | Used For |
|---|---|---|---|
| `DEVPULSE_LOAD_WH` | XSMALL | 60s | COPY INTO loads |
| `DEVPULSE_TRANSFORM_WH` | XSMALL | 60s | Dynamic Table manual refresh |
| `DEVPULSE_CORTEX_WH` | XSMALL | 60s | Cortex LLM/ML enrichment (run once) |
| `DEVPULSE_APP_WH` | XSMALL | 60s | Streamlit app sessions |

### 3.4 Stage and File Format
| Name | Type | Purpose |
|---|---|---|
| `INGESTION.RAW_STAGE` | Internal Named Stage | Holds the survey CSV before loading |
| `INGESTION.SURVEY_CSV_FORMAT` | File Format | CSV with quoted fields, null handling, UTF-8 |

### 3.5 Snowpipe
| Name | Source | Target | Notes |
|---|---|---|---|
| `INGESTION.SURVEY_PIPE` | `@RAW_STAGE` | `RAW.RAW_SURVEY_RESPONSES` | `AUTO_INGEST = FALSE` — configured for pattern demonstration; inactive post-load |

### 3.6 Tables
| Schema | Table | Type | Rows | Purpose |
|---|---|---|---|---|
| `RAW` | `RAW_SURVEY_RESPONSES` | Standard Table | ~65K | COPY INTO target; 114 columns all VARCHAR |
| `ENRICHED` | `ENRICHED_RESPONSES` | Standard Table | ~6.5K (sample) | Cortex LLM outputs materialized on 10% sample |
| `ENRICHED` | `SALARY_FORECAST_RESULTS` | Standard Table | Variable | Cortex ML FORECAST predictions per country |
| `ENRICHED` | `SALARY_BENCHMARKS` | Standard Table | Variable | Pre-aggregated salary percentiles |

### 3.7 Dynamic Tables
| Schema | Name | Source | Lag | Purpose |
|---|---|---|---|---|
| `CLEAN` | `DT_CLEAN_RESPONSES` | `RAW.RAW_SURVEY_RESPONSES` | `9999 days` | Typed and aliased; no business logic |
| `ANALYTICS` | `DT_ANALYTICS_DEVELOPERS` | `CLEAN.DT_CLEAN_RESPONSES` | `9999 days` | Professional devs only; derived columns |

### 3.8 Views
| Schema | Name | Purpose |
|---|---|---|
| `ANALYTICS` | `V_SALARY_BY_COUNTRY` | Median/avg salary aggregated by country |
| `ANALYTICS` | `V_AI_ADOPTION_BY_ROLE` | AI adoption rate by developer role |
| `ANALYTICS` | `V_LANGUAGE_DEMAND` | Language usage count by country (LATERAL FLATTEN) |
| `ENRICHED` | `V_SALARY_TRAINING_INPUT` | Training data for ML FORECAST (median salary by experience × country) |
| `ENRICHED` | `V_SALARY_ACTUAL_VS_FORECAST` | Actuals + forecast combined for Streamlit chart |
| `ENRICHED` | `V_SEARCH_PROFILES` | Composite profile text for Cortex Search indexing |

### 3.9 Cortex Objects
| Type | Name | Method | Input | Output | Scope |
|---|---|---|---|---|---|
| LLM Function | Sentiment scoring | `CORTEX.SENTIMENT()` | `JOB_SAT` text | Float score −1 to 1 | 10% sample |
| LLM Function | Skill clustering | `CORTEX.COMPLETE()` | `LANGUAGE_HAVE_WORKED_WITH` | Skill cluster label | 10% sample |
| LLM Function | Role standardization | `CORTEX.CLASSIFY_TEXT()` | `DEV_TYPE` | Standardized role category | 10% sample |
| LLM Function | AI attitude | `CORTEX.CLASSIFY_TEXT()` | `AI_SENTIMENT_RAW` | Enthusiast / Cautious / Skeptic / Neutral | 10% sample |
| ML Model | `SALARY_FORECAST_MODEL` | `SNOWFLAKE.ML.FORECAST` | Experience × country median salary | Predicted salary | Full dataset |
| Search Service | `DEVPULSE_SEARCH` | Cortex Search | `V_SEARCH_PROFILES.PROFILE_TEXT` | Semantic search results | 10% sample |

### 3.10 Streamlit App
| Name | Warehouse | Schema | Views |
|---|---|---|---|
| `DEVPULSEINTEL_APP` | `DEVPULSE_APP_WH` | `ENRICHED` | Salary Explorer, AI Adoption, Skill Demand, Semantic Search |

---

## 4. Column Naming Convention

| Layer | Convention | Example |
|---|---|---|
| RAW | Matches CSV header exactly (uppercased, spaces removed) | `YEARSCODEPRO`, `CONVERTEDCOMPYEARLY` |
| CLEAN | Readable snake_case, typed | `YEARS_CODE_PRO_INT`, `ANNUAL_COMP_USD` |
| ANALYTICS | Inherits CLEAN names; adds derived columns | `SALARY_BAND`, `EXPERIENCE_BUCKET`, `USES_AI_TOOLS` |
| ENRICHED | Inherits ANALYTICS passthrough names; adds Cortex columns | `SKILL_CLUSTER`, `STANDARDIZED_ROLE`, `JOB_SAT_SENTIMENT_SCORE` |

**Key rule:** Only `DT_CLEAN_RESPONSES` references RAW column names. All other objects reference CLEAN or ANALYTICS column names. This isolates the source schema from the rest of the pipeline.

---

## 5. Cortex FORECAST Design Note

`SNOWFLAKE.ML.FORECAST` requires a TIMESTAMP column as the time axis. Salary data has no natural time dimension — prediction is by years of professional experience.

**Solution:** `YEARS_CODE_PRO_INT` is encoded as a pseudo-timestamp using a fixed epoch:
```sql
DATEADD('day', YEARS_CODE_PRO_INT, '2000-01-01'::DATE)::TIMESTAMP_NTZ
```
Experience = 0 → `2000-01-01`, Experience = 10 → `2000-01-11`. Each country is a separate series. To decode back to years of experience from the stored dates, use `DATEDIFF`:
```sql
DATEDIFF('day', '2000-01-01'::DATE, EXPERIENCE_DATE::DATE) AS YEARS_EXPERIENCE
```

---

## 6. Object Status Verification

The correct commands to check status of each Snowflake-native object type:

```sql
-- Standard objects
SHOW TABLES          IN SCHEMA DEVPULSEINTEL.RAW;
SHOW PIPES           IN SCHEMA DEVPULSEINTEL.INGESTION;
SHOW STAGES          IN SCHEMA DEVPULSEINTEL.INGESTION;

-- Dynamic Tables (check TARGET_LAG column)
SHOW DYNAMIC TABLES  IN DATABASE DEVPULSEINTEL;

-- Cortex ML model
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;

-- Cortex Search (check STATUS column — wait for ACTIVE)
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;

-- Streamlit app
SHOW STREAMLITS      IN SCHEMA DEVPULSEINTEL.ENRICHED;

-- Column structure of any table
DESCRIBE TABLE DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;
```

> **Note:** Cortex Search and Cortex ML objects are managed with `SHOW` commands, not through `INFORMATION_SCHEMA`. `INFORMATION_SCHEMA` covers standard SQL objects (tables, views, columns, stages). For newer Snowflake-native AI features, always use `SHOW`.

---

## 7. Credit Cost Estimates

### Design Assumption: 10% Sampling for Cortex LLM

**All Cortex LLM enrichment functions are applied to a 10% random sample** of professional developers (~6,500 rows) from `ANALYTICS.DT_ANALYTICS_DEVELOPERS`. This is a deliberate cost-efficiency tradeoff:

- **Full-dataset enrichment (65,000 rows):** ~$70–$88 in AI_SERVICES credits
- **Sampled enrichment (6,500 rows, 10%):** ~$7–$10 in AI_SERVICES credits
- **Benefit:** Produces meaningful aggregations in all Streamlit views while reducing cost by 90%

The sample is applied in `04_cortex_enrich.sql` Section 2:
```sql
INSERT INTO ENRICHED.ENRICHED_RESPONSES
SELECT * FROM ANALYTICS.DT_ANALYTICS_DEVELOPERS
SAMPLE (10 PERCENT);  ← Sampling reduces Cortex LLM cost
```

See **setup.md → Step 5** and **README.md → Cost Profile** for full context.

---

### Estimated Cost Breakdown (with 10% sampling)

| Operation | Rows | Estimated Credits | Frequency | Notes |
|---|---|---|---|---|
| COPY INTO raw load | 65K | < 0.1 | Once | Initial load |
| Dynamic Table refresh (CLEAN) | 65K | < 0.05 | Once | One-time manual refresh |
| Dynamic Table refresh (ANALYTICS) | ~50K | < 0.05 | Once | One-time manual refresh |
| Cortex SENTIMENT | 6.5K | ~0.03 | Once | 10% sample |
| Cortex CLASSIFY_TEXT (roles) | 6.5K | ~0.03 | Once | 10% sample |
| Cortex COMPLETE (skill clusters) | 6.5K | ~0.05 | Once | 10% sample, longest running |
| Cortex CLASSIFY_TEXT (AI attitude) | 6.5K | ~0.03 | Once | 10% sample |
| Cortex ML FORECAST training | 50K | ~0.5 | Once | Full dataset aggregation |
| Cortex Search service creation | 6.5K | ~0.2 | Once | 10% sample indexing |
| Streamlit app sessions | — | ~0.5 | Ongoing | Demo use, minimal |
| **Subtotal — Warehouse Compute** | | **~1–2** | | |
| **AI_SERVICES (Cortex LLM tokens)** | | **~7–10** | | |
| **Total estimate (sampled)** | | **~8–12 credits (~$3–$5 USD)** | | |

---

### What If Full-Dataset Enrichment Is Applied?

If the `SAMPLE(10 PERCENT)` clause is omitted from `04_cortex_enrich.sql` Section 2:

| Operation | Rows | Estimated Credits | Notes |
|---|---|---|---|
| Cortex SENTIMENT | 65K | ~0.3 | Full dataset |
| Cortex CLASSIFY_TEXT (roles) | 65K | ~0.3 | Full dataset |
| Cortex COMPLETE (skill clusters) | 65K | ~0.5 | Full dataset, longest running |
| Cortex CLASSIFY_TEXT (AI attitude) | 65K | ~0.3 | Full dataset |
| **AI_SERVICES subtotal** | | **~$70–$88** | **17x cost of sampled approach** |
| **Total project cost** | | **~$75–$90** | |

This is **not an error** — it's the real cost of full-dataset Cortex LLM enrichment at scale. See **README.md → Cost Retrospective** for the detailed analysis of why the original BRD underestimated this cost.

---

### Warehouse Compute Estimates (both scenarios)

Warehouse compute is identical regardless of sampling (same ingestion, same Dynamic Table refresh, same ML training on aggregates):

| Component | Estimated Credits |
|---|---|
| Ingestion (LOAD_WH) | < 0.5 |
| Transformation (TRANSFORM_WH) | < 0.5 |
| ML Training (CORTEX_WH) | < 0.5 |
| App Sessions (APP_WH) | < 1.0 |
| **Total warehouse** | **~$2–3** |

---

## 8. Design Decisions

### Why Dynamic Tables over Tasks + Stored Procedures?
Dynamic Tables are Snowflake's declarative transformation primitive. You define the output, not the execution plan. This is the current Snowflake-recommended pattern. Tasks + stored procedures solve the same problem imperatively and require significantly more code.

### Why materialize Cortex outputs instead of querying live?
Every Cortex LLM function call consumes credits and adds latency. Materializing once makes the app fast, cost fixed, and results reproducible. The Streamlit app reads static columns — no tokens consumed at query time.

### Why `TARGET_LAG = '9999 days'`?
The dataset is static. Auto-refresh serves no purpose and would consume credits on a schedule. Setting lag to 9999 days effectively disables auto-refresh while keeping Dynamic Tables as the declared mechanism (correct for portfolio demonstration). Tables are manually refreshed once after creation with `ALTER DYNAMIC TABLE ... REFRESH`.

### Why one database with multiple schemas?
Simpler object references, simpler for a portfolio project. A production system might separate RAW and ANALYTICS into separate databases for governance — documented as a known simplification.

### Why XSMALL warehouses everywhere?
This dataset (65K rows, 114 columns) fits comfortably in XSMALL compute. No warehouse needs to be larger. Cost minimization is explicit in the NFRs.

### Why apply Cortex LLM to only 10% of data?
Cortex LLM functions bill per token, making full-dataset enrichment prohibitively expensive for portfolio projects ($70–$88 vs. $7–$10). A 10% stratified sample (~6,500 rows) demonstrates full capability, produces meaningful analytical results, and keeps costs practical. This is a deliberate engineering tradeoff documented in **BRD.md Section 9 (revised)** and **README.md → Cost Profile**.

---

*DevPulseIntel · Stack Overflow Developer Survey 2024 · Built on Snowflake Trial*
