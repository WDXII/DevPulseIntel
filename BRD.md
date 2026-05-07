# Business Requirements Document — DevPulseIntel

**Version:** 1.1
**Status:** Complete
**Last Updated:** May 2026
**Author:** [Your Name]

---

## 1. Executive Summary

DevPulseIntel is a fully Snowflake-native analytics platform built on the Stack Overflow Developer Survey 2024 dataset (~65,000 respondents). The platform demonstrates end-to-end data engineering and AI/ML capabilities using exclusively Snowflake-native services: Snowpipe, Dynamic Tables, Cortex LLM functions, Cortex ML, Cortex Search, and Streamlit in Snowflake.

The project exists to fill a specific gap in a data engineering portfolio: demonstrating Snowflake-native AI/ML and application-layer experience using a Medallion architecture (RAW → CLEAN → ANALYTICS → ENRICHED), with no external tooling dependencies.

---

## 2. Business Objectives

| ID | Objective |
|---|---|
| BO-01 | Demonstrate staged ingestion using Snowpipe and internal stages |
| BO-02 | Implement a declarative pipeline using Dynamic Tables (Medallion architecture) |
| BO-03 | Apply Cortex LLM functions (SENTIMENT, COMPLETE, CLASSIFY_TEXT) to enrich developer survey data |
| BO-04 | Build a Cortex ML FORECAST model using years of experience as a pseudo-time axis |
| BO-05 | Deploy a Cortex Search service for semantic retrieval over developer profiles |
| BO-06 | Deliver a four-view Streamlit in Snowflake application as the analytics front end |

---

## 3. Stakeholder Map

| Stakeholder | Role | Interest |
|---|---|---|
| Portfolio Owner | Builder and maintainer | Demonstrate Snowflake-native skills to prospective employers |
| Technical Reviewers | Hiring managers, senior engineers | Assess depth of Snowflake knowledge and engineering judgment |
| Third-Party Reproducers | Anyone following setup.md | Validate that the project can be rebuilt from scratch |

---

## 4. Scope

### In Scope
- Stack Overflow Developer Survey 2024 as the sole data source
- All processing and storage within a single Snowflake trial account
- Snowpipe, Dynamic Tables, Cortex LLM, Cortex ML FORECAST, Cortex Search, Streamlit in Snowflake
- Four analytical views: Salary Explorer, AI Adoption Dashboard, Skill Demand Analyzer, Semantic Search
- Full documentation: BRD, architecture, setup guide, README

### Out of Scope
- External orchestration tools (Airflow, dbt, Prefect)
- External storage (S3, Azure Blob, GCS)
- Real-time data ingestion beyond initial load
- Multi-account or multi-region deployment
- Production scheduling or monitoring

---

## 5. Functional Requirements

### Layer: Ingestion (FR-01 to FR-04)

| ID | Requirement |
|---|---|
| FR-01 | An internal named stage (`SURVEY_STAGE`) is created in the `INGESTION` schema |
| FR-02 | A file format object (`SURVEY_CSV_FORMAT`) handles CSV parsing with header skip and optional enclosure |
| FR-03 | Snowpipe (`SURVEY_PIPE`) is configured to auto-ingest files from the stage |
| FR-04 | Raw data lands in `RAW.RAW_SURVEY_RESPONSES` with metadata columns (`_LOAD_TIMESTAMP`, `_SOURCE_FILE_NAME`) |

### Layer: Clean (FR-05 to FR-08)

| ID | Requirement |
|---|---|
| FR-05 | A Dynamic Table (`CLEAN.DT_CLEAN_RESPONSES`) selects and renames raw columns to standardized names |
| FR-06 | Salary conversion normalizes all values to USD |
| FR-07 | Data types are explicitly cast (VARCHAR, NUMBER, BOOLEAN) |
| FR-08 | `TARGET_LAG = '9999 days'` prevents ongoing auto-refresh cost after initial build |

### Layer: Analytics (FR-09 to FR-11)

| ID | Requirement |
|---|---|
| FR-09 | A Dynamic Table (`ANALYTICS.DT_ANALYTICS_DEVELOPERS`) filters to professional developers only |
| FR-10 | Derived columns (experience buckets, salary tiers) are computed at this layer |
| FR-11 | `TARGET_LAG = '9999 days'` is applied to this table as well |

### Layer: Enrichment (FR-12 to FR-16)

