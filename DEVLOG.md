# DEVLOG: DevPulseIntel

Errors, fixes, and lessons from the build, newest first. I came from SQL Server / T-SQL, so many entries are Snowflake behaviors that differ from what I expected.

---

## 2026-09-25: Post-build review

I reviewed the docs against the code before using the project in job applications.

**Found**
- **Docs contradicted code.** README/BRD had `CLASSIFY_TEXT` and `COMPLETE` swapped, the wrong stage name (`SURVEY_STAGE`), wrong warehouse names, and "Snowpipe auto-ingest" for a pipe that never ran.
- **JobSat is numeric** (0–10 integer; 36,311 of 65,437 null, confirmed with pandas). `SENTIMENT()` scored numbers, so sentiment output is meaningless and the text-matching `JOB_SAT_SCORE` is NULL.
- **Second cost root cause.** `04_cortex_enrich.sql` calls `SENTIMENT` 3× and `CLASSIFY_TEXT` / `COMPLETE` 2× per row. Missing sampling wasn't the only reason for ~$88.
- **Cost criterion mis-marked.** v1.1 said met; sampling was never executed. Corrected to "not met."
- **Row counts.** ANALYTICS holds ~51.5K rows (51,525). The "~23K" I'd carried was the salaried count (23,094) shown by the app's KPI card, which filters `ANNUAL_COMP_USD IS NOT NULL`. The CSV is clean (114 fields per record), so no rows were likely dropped.
- **Filter too broad.** ~6,150 ANALYTICS rows aren't professional developers; all were enriched and billed.
- **Code defects.** "Where Do I Stand?" labels don't match benchmark keys; the developer filter is too broad; the app builds SQL with f-strings.

**Constraint:** trial expired, nothing can be re-run. `sql/` and `app.py` stay as executed; corrections are documented and labeled "not executed."

**Learned**
- Profile inputs before paying for them. A free `SELECT DISTINCT` would have prevented the costliest mistake.
- Set thresholds from data. The 60% sentiment target ignored that only ~44% of respondents answered JobSat.
- Status marks decay. Re-check every ✅ against evidence before showing the project.
- Know what a number counts. A KPI card is a filtered metric; take row counts from `COUNT(*)` and save the query beside the number.

---

## May 2026: Build

### Cost overrun (Cortex LLM)
Enrichment ran on the full table with no sampling or pilot: ~$88 of trial credits (~$70 AI_SERVICES) vs a $5 target. Cost = rows × calls per row × tokens per call; warehouse size doesn't matter. AI credits are consumed only by Cortex LLM/ML SQL, Dynamic Table refreshes containing Cortex functions, FORECAST training, and Cortex Search indexing. Display-only app changes are free. (Status corrected in the 2026-09-25 review.)

### Streamlit: NaN passes a truthiness check
- **Symptom:** a KPI card errored for some filter combinations.
- **Cause:** `MEDIAN()` / `AVG()` over no rows reach pandas as `NaN`, which is **truthy**, so `if k["MEDIAN_SALARY"]:` passed and `int(nan)` raised.
- **Fix:** `pd.notna(k["MEDIAN_SALARY"])`. Made in the deployed app only; `app.py` here predates it, and the deployed copy was lost when the trial expired.

### Snowflake gotchas (from SQL Server)

| Gotcha | Instead |
|---|---|
| Inline column `COMMENT = '...'` in `CREATE TABLE` fails (`unexpected '='`) | `COMMENT ON COLUMN ... IS '...'` after the DDL |
| `GRANT ... ON ALL PIPES` fails (`Bulk grant on PIPE is restricted`) | Grant per pipe |
| Cortex Search services missing from `INFORMATION_SCHEMA` | `SHOW CORTEX SEARCH SERVICES IN SCHEMA ...` |
| `ROWS` is reserved, can't be an alias | `ROW_COUNT` |
| Epoch-day date math was awkward | `DATEADD` / `DATEDIFF` |
| `ACCOUNT_USAGE.COPY_HISTORY` lags up to 2 hours | Use `COUNT(*)` for instant checks; history columns: `LAST_LOAD_TIME`, `ROW_COUNT`, `ERROR_COUNT`, `FIRST_ERROR_MESSAGE` |
| `CREATE OR REPLACE TABLE` in the wrong session context lands in the wrong schema | Use three-part names |
| Column `Check` is reserved | Renamed `CHECK_COL` |

### Documentation rule
`sql/` is the source of truth for code. `setup.md` changes only when instructions change, not when code changes.
