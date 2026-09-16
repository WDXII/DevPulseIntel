# Setup Guide
## DevPulseIntel — Developer Ecosystem Intelligence Platform

**Estimated time:** 2 hours end-to-end
**Prerequisites:** Snowflake trial account, survey CSV downloaded

---

## Before You Start

1. Download the Stack Overflow Developer Survey 2024 from https://survey.stackoverflow.co/
2. Extract the zip — you need `survey_results_public.csv`
3. Confirm your Snowflake trial account has Cortex features enabled for your region

---

## Step 1 — Run `01_staging.sql`

Creates the database, schemas, warehouses, file format, internal stage, RAW table DDL, and Snowpipe.

Run the full script in Snowsight. Expected output from the final verification block:
```
SHOW SCHEMAS        → 5 rows (INGESTION, RAW, CLEAN, ANALYTICS, ENRICHED)
SHOW WAREHOUSES     → 4 rows (DEVPULSE_LOAD_WH, TRANSFORM_WH, CORTEX_WH, APP_WH)
SHOW STAGES         → 1 row  (RAW_STAGE)
SHOW PIPES          → 1 row  (SURVEY_PIPE)
DESCRIBE TABLE      → 116 rows (114 survey columns + _SOURCE_FILE_NAME + _LOAD_TIMESTAMP)
```

---

## Step 2 — Upload the CSV to the Stage

**Option A — Snowsight UI (recommended)**
1. Navigate to **Data → Databases → DEVPULSEINTEL → INGESTION → Stages → RAW_STAGE**
2. Click **+ Files** and select `survey_results_public.csv`
3. Wait for the upload to complete

**Option B — SnowSQL CLI**
```sql
PUT file:///path/to/survey_results_public.csv
    @DEVPULSEINTEL.INGESTION.RAW_STAGE
    AUTO_COMPRESS = FALSE;
```

**Verify the file is staged:**
```sql
LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE;
-- Expected: one row showing the CSV file name and size
-- Zero rows = file not uploaded yet (not an error — the stage exists)
```

---

## Step 3 — Run `02_raw_load.sql`

Loads the CSV into `RAW.RAW_SURVEY_RESPONSES`.

Run Section 1 (pre-load preview) first to confirm column alignment:
```sql
SELECT $1 AS RESPONSEID_PREVIEW, $20 AS COUNTRY_PREVIEW, $114 AS JOBSAT_PREVIEW
FROM @DEVPULSEINTEL.INGESTION.RAW_STAGE
(FILE_FORMAT => 'DEVPULSEINTEL.INGESTION.SURVEY_CSV_FORMAT')
LIMIT 5;
```
If values are in the wrong columns, the $N positional references are misaligned — stop and investigate before loading.

Then run Section 2 (COPY INTO). Expected output from Section 3 verification:
```sql
SELECT COUNT(*) AS ROW_COUNT FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;
-- Expected: ~65,000
```

**Load history (if needed):**
```sql
-- ACCOUNT_USAGE has up to 2 hours latency — use COUNT(*) for immediate confirmation
SELECT FILE_NAME, STATUS, ROW_COUNT, ERROR_COUNT, FIRST_ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE TABLE_NAME = 'RAW_SURVEY_RESPONSES'
  AND LAST_LOAD_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY LAST_LOAD_TIME DESC;
```

---

## Step 4 — Run `03_dynamic_tables.sql`

Creates `CLEAN.DT_CLEAN_RESPONSES` and `ANALYTICS.DT_ANALYTICS_DEVELOPERS`, then triggers an initial manual refresh.

Run the full script. Section 4 triggers the refresh automatically:
```sql
ALTER DYNAMIC TABLE DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES       REFRESH;
ALTER DYNAMIC TABLE DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS REFRESH;
```

Verify via Section 5:
```sql
SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;
-- Expected: 2 rows, TARGET_LAG = '9999 days' for both

SELECT 'RAW' AS LAYER, COUNT(*) AS ROW_COUNT FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
UNION ALL
SELECT 'CLEAN',        COUNT(*)               FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
UNION ALL
SELECT 'ANALYTICS',    COUNT(*)               FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;
-- Expected: RAW ~65K, CLEAN slightly less (WHERE RESPONSEID IS NOT NULL), ANALYTICS lower (professional devs only)
```

---

## Step 5 — Run `04_cortex_enrich.sql`