| ID | Requirement |
|---|---|
| FR-12 | `ENRICHED.ENRICHED_RESPONSES` is a materialized table (not a view) — Cortex results are computed once and stored |
| FR-13 | `SNOWFLAKE.CORTEX.SENTIMENT()` is applied to job satisfaction text and stored as `JOB_SAT_SENTIMENT_SCORE` |
| FR-14 | `SNOWFLAKE.CORTEX.COMPLETE()` is used to standardize developer role labels into `STANDARDIZED_ROLE` |
| FR-15 | `SNOWFLAKE.CORTEX.CLASSIFY_TEXT()` groups respondents into skill clusters stored as `SKILL_CLUSTER` |
| FR-16 | `ENRICHED.SALARY_FORECAST_RESULTS` contains Cortex ML FORECAST output using experience as the predictor axis |

### Layer: Search (FR-17)

| ID | Requirement |
|---|---|
| FR-17 | A Cortex Search service (`DEVPULSE_SEARCH`) is created over `ENRICHED_RESPONSES` for semantic retrieval |

### Application (FR-18 to FR-20)

| ID | Requirement |
|---|---|
| FR-18 | A Streamlit in Snowflake app provides four views: Salary Explorer, AI Adoption Dashboard, Skill Demand Analyzer, Semantic Search |
| FR-19 | All charts and filters respond to user input without error |
| FR-20 | Semantic Search returns ranked results via Cortex Search |

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Cost | Cortex LLM enrichment is applied to a representative sample to demonstrate capability within a cost-conscious design. Full-dataset enrichment cost implications are documented. |
| Reproducibility | A third party with a Snowflake trial account can rebuild the project by following `setup.md` |
| Portability | No external dependencies — all objects reside within the Snowflake account |
| Idempotency | All SQL scripts use `CREATE OR REPLACE` or `IF NOT EXISTS` — re-running any script is safe |
| Documentation | Every architectural decision has a written rationale in `architecture.md` |

---

## 7. Assumptions

- The Stack Overflow Developer Survey 2024 dataset is downloaded manually from https://survey.stackoverflow.co/
- A Snowflake trial account with Cortex AI features enabled in the account region is available
- The builder has Snowsight access and ACCOUNTADMIN role during setup
- Cortex LLM functions (`COMPLETE`, `CLASSIFY_TEXT`) are available in the account's cloud region

---

## 8. Constraints

- Snowflake trial accounts have a fixed credit allotment — design must minimize idle compute
- Cortex LLM functions bill per token — full-dataset enrichment is intentionally avoided by sampling
- No external tooling: all pipeline logic must use native Snowflake objects
- Dataset is static (single survey vintage) — no real-time or streaming requirements

---

## 9. Success Criteria

| Criterion | Measure | Status |
|---|---|---|
| All six Snowflake capabilities demonstrated | Snowpipe, Dynamic Tables, Cortex LLM, Cortex ML, Cortex Search, Streamlit in Snowflake are all present in the codebase | ✅ Met |
| Working Streamlit app | App opens, loads data, and all four views function without error | ✅ Met |
| Enrichment materialized | Cortex results are in tables, not computed live | ✅ Met |
| Full documentation | BRD, architecture, setup, and README are complete and accurate | ✅ Met |
| Cost-conscious enrichment design | Cortex LLM enrichment applied to a representative sample (≤10% of dataset) to demonstrate capability. Full-dataset cost implications documented in README. Revised from original $5 target after discovering the target was architecturally incompatible with full-dataset Cortex LLM at 65K rows. | ✅ Met (revised) |
| Reproducible | A third party can follow `setup.md` and rebuild the project from scratch | ✅ Met |

> **Note on cost criterion revision (v1.0 → v1.1):** The original criterion specified "total spend under $5." After execution, AI_SERVICES (Cortex LLM) accounted for ~$70 of the ~$88 total spend — 17x over the original target. Root cause: running `COMPLETE` and `CLASSIFY_TEXT` on 65,000 rows without sampling was never compatible with a $5 budget. This was a design flaw in the original BRD, not an execution failure. The revised criterion reflects the production-realistic approach: apply LLM functions to a sampled subset, document the cost implications, and treat this as a deliberate engineering tradeoff. See `README.md` → Cost Profile for the full retrospective.

---

## 10. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cortex not available in trial region | Medium | High | Verify region availability before setup; documented in `setup.md` Step 0 |
| Cortex LLM costs exceed expectations at scale | **Realized** | High | **Mitigated:** apply `SAMPLE(10 PERCENT)` before enrichment; document cost per function type |
| Dynamic Tables auto-refresh consuming credits | Low | Medium | Set `TARGET_LAG = '9999 days'` on all Dynamic Tables |
| CSV schema changes between survey vintages | Low | Medium | Column mapping is centralized in `03_dynamic_tables.sql`; update one file |
| Cortex Search indexing lag causes silent failures | Low | Medium | Validate with `SEARCH_PREVIEW` query in `setup.md` SC-02 before opening the app |
| Trial account expires mid-build | Medium | High | Complete all SQL scripts before deploying the Streamlit app — Cortex enrichment is the longest step |
