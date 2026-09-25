# Setup Guide: DevPulseIntel

**Estimated time:** about 2 hours end to end
**Prerequisites:** a Snowflake trial account with Cortex enabled in its region, and the survey CSV downloaded

> **About this guide:** This guide is for **rebuilding** the project. Where the recommended rebuild path differs from what the original May 2026 build did, a **Note** says so. The original build skipped Step 5 (input profiling) and ran enrichment unsampled. The SQL files in `sql/` are the source of truth for code; this guide only describes how to run them.

---

## Before You Start

1. Download the Stack Overflow Developer Survey 2024 from https://survey.stackoverflow.co/
2. Extract the zip. You need `survey_results_public.csv` (65,437 rows).
3. Confirm your Snowflake account region supports Cortex LLM functions (`SENTIMENT`, `CLASSIFY_TEXT`, `COMPLETE` with `mistral-7b`), Cortex ML FORECAST, and Cortex Search.

---

## Step 1: Run `sql/01_staging.sql`

This creates the database, schemas, warehouses, file format, internal stage, the RAW table, and the pipe.

Expected output from the final verification block:
```
SHOW SCHEMAS     → INGESTION, RAW, CLEAN, ANALYTICS, ENRICHED (plus INFORMATION_SCHEMA, PUBLIC)
SHOW WAREHOUSES  → DEVPULSE_LOAD_WH, DEVPULSE_TRANSFORM_WH, DEVPULSE_CORTEX_WH, DEVPULSE_APP_WH
SHOW STAGES      → RAW_STAGE
SHOW PIPES       → SURVEY_PIPE
DESCRIBE TABLE   → 116 rows (114 survey columns + _SOURCE_FILE_NAME + _LOAD_TIMESTAMP)
```

**Note:** `SURVEY_PIPE` is defined with `AUTO_INGEST = FALSE`. It is not used for the load; Step 3 loads the data with a manual `COPY INTO`.

---

## Step 2: Upload the CSV to the Stage

**Option A: Snowsight UI (recommended)**
1. Go to **Data → Databases → DEVPULSEINTEL → INGESTION → Stages → RAW_STAGE**.
2. Click **+ Files** and select `survey_results_public.csv`.

**Option B: SnowSQL CLI**
```sql
PUT file:///path/to/survey_results_public.csv
    @DEVPULSEINTEL.INGESTION.RAW_STAGE
    AUTO_COMPRESS = FALSE;
```

Verify:
```sql
LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE;
-- Expected: one row with the CSV file name and size
```

---

## Step 3: Run `sql/02_raw_load.sql`

Run Section 1 (pre-load preview) first. If values land in the wrong columns, stop: the `$N` positional references are misaligned.

Then run Section 2 (`COPY INTO`) and Section 3 (validation).

```sql
SELECT COUNT(*) FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;
-- Expected: 65,437 (the source CSV row count)
```

**Check for dropped rows.** The load uses `ON_ERROR = 'CONTINUE'`, which skips malformed rows silently. If the count is below 65,437, find out why before continuing:
```sql
-- ACCOUNT_USAGE has up to 2 hours of latency
SELECT FILE_NAME, STATUS, ROW_COUNT, ROW_PARSED, ERROR_COUNT, FIRST_ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE TABLE_NAME = 'RAW_SURVEY_RESPONSES'
  AND LAST_LOAD_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY LAST_LOAD_TIME DESC;
```

**Note:** The original build did not record this check. A post-build check of the source file found every record has exactly 114 fields and no embedded newlines, so a full load of 65,437 rows is expected.

---

## Step 4: Run `sql/03_dynamic_tables.sql`

This creates `CLEAN.DT_CLEAN_RESPONSES`, `ANALYTICS.DT_ANALYTICS_DEVELOPERS`, and three supporting views, then triggers the one-time manual refresh (Section 4).

Verify:
```sql
SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;
-- Expected: 2 rows, TARGET_LAG = '9999 days' for both

SELECT 'RAW' AS LAYER, COUNT(*) AS ROW_COUNT FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
UNION ALL
SELECT 'CLEAN',        COUNT(*)               FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
UNION ALL
SELECT 'ANALYTICS',    COUNT(*)               FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;
-- Expected if all rows load: RAW 65,437 · CLEAN ≈ RAW · ANALYTICS ≈ 51.5K (estimated from source CSV)
```

---

## Step 5: Profile enrichment inputs (recommended; not done in the original build)

Every Cortex call costs money, so confirm each input column contains what the prompt assumes **before** running Step 6. This step would have caught the JobSat problem (README Known Issue 2) for free.

```sql
SELECT JOB_SAT, COUNT(*) FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;
-- 2024 survey: 0–10 integers. SENTIMENT on this column is not meaningful.

SELECT DEV_TYPE, COUNT(*) FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;

SELECT LANGUAGE_HAVE_WORKED_WITH FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
WHERE LANGUAGE_HAVE_WORKED_WITH IS NOT NULL LIMIT 20;

SELECT AI_SENTIMENT_RAW, COUNT(*) FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;
```

