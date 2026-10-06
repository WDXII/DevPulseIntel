# Setup Guide: DevPulseIntel

**Time:** about 2 hours · **Prerequisites:** a Snowflake trial account with Cortex enabled in its region, and the survey CSV

> This guide is for **rebuilding**. Where the recommended path differs from the original May 2026 build, a **Note** says so. The original skipped Step 5 (input profiling) and ran enrichment unsampled. `sql/` is the source of truth for code; this guide only says how to run it.

---

## Before You Start
1. Download the 2024 survey from https://survey.stackoverflow.co/ and extract `survey_results_public.csv` (65,437 rows).
2. Confirm your region supports Cortex LLM (`SENTIMENT`, `CLASSIFY_TEXT`, `COMPLETE` with `mistral-7b`), Cortex ML FORECAST, and Cortex Search.

## Step 1: Run `sql/01_staging.sql`
Creates the database, schemas, warehouses, file format, stage, RAW table, and pipe. Expected from the verification block:
```
SHOW SCHEMAS     → INGESTION, RAW, CLEAN, ANALYTICS, ENRICHED (plus INFORMATION_SCHEMA, PUBLIC)
SHOW WAREHOUSES  → DEVPULSE_LOAD_WH, DEVPULSE_TRANSFORM_WH, DEVPULSE_CORTEX_WH, DEVPULSE_APP_WH
SHOW STAGES      → RAW_STAGE
SHOW PIPES       → SURVEY_PIPE
DESCRIBE TABLE   → 116 rows (114 survey columns + _SOURCE_FILE_NAME + _LOAD_TIMESTAMP)
```
**Note:** `SURVEY_PIPE` has `AUTO_INGEST = FALSE` and isn't used; Step 3 loads with `COPY INTO`.

## Step 2: Upload the CSV
**Snowsight (recommended):** Data → Databases → DEVPULSEINTEL → INGESTION → Stages → RAW_STAGE → **+ Files**.
**SnowSQL:**
```sql
PUT file:///path/to/survey_results_public.csv @DEVPULSEINTEL.INGESTION.RAW_STAGE AUTO_COMPRESS = FALSE;
LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE;   -- expect one row
```

## Step 3: Run `sql/02_raw_load.sql`
Run Section 1 (preview) first; if values land in the wrong columns, the `$N` positions are misaligned, so stop. Then run Section 2 (`COPY INTO`) and Section 3 (validation).
```sql
SELECT COUNT(*) FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;   -- expect 65,437
```
`ON_ERROR = 'CONTINUE'` skips bad rows silently. If the count is low, find out why:
```sql
-- ACCOUNT_USAGE lags up to 2 hours
SELECT FILE_NAME, STATUS, ROW_COUNT, ROW_PARSED, ERROR_COUNT, FIRST_ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE TABLE_NAME = 'RAW_SURVEY_RESPONSES'
  AND LAST_LOAD_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY LAST_LOAD_TIME DESC;
```
**Note:** the original build didn't record this check. A later source-file check found 114 fields in every record and no embedded newlines, so a full 65,437-row load is expected.

## Step 4: Run `sql/03_dynamic_tables.sql`
Creates `CLEAN.DT_CLEAN_RESPONSES`, `ANALYTICS.DT_ANALYTICS_DEVELOPERS`, three views, and runs the one-time manual refresh.
```sql
SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;   -- 2 rows, TARGET_LAG = '9999 days'

SELECT 'RAW' AS LAYER, COUNT(*) AS ROW_COUNT FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
UNION ALL SELECT 'CLEAN',     COUNT(*) FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
UNION ALL SELECT 'ANALYTICS', COUNT(*) FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;
-- Expected: RAW 65,437 · CLEAN ≈ RAW · ANALYTICS ≈ 51.5K (51,525, estimated from the CSV)
```

