# DEVLOG: DevPulseIntel

A log of the errors, fixes, and lessons from building DevPulseIntel, newest first. I came to Snowflake from SQL Server / T-SQL, so many entries are Snowflake-specific behaviors that differ from what I expected.

---

## 2026-09-25: Post-build review

**Trigger:** I reviewed the documents against the code before using the project in job applications.

**Found:**
- **The docs contradicted the code.** The README and BRD had `CLASSIFY_TEXT` and `COMPLETE` swapped, used the wrong stage name (`SURVEY_STAGE` instead of `RAW_STAGE`), used the wrong warehouse names in setup, and described "Snowpipe auto-ingest" when the pipe was never triggered.
- **JobSat is numeric.** I profiled the source CSV with pandas: JobSat is a 0–10 integer (36,311 of 65,437 null). `SENTIMENT()` ran on numbers, so the sentiment feature is meaningless, and the text-matching `JOB_SAT_SCORE` CASE returns NULL.
- **Second cost root cause.** `04_cortex_enrich.sql` calls `SENTIMENT` three times per row and `CLASSIFY_TEXT` / `COMPLETE` twice per row. Missing sampling was not the only reason for the ~$88.
- **The v1.1 cost criterion was marked met, but sampling was never executed.** Corrected to "not met in executed build."
- **Row-count confusion, resolved.** I had recorded "~23K professional developers" through the layers. Profiling the CSV showed ANALYTICS holds ~51.5K rows; 23,094 is the count *with a valid salary*, which is what the app's "Developers" KPI card shows (its query filters `ANNUAL_COMP_USD IS NOT NULL`). The file itself is clean (114 fields in every record), so no rows were likely dropped at load.
- **Filter too broad.** ~6,150 of the 51.5K ANALYTICS rows are not professional developers ("not primarily a developer", "used to be a developer"). They were all enriched and billed.
- **Code review defects:** the "Where Do I Stand?" role labels don't match the benchmark keys; the "professional developer" filter also matches non-professionals; the app builds SQL with f-strings.

**Constraint:** The trial account has expired, so nothing can be re-run.

**Did:** Kept `sql/` and `app.py` exactly as executed. Aligned README, BRD (v1.2), setup, architecture, and decisions with the code. Every correction is documented and labeled "not executed."

**Learned:**
- **Profile inputs before paying for them.** A free `SELECT DISTINCT` would have prevented the most expensive mistake in the project.
- **Set thresholds from the data, not from intuition.** The 60% sentiment-coverage target was chosen without checking how many respondents answered JobSat (~44% overall in the source).
- **Status marks decay.** A ✅ written during the build needs re-checking against evidence before the project is shown to anyone.
- **Know what a number counts.** A KPI card is a filtered metric, not a row count. Record counts from `COUNT(*)` on the table, with the query saved next to the number.

---

## May 2026: Build

### Cost overrun (Cortex LLM)

- **What happened:** Enrichment ran on the full ANALYTICS table with no sampling or cost pilot. The total was ~$88 of trial credits, ~$70 of it AI_SERVICES, against a $5 target.
- **Learned:** LLM cost = rows × calls per row × tokens per call. Warehouse size doesn't affect it. Only a few things consume AI credits: SQL that invokes Cortex LLM/ML functions, Dynamic Table refreshes that contain Cortex functions, FORECAST training, and Cortex Search indexing. Display-only Python changes in the app cost nothing.
- **Did:** Revised the BRD to v1.1 and wrote the Cost Retrospective. (Corrected in the 2026-09-25 review; see above.)

### Streamlit: NaN passes a truthiness check

- **Symptom:** A KPI card errored for some filter combinations.
- **Cause:** `MEDIAN()` / `AVG()` over no rows come back to pandas as `NaN`, and `float('nan')` is **truthy** in Python. So `if k["MEDIAN_SALARY"]:` passed, and `int(nan)` raised an error.
- **Fix:** Guard with `pd.notna(k["MEDIAN_SALARY"])` instead of bare truthiness.
- **Note (Sept 2026):** The fix was made in the deployed app's Snowsight editor. The `app.py` in this repo is the last local copy and predates it; the deployed version was lost when the trial expired.

### Snowflake syntax gotchas (coming from SQL Server)

| Gotcha | What to do instead |
|---|---|
| Inline `COMMENT = '...'` on a column in `CREATE TABLE` fails with `unexpected '='` | Use separate `COMMENT ON COLUMN ... IS '...'` statements after the DDL |
| `GRANT ... ON ALL PIPES` fails with `Bulk grant on PIPE is restricted` | Grant on each pipe individually |
| Cortex Search services don't show up in `INFORMATION_SCHEMA` | Use `SHOW CORTEX SEARCH SERVICES IN SCHEMA ...` |
| `ROWS` is a reserved word and can't be a column alias | Use `ROW_COUNT` or similar |
| Date arithmetic with epoch-day tricks was awkward | Use `DATEADD` / `DATEDIFF` (the forecast axis relies on this) |
| `ACCOUNT_USAGE.COPY_HISTORY` columns aren't what you'd guess, and the view lags by up to 2 hours | Use `LAST_LOAD_TIME`, `ROW_COUNT`, `ERROR_COUNT`, `FIRST_ERROR_MESSAGE`; use `COUNT(*)` for immediate confirmation |
| `CREATE OR REPLACE TABLE` in the wrong session context lands in the wrong schema | Always use fully qualified three-part names |
| The survey column `Check` is a reserved word | Renamed to `CHECK_COL` in RAW |

### Documentation rule adopted

- `sql/` files are the source of truth for code. `setup.md` describes how to run them and changes only when instructions change, not when code changes.
