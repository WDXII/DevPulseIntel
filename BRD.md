# Business Requirements Document: DevPulseIntel

**Version:** 1.2
**Status:** Complete. Post-build review applied.
**Last Updated:** September 2026
**Author:** William Daluyen

> **How to read this document:** Requirements are stated as originally designed. Where the as-built code differs, an **As built** note says so. Section 9 re-scores the success criteria after the post-build review. Section 11 records each revision.

---

## 1. Executive Summary

DevPulseIntel is a Snowflake-native analytics demo built on the Stack Overflow Developer Survey 2024 (65,437 respondents). It shows end-to-end data engineering and AI/ML work using only Snowflake services: internal stage and pipe, Dynamic Tables, Cortex LLM functions, Cortex ML, Cortex Search, and Streamlit in Snowflake.

The project fills a specific gap in a data engineering portfolio: hands-on experience with Snowflake-native AI/ML and the application layer, using a Medallion architecture (RAW → CLEAN → ANALYTICS → ENRICHED) with no external tooling.

---

## 2. Business Objectives

| ID | Objective |
|---|---|
| BO-01 | Demonstrate staged ingestion using an internal stage, `COPY INTO`, and a pipe definition |
| BO-02 | Implement a declarative pipeline using Dynamic Tables (Medallion architecture) |
| BO-03 | Apply Cortex LLM functions (SENTIMENT, CLASSIFY_TEXT, COMPLETE) to enrich developer survey data |
| BO-04 | Build a Cortex ML FORECAST model using years of experience as a pseudo-time axis |
| BO-05 | Deploy a Cortex Search service for semantic retrieval over developer profiles |
| BO-06 | Deliver a four-view Streamlit in Snowflake application as the analytics front end |

---

## 3. Stakeholder Map

| Stakeholder | Role | Interest |
|---|---|---|
| Portfolio Owner | Builder and maintainer | Demonstrate Snowflake-native skills to prospective employers |
| Technical Reviewers | Hiring managers, senior engineers | Assess depth of Snowflake knowledge and engineering judgment |
| Third-Party Reproducers | Anyone following `setup.md` | Rebuild the project from scratch |

---

## 4. Scope

### In Scope
- Stack Overflow Developer Survey 2024 as the sole data source
- All processing and storage within a single Snowflake trial account
- Internal stage, pipe, Dynamic Tables, Cortex LLM, Cortex ML FORECAST, Cortex Search, Streamlit in Snowflake
- Four analytical views: Salary Explorer, AI Adoption Dashboard, Skill Demand Analyzer, Semantic Search
- Documentation: BRD, architecture, decisions, setup guide, DEVLOG, README

### Out of Scope
- External orchestration tools (Airflow, dbt, Prefect)
- External storage (S3, Azure Blob, GCS)
- Real-time or event-driven ingestion
- Multi-account or multi-region deployment
- Production scheduling or monitoring

---

## 5. Functional Requirements

### Layer: Ingestion (FR-01 to FR-04)

| ID | Requirement | As built |
|---|---|---|
| FR-01 | An internal named stage is created in the `INGESTION` schema | `INGESTION.RAW_STAGE` |
| FR-02 | A file format object handles CSV parsing with header skip and optional enclosure | `INGESTION.SURVEY_CSV_FORMAT` |
| FR-03 | A pipe (`SURVEY_PIPE`) is defined over the stage | Defined with `AUTO_INGEST = FALSE`. The load ran via manual `COPY INTO` in `02_raw_load.sql`; the pipe was never triggered |
| FR-04 | Raw data lands in `RAW.RAW_SURVEY_RESPONSES` with metadata columns (`_LOAD_TIMESTAMP`, `_SOURCE_FILE_NAME`) | As specified: 114 survey columns (all VARCHAR) + 2 metadata columns |

### Layer: Clean (FR-05 to FR-08)

| ID | Requirement | As built |
|---|---|---|
| FR-05 | A Dynamic Table (`CLEAN.DT_CLEAN_RESPONSES`) selects and renames raw columns to standardized names | As specified |
| FR-06 | Salary is expressed in USD | Uses Stack Overflow's pre-converted `ConvertedCompYearly`; values under $100 or over $2M are set to NULL. No currency conversion is performed in-pipeline |
| FR-07 | Data types are explicitly cast | Experience → INTEGER and salary → FLOAT in CLEAN. The BOOLEAN `USES_AI_TOOLS` is derived in ANALYTICS |
| FR-08 | `TARGET_LAG = '9999 days'` prevents ongoing auto-refresh cost | As specified. Refreshed manually once |