## Step 5: Profile enrichment inputs (recommended; skipped in the original build)
Every Cortex call costs money, so confirm each input holds what the prompt assumes **before** Step 6. This free step would have caught the JobSat problem (README Known Issue 2).
```sql
SELECT JOB_SAT, COUNT(*) FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;      -- 2024: 0–10 integers; SENTIMENT is not meaningful on this

SELECT DEV_TYPE, COUNT(*) FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;

SELECT LANGUAGE_HAVE_WORKED_WITH FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
WHERE LANGUAGE_HAVE_WORKED_WITH IS NOT NULL LIMIT 20;

SELECT AI_SENTIMENT_RAW, COUNT(*) FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;
```
**Pilot the cost.** Run each Cortex section on ~100 rows, check that run's AI_SERVICES consumption, and multiply out to your planned row count.

## Step 6: Run `sql/04_cortex_enrich.sql`
Populates `ENRICHED.ENRICHED_RESPONSES`. Cost = rows × calls per row × tokens per call, so choose where to sample:

**Option A: sample the seed (simplest).** In Section 2, add `SAMPLE (10 PERCENT)` after `FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS`. Trade-off: `05_cortex_ml.sql` and the benchmarks read this table too, and at ~10% many cells fall below their `HAVING COUNT(*) >= 5` / `>= 10` thresholds, leaving the forecast and "Where Do I Stand?" data sparse.

**Option B: sample only the Cortex steps (recommended).** Keep the seed unsampled and restrict each Cortex `UPDATE` to a sampled ID set:
```sql
CREATE OR REPLACE TABLE DEVPULSEINTEL.ENRICHED.ENRICH_SAMPLE AS
SELECT RESPONSE_ID
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS SAMPLE (10 PERCENT);

-- Add to the WHERE clause of each Cortex UPDATE (Sections 3–6):
--   AND e.RESPONSE_ID IN (SELECT RESPONSE_ID FROM DEVPULSEINTEL.ENRICHED.ENRICH_SAMPLE)
```
Trade-off: Section 7 coverage reads ~10% by design; measure against `ENRICH_SAMPLE` instead.

**Note:** the original build used neither option; it enriched every ANALYTICS row for ~$88 (~$70 AI_SERVICES). See README → Cost Retrospective.

| Section | Does | Time (unsampled) |
|---|---|---|
| 1–2 | CREATE TABLE; INSERT seed from ANALYTICS | Seconds |
| 3 | SENTIMENT UPDATE | 5–15 min |
| 4 | CLASSIFY_TEXT (roles) | 10–20 min |
| 5 | COMPLETE (skill clusters), then cleanup to `Other` | 20–40 min |
| 6 | CLASSIFY_TEXT (AI attitude) | 5–10 min |
| 7 | Coverage check | Seconds |

**Note:** Sections 3–5 call each function more than once per row (Known Issue 1), roughly doubling LLM cost versus one call per row.

Expected Section 7 coverage (unsampled, or within the sample for Option B):
```
PCT_SENTIMENT      ~56%   (BRD target 60%; only ~56% of ANALYTICS rows answered JobSat)
PCT_STD_ROLE       ≥ 80%
PCT_SKILL_CLUSTER  ≥ 50%
PCT_AI_ATTITUDE    ≥ 50%
```
A value of 0% means that section's `UPDATE` didn't run; re-run just that section.

## Step 7: Run `sql/05_cortex_ml.sql`
Trains `SALARY_FORECAST_MODEL` (2–5 min) and builds `SALARY_FORECAST_RESULTS`, `SALARY_BENCHMARKS`, `V_SALARY_ACTUAL_VS_FORECAST`. Section 3 uses `RESULT_SCAN(LAST_QUERY_ID())`: run the `CALL ...!FORECAST` and the `INSERT` back to back, with nothing between.
```sql
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;   -- one row: SALARY_FORECAST_MODEL

SELECT SERIES, ROUND(AVG(FORECAST), 0) AS AVG_PREDICTED_SALARY
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
GROUP BY 1 ORDER BY AVG_PREDICTED_SALARY DESC LIMIT 5;
-- Expect uppercase country names, values roughly $30K–$300K
```

