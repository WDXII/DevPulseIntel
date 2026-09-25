# Design Decisions: DevPulseIntel

Each entry records the context, the decision, its consequences, and (where the post-build review changed my view) a **Hindsight** note. Decisions reflect the build as executed; hindsight notes were not re-run.

| ID | Decision | Status |
|---|---|---|
| D-01 | Snowflake-native only | Kept |
| D-02 | Four-layer Medallion + separate INGESTION schema | Kept |
| D-03 | RAW layer stores everything as VARCHAR | Kept |
| D-04 | Load via `COPY INTO`; pipe defined but not triggered | Kept, with revised wording |
| D-05 | Dynamic Tables with `TARGET_LAG = '9999 days'` | Kept |
| D-06 | Four XS warehouses split by workload | Kept |
| D-07 | Materialize Cortex outputs in a table | Kept |
| D-08 | CLASSIFY_TEXT for roles, COMPLETE for skill clusters | Kept, with a caveat |
| D-09 | Experience as a pseudo-time axis for FORECAST | Kept as a demo; reframed |
| D-10 | Pre-aggregated salary benchmarks | Kept; widget has a defect |
| D-11 | Cortex Search over a composite profile text | Kept |
| D-12 | Sampling Cortex enrichment | Revised twice |
| D-13 | Document post-build findings instead of patching | New (Sept 2026) |

---

### D-01: Snowflake-native only

**Context:** The portfolio goal is to show Snowflake platform depth, specifically Cortex and the application layer.
**Decision:** No external orchestration, storage, or compute. Every step is a Snowflake object.
**Consequences:** Setup is simpler and reviewers see one platform used end to end. The trade-off is that there is no scheduling, testing framework, or CI; those are out of scope (BRD §4).

### D-02: Four-layer Medallion + separate INGESTION schema

**Context:** A clear layer boundary makes it obvious where each transformation lives.
**Decision:** RAW → CLEAN → ANALYTICS → ENRICHED, one schema each, plus `INGESTION` for the stage, file format, and pipe.
**Consequences:** Each script maps to one layer. Downstream scripts and the app only use CLEAN/ANALYTICS column names.

### D-03: RAW layer stores everything as VARCHAR

**Context:** Survey CSVs mix numbers, free text, and sentinel strings ("Less than 1 year", "NA").
**Decision:** Keep all 114 columns as VARCHAR in RAW and cast in CLEAN with `TRY_CAST`. Rename the reserved word `Check` to `CHECK_COL`.
**Consequences:** The load never fails on type errors, and typing logic lives in one place.
**Hindsight:** Keeping everything as text also hid the fact that JobSat is numeric. A typed schema, or a profiling step after load, would have exposed it before enrichment (see D-12).

### D-04: Load via `COPY INTO`; pipe defined but not triggered

**Context:** The dataset is a single static file, so event-driven ingestion adds nothing.
**Decision:** Define `SURVEY_PIPE` with `AUTO_INGEST = FALSE` to show the configuration, and run the actual load as a manual `COPY INTO` with `ON_ERROR = 'CONTINUE'`.
**Consequences:** The load is fast and repeatable (`FORCE = FALSE` skips files already loaded).
**Hindsight:** Earlier docs described this as "Snowpipe auto-ingest," which overstated what ran. They now say "pipe defined; load via COPY INTO." `ON_ERROR = 'CONTINUE'` should have been paired with a mandatory row-count check against the source (65,437). A post-build check of the file found no malformed records, so no rows were likely dropped, but the build never proved it.

### D-05: Dynamic Tables with `TARGET_LAG = '9999 days'`

**Context:** Dynamic Tables are declarative, but automatic refresh on a trial account wastes credits for a static dataset.
**Decision:** Use Dynamic Tables for CLEAN and ANALYTICS with an effectively infinite lag, and refresh manually once.
**Consequences:** You get the declarative pipeline with no ongoing cost. The trade-off is that incremental refresh behavior is not demonstrated.

### D-06: Four XS warehouses split by workload

**Context:** On a fixed trial budget, you need to see which step costs what.
**Decision:** Separate LOAD, TRANSFORM, CORTEX, and APP warehouses, all XS with 60-second auto-suspend.
**Consequences:** Warehouse cost is attributable per stage. Cortex LLM cost bills separately as AI_SERVICES and is not controlled by warehouse size (see D-12).