**Pilot the cost.** Before running any Cortex section on the full table, run it on about 100 rows, check the AI_SERVICES consumption for that run, and multiply out to your planned row count.

---

## Step 6: Run `sql/04_cortex_enrich.sql`

This populates `ENRICHED.ENRICHED_RESPONSES` with Cortex outputs.

### Choose where to sample

Cortex LLM cost scales with rows × calls per row × tokens per call. There are two ways to sample:

**Option A: Sample the seed (simplest).** In Section 2, add `SAMPLE (10 PERCENT)` after `FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS`.
- Trade-off: `05_cortex_ml.sql` and the benchmarks read from this same table. With only ~10% of the rows, many (country, experience) cells fall below the `HAVING COUNT(*) >= 5` and `>= 10` thresholds, so the forecast and "Where Do I Stand?" data become sparse.

**Option B: Sample the Cortex steps only (recommended).** Keep the Section 2 seed unsampled, create a sample of IDs, and restrict each Cortex `UPDATE` to it:
```sql
CREATE OR REPLACE TABLE DEVPULSEINTEL.ENRICHED.ENRICH_SAMPLE AS
SELECT RESPONSE_ID
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS SAMPLE (10 PERCENT);

-- Then add to the WHERE clause of each Cortex UPDATE (Sections 3–6):
--   AND e.RESPONSE_ID IN (SELECT RESPONSE_ID FROM DEVPULSEINTEL.ENRICHED.ENRICH_SAMPLE)
```
- Trade-off: coverage percentages in Section 7 will read about 10% by design. Measure coverage against `ENRICH_SAMPLE` instead.

**Note:** The original build used neither option. Enrichment ran on every ANALYTICS row and consumed ~$88 of trial credits (~$70 AI_SERVICES). See `README.md` → Cost Retrospective.

### Run the sections in order

| Section | What it does | Expected time (unsampled) |
|---|---|---|
| 1 | CREATE TABLE | Seconds |
| 2 | INSERT seed rows from ANALYTICS | Seconds |
| 3 | SENTIMENT UPDATE | 5–15 min |
| 4 | CLASSIFY_TEXT UPDATE (role standardization) | 10–20 min |
| 5 | COMPLETE UPDATE (skill clustering), then cleanup to `Other` | 20–40 min |
| 6 | CLASSIFY_TEXT UPDATE (AI attitude) | 5–10 min |
| 7 | Coverage check | Seconds |

**Note:** As written, Sections 3–5 call each Cortex function more than once per row (README Known Issue 1). Running the scripts unchanged roughly doubles LLM cost compared with a single call per row.

Expected coverage from Section 7 (unsampled, or measured within the sample for Option B):
```
PCT_SENTIMENT      ~56%    (BRD target was 60%, but only ~56% of ANALYTICS rows answered JobSat)
PCT_STD_ROLE       ≥ 80%
PCT_SKILL_CLUSTER  ≥ 50%
PCT_AI_ATTITUDE    ≥ 50%
```
If any value is 0%, the UPDATE in that section didn't run. Re-run that section only.

---

## Step 7: Run `sql/05_cortex_ml.sql`

This trains `SALARY_FORECAST_MODEL` and builds `SALARY_FORECAST_RESULTS`, `SALARY_BENCHMARKS`, and `V_SALARY_ACTUAL_VS_FORECAST`. Training (Section 2) takes 2–5 minutes.

Section 3 uses `RESULT_SCAN(LAST_QUERY_ID())`, so run the `CALL ...!FORECAST` and the `INSERT` immediately one after the other, with nothing in between.

Verify:
```sql
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: one row, NAME = SALARY_FORECAST_MODEL

SELECT SERIES, ROUND(AVG(FORECAST), 0) AS AVG_PREDICTED_SALARY
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
GROUP BY 1 ORDER BY AVG_PREDICTED_SALARY DESC LIMIT 5;
-- Expected: uppercase country names (e.g. UNITED STATES OF AMERICA), values in the $30K–$300K range
```

---

## Step 8: Run `sql/06_cortex_search.sql`