## Step 8: Run `sql/06_cortex_search.sql`
Run Sections 1–2 (view, service), then wait for it to go active (typically 2–5 min):
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
```
Then run the Section 4 tests. **Note:** Test 2 filters on `"United States of America"` but `COUNTRY` is uppercase in CLEAN, so it returns no rows; use `"UNITED STATES OF AMERICA"`.

## Step 9: Deploy the Streamlit app
1. Snowsight → **Streamlit** → **+ Streamlit App**.
2. App name `DEVPULSEINTEL_APP`; warehouse `DEVPULSE_APP_WH`; database/schema `DEVPULSEINTEL` / `ENRICHED`.
3. Paste in `streamlit/app.py` and click **Run**. Expect a four-option sidebar with all pages rendering.

**Note:** the original build kept Snowsight's auto-generated app name.

---

## Verification Checklist
Each group maps to a BRD §9 criterion. Run the check before ticking.

**SC-01 Capabilities present**
- [ ] `SHOW PIPES IN SCHEMA DEVPULSEINTEL.INGESTION;` → `SURVEY_PIPE`
- [ ] `SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;` → both at `9999 days`
- [ ] Forecast model exists and results look realistic (Step 7)
- [ ] Search service active (Step 8)
- [ ] `SHOW STREAMLITS IN SCHEMA DEVPULSEINTEL.ENRICHED;` → one row

**SC-02 App views work** (manual)
- [ ] Salary Explorer: KPIs non-zero; experience, band, and forecast charts render
- [ ] "Where Do I Stand?": see Known Issue 5 before expecting results
- [ ] AI Adoption: rate > 0%; attitude donut has segments
- [ ] Skill Demand: cluster salary and top-language charts render
- [ ] Semantic Search: a query returns cards. Check first in SQL:
```sql
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{"query": "Python developer with data engineering experience",
      "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER"], "limit": 3}'
) AS RESULTS;   -- expect a results array of 3
```

**SC-03 Enrichment materialized**
- [ ] Cortex columns are physical columns (expect 4 rows):
```sql
SELECT COLUMN_NAME, DATA_TYPE FROM DEVPULSEINTEL.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'ENRICHED' AND TABLE_NAME = 'ENRICHED_RESPONSES'
  AND COLUMN_NAME IN ('JOB_SAT_SENTIMENT_SCORE','STANDARDIZED_ROLE','SKILL_CLUSTER','AI_ATTITUDE_CATEGORY');
```

**SC-04 Coverage**
- [ ] Section 7 of `04_cortex_enrich.sql` meets the Step 6 thresholds

**SC-05 Cost**
- [ ] Inputs profiled (Step 5) and cost piloted on ~100 rows
- [ ] Sampling applied (Step 6, A or B)
- [ ] Total checked: Snowsight → **Admin → Cost Management**, filtered to your build dates

Rough sampled-rebuild estimate (**extrapolated from the original actuals; unverified**): warehouses a few dollars; AI_SERVICES ~$7 for scripts as-is at 10%, ~$3–4 with one call per function per row. If AI_SERVICES nears ~$70, enrichment ran unsampled.

**SC-06 Docs present**
- [ ] `README.md`, `BRD.md`, `architecture.md`, `decisions.md`, `setup.md`, `DEVLOG.md`, `sql/01–06`, `streamlit/app.py`, `screenshots/`

---

## Troubleshooting

| Symptom | Cause → Fix |
|---|---|
| `LIST @RAW_STAGE` returns 0 rows | File not uploaded → upload, re-run |
| RAW count below 65,437 | `ON_ERROR = 'CONTINUE'` skipped rows → check `COPY_HISTORY` (Step 3) |
| COPY INTO `invalid identifier` | Wrong table or session context → `SHOW TABLES IN SCHEMA DEVPULSEINTEL.RAW` |
| Dynamic Table has 0 rows | RAW was empty at refresh → load RAW, then `ALTER DYNAMIC TABLE ... REFRESH` |
| `unexpected '='` in CREATE TABLE | Inline `COMMENT =` → use `COMMENT ON COLUMN` |
| `Bulk grant on PIPE is restricted` | Grant per pipe |
| Forecast `INSERT` wrong or fails | A query ran between `CALL` and `RESULT_SCAN` → re-run both back to back |
| Search returns nothing | Still initializing, or `SKILL_CLUSTER` all NULL → wait for ACTIVE; check SC-04 |
| Streamlit query error | Column mismatch → `DESCRIBE TABLE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES` |
| AI_SERVICES ~$70+ | Enrichment ran unsampled → see README → Cost Retrospective |
