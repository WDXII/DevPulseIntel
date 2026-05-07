# DevPulseIntel — Dev Log

A running record of engineering decisions, challenges encountered, solutions applied, and lessons learned during the DevPulseIntel build.

> **Why this exists:** A portfolio project without a dev log shows only the finished result. A dev log shows how you think — how you diagnose problems, what you learned from them, and how your understanding evolved. That is what interviewers actually want to see.

---

## How to Read This Log

Each entry has:
- **What happened** — the problem or decision
- **Root cause** — why it happened (honest, no glossing over)
- **Solution** — what fixed it
- **Lesson** — the transferable principle

Entries are ordered chronologically (oldest → newest).

---

## Entries

---

### 01 · Column count mismatch on load
**Stage:** `01_staging.sql` / `02_raw_load.sql`
**Error:** `SQL compilation error: Insert value list does not match column list expecting 48 but got 49`

**What happened:**
The raw table DDL was written with 48 columns before the actual dataset was downloaded and inspected. The error surfaced at position 49 because that is where the first mismatch was detected — the actual dataset had 114 columns.

**Root cause:**
Schema was written before data was validated. The 48-column DDL was a fictional estimate, not derived from the actual file.

**Solution:**
Extracted the header row and regenerated the full DDL from the actual 114 column names:
```bash
head -1 survey_results_public.csv | tr ',' '\n' | wc -l
```

**Lesson:**
> **Schema first, code second.** For any bulk-load pipeline, the very first step is counting and inspecting the actual file headers. Never write a DDL before you have seen the data.

---

### 02 · "Invalid identifier" is a misleading error
**Stage:** `02_raw_load.sql`
**Error:** `SQL compilation error: invalid identifier 'RESPONSEID'`

**What happened:**
COPY INTO failed with "invalid identifier RESPONSEID" — which looked like a column name error. The actual cause was the table was referenced as `RAW.RAW_SURVEY_RESPONSES` in the COPY INTO but had been created as `RAW.SURVEY_RESPONSES` in the DDL. Snowflake cannot validate column names against a table it cannot find.

**Solution:**
Ran `SHOW TABLES IN SCHEMA DEVPULSEINTEL.RAW` to confirm what actually existed, then aligned all references to `RAW_SURVEY_RESPONSES`.

**Lesson:**
> **"Invalid identifier" on a column inside COPY INTO almost always means the table was not found, not a column name error.** Check object existence first with `SHOW TABLES`. Never debug column names before confirming the table exists.

---

### 03 · Stray `METADATA$FILENAME` in SELECT caused parse failure
**Stage:** `02_raw_load.sql`

**What happened:**
`METADATA$FILENAME` was left as a dangling line after `$114` in the FROM SELECT, leftover from an earlier draft. Snowflake treated it as a 116th expression with no matching column in the column list.

**Solution:**
Placed `METADATA$FILENAME` correctly inside the SELECT as the 115th expression, mapped explicitly to `_SOURCE_FILE_NAME` in the column list.

**Lesson:**
> **`METADATA$FILENAME` is a virtual column, not a CSV field.** It must appear in the FROM SELECT like any positional column and have a corresponding entry in the COPY INTO column list. Verify SELECT expression count equals column list count before running.

---

### 04 · `_LOAD_TIMESTAMP` must not appear in the COPY INTO column list
**Stage:** `01_staging.sql` / `02_raw_load.sql`

**What happened:**
An early version included `_LOAD_TIMESTAMP` in the COPY INTO column list. This is redundant — the column already has `DEFAULT CURRENT_TIMESTAMP()` on the table definition.

**Solution:**
Removed `_LOAD_TIMESTAMP` from the COPY INTO column list. The DEFAULT fires automatically when the column is absent from the load statement.

**Lesson:**
> **Exclude DEFAULT columns from COPY INTO column lists.** Including them overrides the default with whatever value you supply. Let the table definition be the source of truth.

---

### 05 · Two phantom columns (`COMP_FREQ`, `BRANCH_SAT`) in scripts 03–06
**Stage:** `03_dynamic_tables.sql` through `app.py`

**What happened:**
`COMP_FREQ` and `BRANCH_SAT` appeared throughout the pipeline but neither exists in the actual 2024 Stack Overflow survey. They were carry-overs from the original fictional 48-column schema.

**Solution:**
Cross-referenced the full 114-column list from the actual dataset against every column reference in the codebase and removed both phantom columns.

**Lesson:**
> **A phantom column is worse than a missing column.** A missing column errors immediately. A phantom column silently returns NULL everywhere, making quality problems invisible until someone asks why a chart is empty. Validate every downstream reference against the source schema before writing transformation logic.

---

### 06 · All column references in 03–06 were broken — wrong naming convention
**Stage:** `03_dynamic_tables.sql` through `app.py`