### D-07: Materialize Cortex outputs in a table

**Context:** LLM functions bill per call. Computing them in a view would re-bill every time the app ran a query.
**Decision:** Seed `ENRICHED_RESPONSES` from ANALYTICS with `INSERT`, then fill the Cortex columns with one `UPDATE` per task.
**Consequences:** The app reads stored results at no extra LLM cost. Any re-run of the script re-bills.
**Hindsight:** Each `UPDATE` calls its function once per derived column instead of once per row: SENTIMENT three times, and CLASSIFY_TEXT and COMPLETE twice each. The fix is to store the raw function result once and derive the other columns from it.

### D-08: CLASSIFY_TEXT for roles, COMPLETE for skill clusters

**Context:** DevType has 30+ raw values; language stacks are long semicolon lists.
**Decision:** Use `CLASSIFY_TEXT` with 8 fixed role labels (it returns a label plus a confidence score). Use `COMPLETE` with `mistral-7b` and a constrained prompt for 8 skill clusters, then map any non-conforming answer to `Other`.
**Consequences:** All three Cortex LLM functions are demonstrated, each on a task that suits it.
**Hindsight:** Role standardization could have been done with a deterministic mapping table for free; the LLM was chosen to demonstrate the function. That is fine for a demo, but I should say so when asked.

### D-09: Experience as a pseudo-time axis for FORECAST

**Context:** FORECAST requires a timestamp, and the dataset is a single survey year.
**Decision:** Encode years of professional experience as days from 2000-01-01, treat each country as a series, and forecast 10 periods.
**Consequences:** The FORECAST API, including series handling and prediction intervals, is demonstrated end to end.
**Hindsight:** This is not a valid salary model. It forecasts past the data's 51-year cap and assumes time-series structure where none exists. It is now documented explicitly as a capability demo. A regression model would be the right tool for salary versus experience.

### D-10: Pre-aggregated salary benchmarks

**Context:** "Where Do I Stand?" needs percentiles instantly and without cost.
**Decision:** Precompute P25/median/avg/P75/P90 by country × experience bucket × role into `SALARY_BENCHMARKS`.
**Consequences:** Lookups are cheap.
**Hindsight (code review):** The table is keyed on `PRIMARY_DEV_ROLE` (raw survey labels), but the widget filters with `STANDARDIZED_ROLE` values, so the labels likely never match. The benchmark should have been keyed on `STANDARDIZED_ROLE`, and the lookup should also filter by experience bucket.

### D-11: Cortex Search over a composite profile text

**Context:** Semantic search works best over a single descriptive text field.
**Decision:** Concatenate role, cluster, languages, databases, platforms, country, experience, salary band, JobSat, and AI attitude into `PROFILE_TEXT`. Index only enriched rows, and expose categorical columns as filter attributes.
**Consequences:** Natural-language queries plus structured filters work in one call.

### D-12: Sampling Cortex enrichment

**Context:** v1.0 of the BRD targeted total spend under $5. Enrichment ran unsampled on all ANALYTICS rows and consumed ~$88 of trial credits (~$70 AI_SERVICES).
**Decision (v1.1, May 2026):** Recommend `SAMPLE (10 PERCENT)` on the seed `INSERT`. This was documented but never executed.
**Revision (v1.2, September 2026):** Sampling the seed also thins the data used by FORECAST and the benchmarks, which don't need an LLM at all. The better design is to keep the seed unsampled and restrict only the Cortex `UPDATE`s to a sampled ID set (`setup.md` Step 6, Option B). The review also added two rules that come before sampling:
1. Profile every enrichment input (`SELECT DISTINCT ... LIMIT 20`) before any paid call.
2. Pilot each Cortex step on about 100 rows and extrapolate cost before scaling.

**Why this matters:** Sampling reduces the cost of a mistake; profiling prevents it. Either rule would have caught the JobSat problem and most of the overrun.

### D-13: Document post-build findings instead of patching (September 2026)

**Context:** The trial account expired after the build, so code can no longer be executed.
**Decision:** Keep `sql/` and `app.py` exactly as executed. Record defects and corrected patterns in the README Known Issues, BRD v1.2, and this file, with every correction labeled "not executed."
**Consequences:** The code, results, and screenshots stay consistent with each other, and reviewers can see both what ran and what should change.