Populates `ENRICHED.ENRICHED_RESPONSES` with Cortex LLM outputs on a **10% sample** of professional developers.

### Why apply a sample?

Cortex LLM functions (`COMPLETE`, `CLASSIFY_TEXT`) bill per token. Running enrichment on the full 65,000 respondent dataset costs approximately **$70–$88 in AI_SERVICES credits**. A 10% sample (~6,500 professional developers) costs **~$7–$8** and demonstrates the full capability equally well for portfolio purposes. 

This is a deliberate engineering tradeoff: **representativeness vs. cost efficiency**. The sample is large enough to populate meaningful aggregations and trends in the Streamlit app. This approach is documented in **BRD.md Section 9 (Success Criteria, revised)** and explained in depth in **README.md → Cost Profile**.

### How sampling is applied

Before running Step 5, modify Section 2 of `04_cortex_enrich.sql`:

**Original:**
```sql
INSERT INTO DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
SELECT * FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;
```

**Updated (add SAMPLE clause):**
```sql
INSERT INTO DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
SELECT * FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
SAMPLE (10 PERCENT);
```

Then run the full script as documented below.

---

### Run Script Sections in Order

Run sections in order:
- Section 1: CREATE TABLE (DDL only — fast)
- Section 2: INSERT seed rows from ANALYTICS with `SAMPLE (10 PERCENT)` (fast)
- Section 3: SENTIMENT UPDATE — expect 5–15 minutes
- Section 4: CLASSIFY_TEXT UPDATE (role standardization) — expect 10–20 minutes
- Section 5: COMPLETE UPDATE (skill clustering) — expect 20–40 minutes, longest section
- Section 6: CLASSIFY_TEXT UPDATE (AI attitude) — expect 5–10 minutes
- Section 7: Coverage check

Expected coverage from Section 7:
```
PCT_SENTIMENT    ≥ 60%
PCT_STD_ROLE     ≥ 80%
PCT_SKILL_CLUSTER ≥ 50%
PCT_AI_ATTITUDE  ≥ 50%
```
If any value is 0%, the UPDATE in that section did not run — re-run that section only.

---

## Step 6 — Run `05_cortex_ml.sql`

Trains the `SALARY_FORECAST_MODEL` and stores results in `SALARY_FORECAST_RESULTS`.

Run the full script. Model training (Section 2) takes 2–5 minutes.

Verify:
```sql
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: one row, NAME = SALARY_FORECAST_MODEL

SELECT SERIES, ROUND(AVG(FORECAST), 0) AS AVG_PREDICTED_SALARY
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
GROUP BY 1 ORDER BY AVG_PREDICTED_SALARY DESC LIMIT 5;
-- Expected: recognisable country names, values in $30K–$300K range
```

---

## Step 7 — Run `06_cortex_search.sql`

Creates the `DEVPULSE_SEARCH` Cortex Search service.

Run Sections 1 and 2 only (view creation + service creation). Do not run Section 4 test queries until the service is ACTIVE.