**What happened:**
The downstream pipeline referenced RAW columns using snake_case names (`RESPONSE_ID`, `YEARS_CODE_PRO`) from the fictional draft. The actual RAW table uses CSV-derived concatenated names (`RESPONSEID`, `YEARSCODEPRO`). Every RAW column reference in `DT_CLEAN_RESPONSES` would have failed at runtime.

**Solution:**
`DT_CLEAN_RESPONSES` now selects from RAW using actual column names and aliases them to clean snake_case. Scripts 04–06 and app.py use the aliased names and never touch raw column names.

**Lesson:**
> **The CLEAN layer's job is to bridge source fidelity and downstream usability.** RAW column names match the source file. CLEAN establishes canonical names and types. Nothing below CLEAN should ever reference a raw column name.

---

### 07 · Reserved word `CHECK` in column names
**Stage:** `01_staging.sql`

**What happened:**
Column 6 in the CSV is named `Check` — a SQL reserved word. Uppercased to `CHECK` by the column generation script, it caused a parse error.

**Solution:**
Renamed to `CHECK_COL` in the RAW DDL with a comment documenting the source name.

**Lesson:**
> **Scan generated column names for reserved words before executing DDL.** Common offenders: `CHECK`, `DATE`, `VALUE`, `NAME`, `RANK`, `TYPE`, `KEY`. Rename at the RAW layer and document the original name in a comment.

---

### 08 · `LIST @stage` returning no results is not an error
**Stage:** Deployment

**What happened:**
`LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE` returned zero rows after stage creation, initially interpreted as a failure.

**Solution:**
No fix needed. `LIST` returns zero rows when a stage exists but contains no files. Uploaded the CSV and the command returned one row.

**Lesson:**
> **In Snowflake, empty result ≠ missing object.** Object non-existence always throws an error. `LIST`, `SHOW`, and query functions return zero rows for objects that exist but are empty.

---

### 09 · Cortex ML FORECAST applied creatively to non-time-series data
**Stage:** `05_cortex_ml.sql`
*(Design decision — not an error)*

**What happened:**
`SNOWFLAKE.ML.FORECAST` requires a TIMESTAMP column. Salary data has no natural time dimension — the goal was prediction by years of experience.

**Solution:**
Used `YEARS_CODE_PRO_INT` as a pseudo-time axis by converting it to a date offset from a fixed epoch:
```sql
DATEADD('day', YEARS_CODE_PRO_INT, '2000-01-01'::DATE)::TIMESTAMP_NTZ
```

**Lesson:**
> **Snowflake ML FORECAST does not require a real time-series.** Any monotonically increasing continuous dimension can stand in for a timestamp. This lets you demonstrate ML FORECAST on cross-sectional survey data.

---

### 10 · Documentation must be coupled to success criteria, not just object existence
**Stage:** `setup.md` / `BRD.md`

**What happened:**
The original verification checklist verified that objects existed. It did not verify that objects worked — empty Cortex outputs or a search service still indexing would silently pass.

**Solution:**
Rewrote the checklist with six sections (SC-1 through SC-6), each with executable SQL and explicit expected results tied directly to BRD success criteria.

**Lesson:**
> **"Object exists" and "object works" are different verifications.** Every verification step needs an expected result — not just "this query runs" but "this query returns a value ≥ X."

---

### 11 · Inline `COMMENT =` on columns is not supported in Snowflake DDL
**Stage:** `01_staging.sql`, `04_cortex_enrich.sql`
**Error:** `SQL compilation error: syntax error line N at position 14 unexpected '='`

**What happened:**
Column-level comments were written inline inside `CREATE TABLE`:
```sql
-- WRONG
_SOURCE_FILE_NAME  VARCHAR
  COMMENT = 'Populated from METADATA$FILENAME at load time',
```
Snowflake rejects this syntax. The `unexpected '='` error appears on every column that has an inline comment.

**Root cause:**
`COMMENT =` works at the object level in `CREATE TABLE ... COMMENT = '...'` and looks like it should work inline on columns too — but it does not. This is a Snowflake-specific limitation.

**Solution:**
Removed all inline column comments from the DDL. Added them separately using `COMMENT ON COLUMN`:
```sql
COMMENT ON COLUMN DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES._SOURCE_FILE_NAME
  IS 'Populated from METADATA$FILENAME at load time';
```

**Lesson:**
> **`COMMENT =` works on objects (table, view, dynamic table) but NOT on individual columns inside a CREATE statement.** Column comments always require a separate `COMMENT ON COLUMN ... IS '...'` statement after creation — one statement per column. Object-level inline ✅, column-level inline ❌.

---

