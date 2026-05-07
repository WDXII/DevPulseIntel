-- =============================================================================
-- DevPulseIntel | 06_cortex_search.sql
-- Purpose : Create Cortex Search service over ENRICHED_RESPONSES
-- Run as  : ACCOUNTADMIN
-- Prereq  : 04_cortex_enrich.sql must be complete (ENRICHED_RESPONSES populated)
-- Note    : Service takes 2–5 minutes to reach ACTIVE status after creation.
--           Do not run test queries in Section 4 until ACTIVE.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DEVPULSE_CORTEX_WH;
USE DATABASE DEVPULSEINTEL;
USE SCHEMA ENRICHED;

-- ---------------------------------------------------------------------------
-- SECTION 1: Profile text view for indexing
-- Concatenates key fields into a single searchable text column.
-- The Cortex Search service indexes this text for semantic similarity.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW DEVPULSEINTEL.ENRICHED.V_SEARCH_PROFILES
  COMMENT = 'Composite profile text for Cortex Search indexing. One row per respondent.'
AS
SELECT
    RESPONSE_ID,
    COUNTRY,
    PRIMARY_DEV_ROLE,
    STANDARDIZED_ROLE,
    SKILL_CLUSTER,
    EXPERIENCE_BUCKET,
    EXPERIENCE_BUCKET_SORT,
    SALARY_BAND,
    SALARY_BAND_SORT,
    ANNUAL_COMP_USD,
    LANGUAGE_HAVE_WORKED_WITH,
    DATABASE_HAVE_WORKED_WITH,
    PLATFORM_HAVE_WORKED_WITH,
    JOB_SAT,
    JOB_SAT_SENTIMENT_LABEL,
    AI_ATTITUDE_CATEGORY,
    AI_THREAT_JOB,
    USES_AI_TOOLS,

    -- Composite text column: the field Cortex Search will index semantically
    TRIM(CONCAT_WS(' | ',
        COALESCE('Role: '     || STANDARDIZED_ROLE,        ''),
        COALESCE('Cluster: '  || SKILL_CLUSTER,            ''),
        COALESCE('Languages: '|| LANGUAGE_HAVE_WORKED_WITH,''),
        COALESCE('Databases: '|| DATABASE_HAVE_WORKED_WITH,''),
        COALESCE('Platforms: '|| PLATFORM_HAVE_WORKED_WITH,''),
        COALESCE('Country: '  || COUNTRY,                  ''),
        COALESCE('Experience: '|| EXPERIENCE_BUCKET,       ''),
        COALESCE('Salary: '   || SALARY_BAND,              ''),
        COALESCE('JobSat: '   || JOB_SAT,                  ''),
        COALESCE('AI Attitude: '|| AI_ATTITUDE_CATEGORY,   '')
    ))                                                          AS PROFILE_TEXT

FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE RESPONSE_ID IS NOT NULL
  AND SKILL_CLUSTER IS NOT NULL;   -- Only index enriched rows


-- ---------------------------------------------------------------------------
-- SECTION 2: Create Cortex Search service
-- SEARCH ON: the composite PROFILE_TEXT column (semantic similarity index)
-- ATTRIBUTES: filterable columns available in Python filter expressions
-- ---------------------------------------------------------------------------

CREATE OR REPLACE CORTEX SEARCH SERVICE DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH
  ON PROFILE_TEXT
  ATTRIBUTES
    COUNTRY,
    PRIMARY_DEV_ROLE,
    STANDARDIZED_ROLE,
    SKILL_CLUSTER,
    EXPERIENCE_BUCKET,
    SALARY_BAND,
    JOB_SAT_SENTIMENT_LABEL,
    AI_ATTITUDE_CATEGORY,
    USES_AI_TOOLS
  WAREHOUSE = DEVPULSE_CORTEX_WH
  TARGET_LAG = '9999 days'
  COMMENT   = 'Semantic search over DevPulseIntel developer profiles. Index built from V_SEARCH_PROFILES.'
AS
  SELECT * FROM DEVPULSEINTEL.ENRICHED.V_SEARCH_PROFILES;

-- ---------------------------------------------------------------------------
-- SECTION 3: Check service status
-- Wait until STATUS = ACTIVE (typically 2–5 minutes) before running Section 4.
-- ---------------------------------------------------------------------------

SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;
-- Expected: NAME = DEVPULSE_SEARCH, STATUS = ACTIVE



-- ---------------------------------------------------------------------------
-- SECTION 4: Functional test queries (run only after STATUS = ACTIVE)
-- ---------------------------------------------------------------------------

-- Test 1: General semantic query — no filters
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query":   "Python developer with data engineering experience",
        "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER", "COUNTRY"],
        "limit":   3
    }'
) AS RESULTS;

-- Test 2: With country filter
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query":   "cloud infrastructure and DevOps automation",
        "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER", "SALARY_BAND"],
        "filter":  {"@eq": {"COUNTRY": "United States of America"}},
        "limit":   5
    }'
) AS RESULTS;

-- Test 3: With AI adoption filter
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query":   "mobile developer iOS Android React Native",
        "columns": ["RESPONSE_ID", "SKILL_CLUSTER", "EXPERIENCE_BUCKET", "SALARY_BAND"],
        "filter":  {"@eq": {"USES_AI_TOOLS": true}},
        "limit":   5
    }'
) AS RESULTS;

-- Test 4: Full-stack multi-filter
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
    '{
        "query":   "experienced senior developer machine learning",
        "columns": ["RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER",
                    "EXPERIENCE_BUCKET", "COUNTRY", "SALARY_BAND",
                    "JOB_SAT_SENTIMENT_LABEL"],
        "filter":  {"@and": [
            {"@eq": {"SALARY_BAND": "Over $200K"}},
            {"@eq": {"JOB_SAT_SENTIMENT_LABEL": "Positive"}}
        ]},
        "limit":   5
    }'
) AS RESULTS;

-- =============================================================================
-- END 06_cortex_search.sql
-- Next: Deploy streamlit/app.py as Streamlit in Snowflake (see setup.md Step 9)
-- =============================================================================