### Layer: Analytics (FR-09 to FR-11)

| ID | Requirement | As built |
|---|---|---|
| FR-09 | A Dynamic Table (`ANALYTICS.DT_ANALYTICS_DEVELOPERS`) filters to professional developers | Filter: `MAIN_BRANCH LIKE '%developer%'` and `DEV_TYPE NOT LIKE '%student%'`. Keeps 51,525 rows (source-CSV estimate), including ~6,150 respondents who are not professional developers; see README Known Issue 6 |
| FR-10 | Derived columns (experience buckets, salary bands) are computed at this layer | As specified. `JOB_SAT_SCORE` is also derived here but resolves to NULL because JobSat is numeric (Known Issue 2) |
| FR-11 | `TARGET_LAG = '9999 days'` is applied | As specified |

### Layer: Enrichment (FR-12 to FR-16)

| ID | Requirement | As built |
|---|---|---|
| FR-12 | `ENRICHED.ENRICHED_RESPONSES` is a materialized table; Cortex results are computed once and stored | As specified (INSERT seed + UPDATE per Cortex function) |
| FR-13 | `SNOWFLAKE.CORTEX.SENTIMENT()` is applied to job satisfaction and stored as `JOB_SAT_SENTIMENT_SCORE` | Executed. Post-build review found JobSat is a 0–10 integer in the 2024 survey, so the output is not meaningful (Known Issue 2) |
| FR-14 | `SNOWFLAKE.CORTEX.CLASSIFY_TEXT()` standardizes developer roles into `STANDARDIZED_ROLE` (8 categories) | As specified. Input: `DEV_TYPE` |
| FR-15 | `SNOWFLAKE.CORTEX.COMPLETE()` assigns respondents to skill clusters stored as `SKILL_CLUSTER` (8 clusters) | As specified. Model: `mistral-7b`. Input: `LANGUAGE_HAVE_WORKED_WITH`. Non-conforming responses are mapped to `Other` |
| FR-16 | `ENRICHED.SALARY_FORECAST_RESULTS` contains Cortex ML FORECAST output using experience as the pseudo-time axis | As specified. 10 forecast periods per country series, 80% prediction interval |

Also delivered: `AI_ATTITUDE_CATEGORY` via `CLASSIFY_TEXT` on the AI sentiment answer (4 categories), and `ENRICHED.SALARY_BENCHMARKS` (pre-aggregated percentiles).

### Layer: Search (FR-17)

| ID | Requirement | As built |
|---|---|---|
| FR-17 | A Cortex Search service (`DEVPULSE_SEARCH`) is created over `ENRICHED_RESPONSES` | Built over `V_SEARCH_PROFILES` (composite `PROFILE_TEXT`), indexing rows with a non-null `SKILL_CLUSTER` |

### Application (FR-18 to FR-20)

| ID | Requirement | As built |
|---|---|---|
| FR-18 | A Streamlit in Snowflake app provides four views: Salary Explorer, AI Adoption Dashboard, Skill Demand Analyzer, Semantic Search | As specified |
| FR-19 | All charts and filters respond to user input without error | Charts verified at build time (see screenshots). The "Where Do I Stand?" widget likely returns "Not enough data" for all inputs (Known Issue 5, found by code review) |
| FR-20 | Semantic Search returns ranked results via Cortex Search | As specified |

---

## 6. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Cost | Cortex LLM enrichment should run on a representative sample, with cost measured on a small batch before scaling. **Not met in the executed build**; see Section 9 |
| Reproducibility | A third party with a Snowflake trial account can rebuild the project by following `setup.md` |
| Portability | No external dependencies. All objects reside in the Snowflake account |
| Idempotency | SQL scripts use `CREATE OR REPLACE` or `IF NOT EXISTS`. Exception: `04_cortex_enrich.sql` and `05_cortex_ml.sql` re-bill Cortex usage on every re-run |
| Documentation | Design rationale is recorded in `decisions.md`; the object inventory is in `architecture.md` |

---

## 7. Assumptions

- The survey dataset is downloaded manually from https://survey.stackoverflow.co/
- A Snowflake trial account with Cortex AI features enabled in its region is available
- The builder has Snowsight access and the ACCOUNTADMIN role during setup
- Cortex LLM functions (`COMPLETE`, `CLASSIFY_TEXT`, `SENTIMENT`) are available in the account's cloud region
- **Not validated before build:** that each enrichment input column contains free text. JobSat did not (see Section 10)