### 12 · `INFORMATION_SCHEMA.COPY_HISTORY` column names differ from expectation
**Stage:** `02_raw_load.sql`
**Error:** `SQL compilation error: invalid identifier 'ROWS_LOADED'`

**What happened:**
The post-load verification query used column names that do not exist:
```sql
-- WRONG
ROWS_LOADED, ROWS_PARSED, ERRORS_SEEN, FIRST_ERROR, FIRST_ERROR_LINE
```

**Solution:**
Correct column names for `INFORMATION_SCHEMA.COPY_HISTORY`:
```sql
-- CORRECT
ROW_COUNT, ROW_PARSED, ERROR_COUNT,
FIRST_ERROR_MESSAGE, FIRST_ERROR_LINE_NUMBER,
FIRST_ERROR_CHARACTER_POS, FIRST_ERROR_COLUMN_NAME
```
For most purposes, `SELECT COUNT(*) FROM target_table` is faster confirmation than parsing COPY_HISTORY. For full load history, use `SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY` (up to 2 hours latency).

**Lesson:**
> **Never write INFORMATION_SCHEMA queries from memory.** Run `SELECT * FROM TABLE(INFORMATION_SCHEMA.FUNCTION_NAME(...)) LIMIT 1` first to see real column names. INFORMATION_SCHEMA function signatures vary significantly.

---

### 13 · `INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICE_USAGE_HISTORY` does not exist
**Stage:** `06_cortex_search.sql`
**Error:** `SQL compilation error: Unknown table function INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICE_USAGE_HISTORY`

**What happened:**
The script polled Cortex Search service status using a table function that does not exist in Snowflake:
```sql
-- WRONG — this function does not exist
SELECT SERVICE_STATUS
FROM TABLE(
    INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICE_USAGE_HISTORY(
        SERVICE_NAME => 'DEVPULSE_SEARCH'
    )
)
```

**Root cause:**
Hallucinated function name — written by assumption rather than verified against Snowflake documentation. Cortex Search is a newer feature whose management commands are `SHOW`-based, not INFORMATION_SCHEMA table functions.

**Solution:**
```sql
-- CORRECT — only reliable status check for Cortex Search
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Check: STATUS column = ACTIVE

-- Functional validation once ACTIVE
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query": "Python developer with data engineering experience",
        "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER"],
        "limit": 3
    }'
) AS RESULTS;
```

**Lesson:**
> **For Snowflake-native AI features (Cortex Search, Cortex ML), management is done via `SHOW` commands, not INFORMATION_SCHEMA.** INFORMATION_SCHEMA covers standard SQL objects. Newer Snowflake-native objects use `SHOW CORTEX SEARCH SERVICES`, `SHOW SNOWFLAKE.ML.FORECAST`, `SHOW DYNAMIC TABLES`. When in doubt, check the docs — do not assume a function exists.

---

### 14 · `epoch_day` is not a valid `DATE_PART` value
**Stage:** `05_cortex_ml.sql`, `V_SALARY_ACTUAL_VS_FORECAST`
**Error:** `SQL compilation error: invalid value [epoch_day] for parameter 'DATE_PART date/time part'`

**What happened:**
The view used `DATE_PART('epoch_day', ...)` to reverse the pseudo-date encoding. This date part does not exist in Snowflake.

**Solution:**
```sql
-- WRONG
DATE_PART('epoch_day', EXPERIENCE_DATE::DATE)

-- CORRECT
DATEDIFF('day', '2000-01-01'::DATE, EXPERIENCE_DATE::DATE)
```

**Lesson:**
> **Use `DATEDIFF` for interval calculations between two dates, not `DATE_PART` arithmetic.** Valid Snowflake epoch parts are `epoch_second` and `epoch_millisecond` only — `epoch_day` does not exist. `DATEDIFF` is explicit, readable, and correct.

---

### 15 · `ROWS` is a reserved word — cannot be used as a column alias
**Stage:** Verification queries
**Error:** SQL parse error on `COUNT(*) AS ROWS`

**What happened:**
`ROWS` was used as a column alias. Snowflake treats it as reserved (used in window function syntax: `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`).

**Solution:**
```sql
-- WRONG
SELECT COUNT(*) AS ROWS

-- CORRECT
SELECT COUNT(*) AS ROW_COUNT
```

**Lesson:**
> **Snowflake reserves words that SQL Server allows as identifiers.** Default habit: suffix count aliases with `_COUNT` or `_TOTAL`. Other common reserved words that cause this: `VALUE`, `DATE`, `NAME`, `RANK`, `TYPE`, `KEY`. If you must use a reserved word as an alias, double-quote it — but avoiding them is cleaner.

---

### 16 · Bulk `GRANT ON ALL PIPES` is restricted in Snowflake
**Stage:** Access control setup
**Error:** `SQL compilation error: Bulk grant on objects of type PIPE to ROLE is restricted`