Run Sections 1 and 2 (view and service creation), then wait for the service to become active:
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Re-run until the service shows as ACTIVE (typically 2–5 minutes)
```

Then run the Section 4 test queries.

**Note:** Test 2 filters on `"United States of America"`, but `COUNTRY` is uppercased in the CLEAN layer, so Test 2 returns no rows. Use `"UNITED STATES OF AMERICA"` instead.

---

## Step 9: Deploy the Streamlit App

1. In Snowsight, open **Streamlit** and click **+ Streamlit App**.
2. Configure:
   - **App name:** `DEVPULSEINTEL_APP`
   - **Warehouse:** `DEVPULSE_APP_WH`
   - **Database / Schema:** `DEVPULSEINTEL` / `ENRICHED`
3. Replace the editor contents with `streamlit/app.py`, then click **Run**.

Expected: a sidebar with four navigation options, and all pages render.

**Note:** In the original build, the app kept Snowsight's auto-generated name rather than `DEVPULSEINTEL_APP`.

---

## Verification Checklist

Each item maps to a BRD Section 9 criterion. Run the check before ticking the box.

### SC-01: Capabilities present and executed

- [ ] Pipe exists
```sql
SHOW PIPES IN SCHEMA DEVPULSEINTEL.INGESTION;   -- SURVEY_PIPE
```
- [ ] Both Dynamic Tables exist with `TARGET_LAG = '9999 days'`
```sql
SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;
```
- [ ] Forecast model exists and results look realistic (Step 7 queries)
- [ ] Cortex Search service is active (Step 8)
- [ ] App exists
```sql
SHOW STREAMLITS IN SCHEMA DEVPULSEINTEL.ENRICHED;   -- one row
```

### SC-02: App views functional (manual)

- [ ] **Salary Explorer:** KPI cards show non-zero values; experience and salary band charts render; the forecast chart shows actual and forecast lines
- [ ] **Salary Explorer, "Where Do I Stand?":** see README Known Issue 5 before expecting results
- [ ] **AI Adoption:** adoption rate > 0%; the attitude donut chart has segments
- [ ] **Skill Demand:** the cluster salary and top languages charts render
- [ ] **Semantic Search:** a query returns result cards

Validate search before opening the app:
```sql
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{"query": "Python developer with data engineering experience",
      "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER"],
      "limit": 3}'
) AS RESULTS;
-- Expected: JSON with a results array of 3 items
```

### SC-03: Enrichment materialized

- [ ] Cortex columns are physical columns in a base table
```sql
SELECT COLUMN_NAME, DATA_TYPE
FROM DEVPULSEINTEL.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'ENRICHED'
  AND TABLE_NAME   = 'ENRICHED_RESPONSES'
  AND COLUMN_NAME IN ('JOB_SAT_SENTIMENT_SCORE', 'STANDARDIZED_ROLE',
                      'SKILL_CLUSTER', 'AI_ATTITUDE_CATEGORY');
-- Expected: 4 rows
```

### SC-04: Enrichment coverage

- [ ] Section 7 of `04_cortex_enrich.sql` meets the thresholds in Step 6

### SC-05: Cost

- [ ] Inputs profiled (Step 5) and cost piloted on ~100 rows before full enrichment
- [ ] Sampling applied (Step 6, Option A or B)
- [ ] Total consumption checked: Snowsight → **Admin → Cost Management**, filtered to your build dates

Rough expectation for a sampled rebuild (**extrapolated from the original build's actuals; unverified**):
```
Warehouse compute (4 × XS, one-time build)     a few dollars
AI_SERVICES, scripts run as-is (10% sample)    ~$7
AI_SERVICES, one call per function per row     ~$3–4
```
If AI_SERVICES approaches ~$70, enrichment ran unsampled.

### SC-06: Documentation present

- [ ] Repo contains `README.md`, `BRD.md`, `architecture.md`, `decisions.md`, `setup.md`, `DEVLOG.md`, `sql/01–06`, `streamlit/app.py`, `screenshots/`

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `LIST @RAW_STAGE` returns 0 rows | File not uploaded yet | Upload the CSV, then re-run |
| RAW row count below 65,437 | Rows skipped by `ON_ERROR = 'CONTINUE'` | Check `COPY_HISTORY` (Step 3) for the first error message |
| COPY INTO: `invalid identifier` | Wrong table name or session context | `SHOW TABLES IN SCHEMA DEVPULSEINTEL.RAW` |
| Dynamic Table has 0 rows after refresh | RAW was empty at refresh time | Load RAW first, then re-run `ALTER DYNAMIC TABLE ... REFRESH` |
| `unexpected '='` in CREATE TABLE | Inline `COMMENT =` on a column | Use separate `COMMENT ON COLUMN` statements |
| `Bulk grant on PIPE is restricted` | `GRANT ... ON ALL PIPES` is not allowed | Grant on each pipe individually |
| Forecast `INSERT` returns wrong data or fails | Another query ran between `CALL` and `RESULT_SCAN(LAST_QUERY_ID())` | Re-run the `CALL`, then the `INSERT` immediately |
| Cortex Search returns empty results | Service still initializing, or `SKILL_CLUSTER` is all NULL | Wait for ACTIVE; check SC-04 coverage |
| Streamlit query error | Column name mismatch | `DESCRIBE TABLE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES` |
| AI_SERVICES cost ~$70+ | Enrichment ran unsampled | Expected without sampling. See README → Cost Retrospective |