---

## 8. Constraints

- Snowflake trial accounts have a fixed credit allotment, so the design must minimize idle compute
- Cortex LLM functions bill per token
- No external tooling: all pipeline logic uses native Snowflake objects
- The dataset is static (single survey vintage)
- **Post-build:** the trial account has expired, so code cannot be re-executed. Post-build findings are documented, not patched

---

## 9. Success Criteria (post-build review, v1.2)

| Criterion | Measure | Status |
|---|---|---|
| Six Snowflake capabilities demonstrated | Stage/pipe, Dynamic Tables, Cortex LLM, Cortex ML, Cortex Search, Streamlit present and executed | ✅ Met, with a caveat: pipe defined (`AUTO_INGEST = FALSE`), load executed via manual `COPY INTO` |
| Working Streamlit app | All four views render without error | ✅ Met. See screenshots. One widget has a logic defect found by code review (Known Issue 5) |
| Enrichment materialized | Cortex results stored in tables, not computed live | ✅ Met |
| Enrichment coverage | PCT_SENTIMENT ≥ 60%, PCT_STD_ROLE ≥ 80%, PCT_SKILL_CLUSTER ≥ 50% | ❌ Sentiment not met: only ~55.7% of in-scope respondents answered JobSat (estimated from source CSV; build-time coverage output not retained). The SENTIMENT input is also numeric, so even covered rows carry no meaningful signal. Role and skill-cluster coverage not re-verifiable |
| Cost-conscious enrichment | LLM enrichment on a representative sample, cost measured before scaling | ❌ Not met in the executed build. Enrichment ran on all in-scope rows (~51.5K, estimated from source CSV) and consumed ~$88 of trial credits (~$70 AI_SERVICES). Sampling is documented as the remediation and was not executed |
| Documentation | BRD, architecture, decisions, setup, DEVLOG, README complete and consistent with code | ✅ Met after the v1.2 post-build alignment |
| Reproducible | A third party can rebuild from `setup.md` | ⚠️ Untested. No independent rebuild has been performed; the original trial account has expired |

> **Cost history:** v1.0 specified total spend under $5. v1.1 revised the criterion to "≤10% sample" and marked it met. That was inaccurate, because the sample was never executed. v1.2 corrects the status to "not met in executed build" and identifies a second root cause: redundant per-row Cortex calls. See `README.md` → Cost Retrospective.

---

## 10. Risk Register

| Risk | Likelihood | Impact | Status / Mitigation |
|---|---|---|---|
| Cortex not available in trial region | Medium | High | Did not occur. Checked before setup (`setup.md` prerequisites) |
| Cortex LLM costs exceed expectations at scale | — | High | **Realized.** Remediation for rebuilds: profile inputs, pilot on 100 rows, sample the Cortex steps, one call per function per row |
| Enrichment input is not the expected data type | — | High | **Realized** (JobSat numeric). Remediation: profile every input column before any Cortex call |
| Dynamic Tables auto-refresh consuming credits | Low | Medium | Mitigated: `TARGET_LAG = '9999 days'` on both tables |
| CSV schema changes between survey vintages | Low | Medium | Column mapping centralized in `01_staging.sql` (RAW) and `03_dynamic_tables.sql` (CLEAN) |
| Cortex Search indexing lag causes silent failures | Low | Medium | Mitigated: `SEARCH_PREVIEW` validation in `setup.md` before opening the app |
| Rows silently dropped at load (`ON_ERROR = 'CONTINUE'`) | Low | Medium | **Did not occur (by source-file check).** Every CSV record has exactly 114 fields and there are no embedded newlines, so no malformed rows were expected. Rebuilds should still compare the RAW count with 65,437 |
| Trial account expires | — | High | **Realized after completion.** Code preserved as executed; findings documented |

---

## 11. Change Log

| Version | Date | Change |
|---|---|---|
| 1.0 | May 2026 | Initial requirements |
| 1.1 | May 2026 | Cost criterion revised from "< $5 total" to "≤10% sample" after the ~$88 overrun |
| 1.2 | September 2026 | Post-build review. Aligned FRs with as-built code (FR-14/FR-15 function assignments corrected, stage name, pipe usage). Re-scored success criteria (cost and sentiment-coverage criteria corrected to not met; reproducibility qualified). In-scope row count established at ~51.5K by source-file profiling; an earlier ~23K figure was the salaried-developer count shown by the app's KPI card. Added realized risks. Author name filled in |