**What happened:**
```sql
-- WRONG — not allowed
GRANT ALL PRIVILEGES ON ALL PIPES IN DATABASE DEVPULSEINTEL TO ROLE ACCOUNTADMIN;
```

**Solution:**
Grant pipe privileges individually:
```sql
GRANT MONITOR, OPERATE ON PIPE DEVPULSEINTEL.INGESTION.SURVEY_PIPE TO ROLE ACCOUNTADMIN;
```
`MONITOR` — inspect pipe status. `OPERATE` — pause/resume. `ALL PRIVILEGES` on a pipe is not meaningful since pipes do not support DML.

**Lesson:**
> **Pipes, streams, and tasks have restricted bulk grant support in Snowflake.** Grant these individually with only the privileges meaningful for the object type. This is also a security principle: bulk `ALL PRIVILEGES` grants are a red flag in any environment.

---

### 17 · `CREATE OR REPLACE TABLE` is session-context dependent
**Stage:** `01_staging.sql`

**What happened:**
Running `CREATE OR REPLACE TABLE RAW_SURVEY_RESPONSES` without an active `USE SCHEMA DEVPULSEINTEL.RAW` created a new table in the session default schema. The original 48-column table in `DEVPULSEINTEL.RAW` was left untouched.

**Solution:**
Always use fully qualified three-part names:
```sql
-- WRONG (context-dependent)
CREATE OR REPLACE TABLE RAW_SURVEY_RESPONSES ( ... );

-- CORRECT (always hits the right object)
CREATE OR REPLACE TABLE DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES ( ... );
```

**Lesson:**
> **Always use fully qualified three-part names (`database.schema.table`) in all DDL statements.** This is immune to session context. In a multi-schema project, relying on `USE SCHEMA` is a silent failure waiting to happen — especially when running script sections out of order or in a fresh Snowsight tab.

---

## Quick Reference — Errors Encountered

| Error | Likely Cause | First Check |
|---|---|---|
| `Insert value list does not match column list expecting N but got M` | Column count mismatch | `DESCRIBE TABLE` vs actual file header count |
| `Invalid identifier 'COLUMN_NAME'` inside COPY INTO | Table not found (wrong name or wrong session context) | `SHOW TABLES IN SCHEMA` |
| `Invalid identifier` on reserved word alias | Column alias is a SQL keyword (ROWS, DATE, NAME…) | Rename alias with `_COUNT` or `_TOTAL` suffix |
| `unexpected '='` in CREATE TABLE | Inline `COMMENT =` on a column | Remove inline; use `COMMENT ON COLUMN` after creation |
| `Bulk grant on objects of type PIPE is restricted` | Cannot use `ON ALL PIPES` in GRANT | Grant pipe privileges individually |
| `Unknown table function INFORMATION_SCHEMA.X` | Function does not exist — verify against docs | Use `SHOW` commands for Cortex objects |
| `invalid value [epoch_day] for parameter DATE_PART` | `epoch_day` does not exist | Use `DATEDIFF('day', start, end)` |
| `LIST @stage` returns 0 rows | Stage exists but no file uploaded | Upload the file, then re-run LIST |
| Cortex Search returns empty results | Service still indexing, or no enriched rows in index | `SHOW CORTEX SEARCH SERVICES` → STATUS = ACTIVE |
| Dynamic Table shows 0 rows after refresh | Source table was empty at refresh time | Check RAW row count before refreshing |
| `CREATE OR REPLACE` hit wrong schema | Session context wrong | Use fully qualified three-part names always |

---

## Design Decisions Worth Remembering

| Decision | Rationale |
|---|---|
| RAW column names match CSV headers exactly | Source fidelity — raw layer independently reproducible without referencing any other script |
| CLEAN layer aliases RAW names to snake_case | Single point where naming is standardized; nothing downstream touches raw names |
| `TARGET_LAG = '9999 days'` on Dynamic Tables | Eliminates auto-refresh credit burn on static data |
| Cortex outputs materialized, never live | LLM functions bill per call; materializing once makes cost fixed and performance predictable |
| `_LOAD_TIMESTAMP` uses DEFAULT, not COPY INTO | Table DDL owns default values; load statements should not generate timestamps |
| `METADATA$FILENAME` → `_SOURCE_FILE_NAME` | Every row traceable to its source file — standard data engineering practice |
| `ON_ERROR = CONTINUE` in COPY INTO | Survey free-text fields can contain embedded newlines; minor row loss at RAW is acceptable |
| Fully qualified three-part object names everywhere | Immune to session context; eliminates silent schema mismatch bugs |
| `SHOW` commands for Cortex object status | INFORMATION_SCHEMA covers standard SQL objects; Cortex features use `SHOW` |
