# Design Decisions: DevPulseIntel

Each entry gives the decision, why, and, where the post-build review changed my view, a **Hindsight** note. Hindsight notes were not re-run (trial expired).

| ID | Decision | Status |
|---|---|---|
| D-01 | Snowflake-native only | Kept |
| D-02 | Four-layer Medallion + separate INGESTION schema | Kept |
| D-03 | RAW stores everything as VARCHAR | Kept; hindsight |
| D-04 | Load via `COPY INTO`; pipe defined, not triggered | Kept; wording revised |
| D-05 | Dynamic Tables with `TARGET_LAG = '9999 days'` | Kept |
| D-06 | Four XS warehouses split by workload | Kept |
| D-07 | Materialize Cortex outputs in a table | Kept; hindsight |
| D-08 | CLASSIFY_TEXT for roles, COMPLETE for skill clusters | Kept; caveat |
| D-09 | Experience as pseudo-time axis for FORECAST | Kept as demo; reframed |
| D-10 | Pre-aggregated salary benchmarks | Kept; widget defect |
| D-11 | Cortex Search over a composite profile text | Kept |
| D-12 | Sampling Cortex enrichment | Revised twice |
| D-13 | Document post-build findings instead of patching | New (Sept 2026) |

---

**D-01: Snowflake-native only.** The goal is to show platform depth, so every step is a Snowflake object. Trade-off: no scheduling, tests, or CI (out of scope, BRD §4).

**D-02: Medallion + INGESTION schema.** RAW → CLEAN → ANALYTICS → ENRICHED, one schema each, plus `INGESTION` for stage, file format, and pipe. Each script maps to one layer.

**D-03: RAW as VARCHAR.** Survey CSVs mix numbers, free text, and sentinels ("Less than 1 year", "NA"). All 114 columns stay text in RAW and are cast in CLEAN with `TRY_CAST`; reserved word `Check` becomes `CHECK_COL`. Loads never fail on types.
*Hindsight:* all-text also hid that JobSat is numeric. A profiling step after load would have caught it (D-12).

**D-04: `COPY INTO`; pipe defined, not triggered.** The data is one static file, so event-driven ingestion adds nothing. `SURVEY_PIPE` (`AUTO_INGEST = FALSE`) shows the config; the load is a manual `COPY INTO` with `ON_ERROR = 'CONTINUE'`.
*Hindsight:* early docs said "Snowpipe auto-ingest," which overstated what ran. `ON_ERROR = 'CONTINUE'` needed a mandatory row-count check against 65,437. A later source-file check found no malformed records, but the build never proved it.

**D-05: Dynamic Tables, 9999-day lag.** Declarative pipeline, no refresh cost on a trial account; refreshed manually once. Trade-off: incremental refresh isn't demonstrated.

**D-06: Four XS warehouses.** LOAD, TRANSFORM, CORTEX, APP, all 60-second auto-suspend, so cost is attributable per stage. Cortex LLM cost bills separately as AI_SERVICES and ignores warehouse size.

**D-07: Materialize Cortex outputs.** LLM functions bill per call, so a view would re-bill on every app query. `ENRICHED_RESPONSES` is seeded by `INSERT`, then filled by one `UPDATE` per task. Re-running the script re-bills.
*Hindsight:* each `UPDATE` calls its function once per derived column, not once per row (SENTIMENT ×3; CLASSIFY_TEXT and COMPLETE ×2). Fix: store the raw result once and derive the rest from it.

**D-08: CLASSIFY_TEXT for roles, COMPLETE for clusters.** `CLASSIFY_TEXT` maps `DEV_TYPE` to 8 role labels; `COMPLETE` (`mistral-7b`, constrained prompt) maps languages to 8 clusters, with non-conforming answers set to `Other`. All three LLM functions are demonstrated.
*Hindsight:* role standardization could be a free mapping table. I chose the LLM to demonstrate the function, and I should say so when asked.

**D-09: Experience as pseudo-time for FORECAST.** `FORECAST` needs a timestamp and the data is one survey year, so years of experience become days from 2000-01-01, one series per country, 10 periods.
*Hindsight:* not a valid salary model. It extrapolates past the 51-year cap and assumes time-series structure that isn't there. Documented as a capability demo; regression is the right tool.

**D-10: Pre-aggregated benchmarks.** P25/median/avg/P75/P90 by country × experience bucket × role are precomputed into `SALARY_BENCHMARKS` for instant, free lookups.
*Hindsight (code review):* the table is keyed on `PRIMARY_DEV_ROLE` (raw labels) but the widget filters on `STANDARDIZED_ROLE`, so labels likely never match. Key on `STANDARDIZED_ROLE` and filter by experience bucket.

**D-11: Cortex Search over a composite text.** `PROFILE_TEXT` concatenates role, cluster, languages, databases, platforms, country, experience, salary band, JobSat, and AI attitude. Only enriched rows are indexed; categorical columns are filter attributes.

**D-12: Sampling Cortex enrichment.** v1.0 targeted under $5. Unsampled enrichment cost ~$88 of trial credits (~$70 AI_SERVICES).
- *v1.1 (May 2026):* recommended `SAMPLE (10 PERCENT)` on the seed `INSERT`. Documented, never executed.
- *v1.2 (Sept 2026):* sampling the seed also thins FORECAST and benchmark data, which need no LLM. Keep the seed unsampled and restrict only the Cortex `UPDATE`s to a sampled ID set (`setup.md` Step 6, Option B).

Two rules come before sampling: (1) profile every enrichment input (`SELECT DISTINCT ... LIMIT 20`) before any paid call; (2) pilot each Cortex step on ~100 rows and extrapolate cost. Sampling shrinks the cost of a mistake; profiling prevents it. Either rule would have caught JobSat and most of the overrun.

**D-13: Document findings, don't patch (Sept 2026).** The trial expired, so code can't be run. `sql/` and `app.py` stay exactly as executed; defects and fixes live in README Known Issues, BRD v1.2, and this file, each labeled "not executed." Code, results, and screenshots stay consistent.