**Check service status:**
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Wait until STATUS column = ACTIVE (typically 2–5 minutes)
-- Re-run this command until ACTIVE appears
```

Once ACTIVE, run the Section 4 test queries to confirm the index returns results.

---

## Step 8 — Deploy the Streamlit App

1. In Snowsight, click **Streamlit** in the left sidebar
2. Click **+ Streamlit App**
3. Configure:
   - **App name:** `DEVPULSEINTEL_APP`
   - **Warehouse:** `DEVPULSE_APP_WH`
   - **Database:** `DEVPULSEINTEL`
   - **Schema:** `ENRICHED`
4. Select all code in the editor (`Ctrl+A` / `Cmd+A`) and delete it
5. Paste the full contents of `streamlit/app.py`
6. Click **Run**

Expected: app loads with a sidebar showing four navigation options. All pages render without errors.

---

## Verification Checklist

> **How to use this checklist:** Every item maps to a BRD success criterion. Run the SQL, confirm the expected result, then tick the box. Do not tick without running — object existence and object correctness are different things.

---

### SC-01 · All six Snowflake capabilities present and functional

**Snowpipe**
- [ ] `SURVEY_PIPE` exists in `INGESTION` schema
```sql
SHOW PIPES IN SCHEMA DEVPULSEINTEL.INGESTION;
-- Expected: one row, NAME = SURVEY_PIPE
```

**Dynamic Tables — correct lag**
- [ ] Both Dynamic Tables exist with `TARGET_LAG = '9999 days'`
```sql
SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;
-- Expected: two rows — DT_CLEAN_RESPONSES and DT_ANALYTICS_DEVELOPERS
-- TARGET_LAG column must show '9999 days' for both
```

**Cortex LLM — enrichment coverage above thresholds**
- [ ] PCT_SENTIMENT ≥ 60%, PCT_STD_ROLE ≥ 80%, PCT_SKILL_CLUSTER ≥ 50%
```sql
SELECT
    ROUND(SUM(CASE WHEN JOB_SAT_SENTIMENT_SCORE IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1) AS PCT_SENTIMENT,
    ROUND(SUM(CASE WHEN STANDARDIZED_ROLE IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1) AS PCT_STD_ROLE,
    ROUND(SUM(CASE WHEN SKILL_CLUSTER IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1) AS PCT_SKILL_CLUSTER
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES;
-- If any value is 0%: the UPDATE in 04_cortex_enrich.sql did not run for that section
```

**Cortex ML — model and results exist**
- [ ] Model exists and results contain realistic salary values
```sql
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: one row, NAME = SALARY_FORECAST_MODEL

SELECT SERIES, ROUND(AVG(FORECAST), 0) AS AVG_PREDICTED_SALARY
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
GROUP BY 1 ORDER BY AVG_PREDICTED_SALARY DESC LIMIT 5;
-- Expected: recognisable country names, values $30K–$300K
```

**Cortex Search — service active**
- [ ] Service status is ACTIVE
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: one row, NAME = DEVPULSE_SEARCH, STATUS = ACTIVE
-- If INITIALIZING: wait 2–5 minutes and re-run
```

**Streamlit — app deployed**
- [ ] App object exists
```sql
SHOW STREAMLITS IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: one row, NAME = DEVPULSEINTEL_APP
```

---

### SC-02 · Working Streamlit app — all four views functional

Open the deployed app and verify manually:
- [ ] **Salary Explorer** — KPI cards load with non-zero values
- [ ] **Salary Explorer** — salary by experience chart renders
- [ ] **Salary Explorer** — ML Forecast chart shows actual and forecast lines
- [ ] **Salary Explorer** — "Where do I Stand?" widget responds to salary input
- [ ] **AI Adoption Dashboard** — adoption rate > 0%
- [ ] **AI Adoption Dashboard** — AI attitude donut chart has segments
- [ ] **Skill Demand Analyzer** — skill cluster salary chart renders
- [ ] **Skill Demand Analyzer** — top languages chart renders
- [ ] **Semantic Search** — query returns result cards without error

**Validate Semantic Search before opening the app:**
```sql
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query": "Python developer with data engineering experience",
        "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER"],
        "limit": 3
    }'
) AS RESULTS;
-- Expected: JSON with a results array containing 3 items
-- Empty array: confirm ENRICHED_RESPONSES has SKILL_CLUSTER populated (SC-01 check)
```

---

### SC-03 · Enrichment coverage meets thresholds

Already covered in SC-01 Cortex LLM check above.

---

### SC-04 · Enrichment is materialized — not computed at query time

- [ ] Cortex columns are physical table columns, not view expressions
```sql
SELECT COLUMN_NAME, DATA_TYPE
FROM DEVPULSEINTEL.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'ENRICHED'
  AND TABLE_NAME   = 'ENRICHED_RESPONSES'
  AND COLUMN_NAME IN (
      'JOB_SAT_SENTIMENT_SCORE', 'STANDARDIZED_ROLE',
      'SKILL_CLUSTER', 'AI_ATTITUDE_CATEGORY'
  )
ORDER BY COLUMN_NAME;
-- Expected: 4 rows — physical columns in a BASE TABLE
-- 0 rows: table not created correctly — re-run 04_cortex_enrich.sql Section 1
```

---

### SC-05 · Full documentation present

- [ ] All files exist in the project directory
```bash
ls -1
# Expected: BRD.md, architecture.md, setup.md, README.md, DEVLOG.md, .gitignore

ls -1 sql/
# Expected: 01_staging.sql through 06_cortex_search.sql

ls -1 streamlit/
# Expected: app.py
```

---

### SC-06 · Cortex LLM enrichment on representative sample (≤10%)

This criterion verifies that Cortex LLM enrichment is applied to a 10% sample of professional developers, demonstrating cost-conscious design while maintaining capability demonstration.

**Design rationale:**
- Full-dataset Cortex LLM enrichment (65,000 rows) costs ~$70–$88 and is incompatible with cost-efficient portfolio design
- A 10% sample (~6,500 rows) costs ~$7–$8 and produces meaningful results for all analytical views
- This tradeoff is documented in **BRD.md Section 9 (revised success criteria)** and **README.md → Cost Profile**

**Verification:**

- [ ] Step 5 (04_cortex_enrich.sql) applies `SAMPLE (10 PERCENT)` in Section 2
```sql
-- Verify sampling is applied: check that ENRICHED_RESPONSES row count is ~10% of ANALYTICS
SELECT 
    'ANALYTICS (all prof. devs)' AS LAYER, COUNT(*) AS ROW_COUNT 
    FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
UNION ALL
SELECT 'ENRICHED (sampled)', COUNT(*) 
    FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
ORDER BY 1;
-- Expected: ENRICHED row count is roughly 10% of ANALYTICS (e.g., ANALYTICS: 50K, ENRICHED: 5K)
```

- [ ] Cortex enrichment coverage is above thresholds despite smaller row count
```sql
-- Coverage should remain ≥60% even with 10% sample
SELECT
    ROUND(SUM(CASE WHEN JOB_SAT_SENTIMENT_SCORE IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1) AS PCT_SENTIMENT
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES;
-- Expected: ≥60% (may be higher with sample — API failures are fewer on smaller batches)
```

- [ ] Cost breakdown reflects sampled enrichment
```
Expected cost range with 10% sampling:
  DEVPULSE_LOAD_WH (COPY INTO, 65K rows):       < $0.50
  DEVPULSE_TRANSFORM_WH (Dynamic Table refresh): < $0.50
  DEVPULSE_CORTEX_WH (manual operations):        < $0.50
  DEVPULSE_APP_WH (Streamlit sessions):          < $1.00
  ─────────────────────────────────────────────────────
  Subtotal (warehouse compute):                  ~$2–$3
  
  AI_SERVICES (Cortex LLM on 6.5K rows):        $7–$10
  Cortex Search indexing:                        < $1.00
  ─────────────────────────────────────────────────────
  Total estimated spend:                        $10–$15
```

**To verify actual billing:**
1. Snowsight → **Admin** → **Cost Management** → **Consumption**
2. Filter by your build date and the four `DEVPULSE_*` warehouses
3. Verify total is in the $10–$25 range
4. If total is ~$88, full-dataset enrichment was applied (missing `SAMPLE` clause in Step 5 Section 2)

---

### SC-07 · (Optional) Verify cost model documentation

- [ ] README.md includes a detailed Cost Retrospective explaining the $88 full-dataset cost

```bash
grep -A 20 "Cost Retrospective" README.md
```

This documents what went wrong in the original design and why sampling is the correct approach for portfolio projects.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `LIST @RAW_STAGE` returns 0 rows | File not uploaded yet | Upload CSV, then re-run |
| COPY INTO: `invalid identifier 'RESPONSEID'` | Table not found — wrong name or session context | `SHOW TABLES IN SCHEMA DEVPULSEINTEL.RAW` to confirm table exists |
| Dynamic Table has 0 rows after refresh | RAW table was empty at refresh time | Load RAW first, then re-run `ALTER DYNAMIC TABLE ... REFRESH` |
| Cortex Search returns empty results | Service still INITIALIZING, or SKILL_CLUSTER is all NULL | `SHOW CORTEX SEARCH SERVICES` → wait for ACTIVE; confirm SC-01 enrichment coverage |
| Streamlit app shows query error | Column name mismatch between app.py and actual table | `DESCRIBE TABLE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES` to verify column names |
| `unexpected '='` in CREATE TABLE | Inline `COMMENT =` on a column | Remove inline comments; use `COMMENT ON COLUMN` statements after table creation |
| `Bulk grant on PIPE is restricted` | Cannot use `ON ALL PIPES` in GRANT | Grant each pipe individually: `GRANT MONITOR, OPERATE ON PIPE ... TO ROLE ...` |
| Cortex enrichment cost was $70–$88 (much higher than expected) | Full-dataset enrichment applied — `SAMPLE (10 PERCENT)` was omitted in Step 5 Section 2 | This is not an error; it's the cost of running Cortex LLM on all 65K rows. For future projects, always apply `SAMPLE()` before enrichment. See README.md Cost Retrospective for details. |
