-- =============================================================================
-- DevPulseIntel | 04_cortex_enrich.sql
-- Purpose : Populate ENRICHED.ENRICHED_RESPONSES with Cortex LLM outputs
--           (SENTIMENT, CLASSIFY_TEXT, COMPLETE)
-- Run as  : ACCOUNTADMIN
-- Run ONCE: Cortex functions bill per call. Do not re-run on existing rows.
-- Prereq  : 03_dynamic_tables.sql must be run and both Dynamic Tables refreshed.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DEVPULSE_CORTEX_WH;
USE DATABASE DEVPULSEINTEL;
USE SCHEMA ENRICHED;

-- ---------------------------------------------------------------------------
-- SECTION 1: Create ENRICHED_RESPONSES table
-- All Cortex outputs are materialized here. The Streamlit app reads this table.
-- Columns are populated by INSERT + UPDATE pattern in sections 2–5.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES (

    -- Join key
    RESPONSE_ID                     VARCHAR     NOT NULL,

    -- Core analytics passthrough (avoids joins in Streamlit app)
    COUNTRY                         VARCHAR,
    PRIMARY_DEV_ROLE                VARCHAR,
    EXPERIENCE_BUCKET               VARCHAR,
    EXPERIENCE_BUCKET_SORT          INTEGER,
    ANNUAL_COMP_USD                 FLOAT,
    SALARY_BAND                     VARCHAR,
    SALARY_BAND_SORT                INTEGER,
    YEARS_CODE_PRO_INT              INTEGER,
    USES_AI_TOOLS                   BOOLEAN,
    AI_TOOL_CURRENTLY_USING         VARCHAR,
    JOB_SAT                         VARCHAR,
    JOB_SAT_SCORE                   INTEGER,
    LANGUAGE_HAVE_WORKED_WITH       VARCHAR,
    PRIMARY_LANGUAGE                VARCHAR,
    DATABASE_HAVE_WORKED_WITH       VARCHAR,
    PLATFORM_HAVE_WORKED_WITH       VARCHAR,
    EMPLOYMENT                      VARCHAR,
    REMOTE_WORK                     VARCHAR,
    ORG_SIZE                        VARCHAR,
    ED_LEVEL                        VARCHAR,
    INDUSTRY                        VARCHAR,
    AI_THREAT_JOB                   VARCHAR,

    -- ── Cortex SENTIMENT ──────────────────────────────────────────────────
    JOB_SAT_SENTIMENT_SCORE         FLOAT,
    JOB_SAT_SENTIMENT_LABEL         VARCHAR,
    

    -- ── Cortex CLASSIFY_TEXT ──────────────────────────────────────────────
    STANDARDIZED_ROLE               VARCHAR,    
    STANDARDIZED_ROLE_SCORE         FLOAT,
    
    -- ── Cortex COMPLETE ───────────────────────────────────────────────────
    SKILL_CLUSTER                   VARCHAR,    
    SKILL_CLUSTER_RAW               VARCHAR,
     
    -- ── AI attitude (CLASSIFY_TEXT on AI sentiment) ───────────────────────
    AI_ATTITUDE_CATEGORY            VARCHAR,
     
    -- Enrichment metadata
    ENRICHED_AT                     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
     
)
COMMENT = 'Enriched developer profiles. All Cortex LLM outputs materialized. Never recomputed at query time.';
COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.JOB_SAT_SENTIMENT_SCORE
  IS 'CORTEX.SENTIMENT() on JOB_SAT text. Range: -1 (negative) to 1 (positive).';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.JOB_SAT_SENTIMENT_LABEL
  IS 'Derived: Positive (>0.2), Neutral (-0.2 to 0.2), Negative (<-0.2)';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.STANDARDIZED_ROLE
  IS 'CORTEX.CLASSIFY_TEXT() output: standardized role category from DEV_TYPE.';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.STANDARDIZED_ROLE_SCORE
  IS 'Confidence score for role classification (0-1).';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.SKILL_CLUSTER
  IS 'CORTEX.COMPLETE() output: LLM-assigned skill cluster for respondent tech stack.';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.SKILL_CLUSTER_RAW
  IS 'Raw LLM response before parsing. Kept for debugging.';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.AI_ATTITUDE_CATEGORY
  IS 'CORTEX.CLASSIFY_TEXT() on AI_SENTIMENT_RAW: Enthusiast / Cautious / Skeptic / Neutral';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES.ENRICHED_AT
  IS 'Timestamp when Cortex enrichment was applied to this row.';

-- ---------------------------------------------------------------------------
-- SECTION 2: Seed table from ANALYTICS layer
-- Populates all passthrough columns. Cortex columns remain NULL until
-- sections 3-5 run.
-- ---------------------------------------------------------------------------

INSERT INTO DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES (
    RESPONSE_ID, COUNTRY, PRIMARY_DEV_ROLE, EXPERIENCE_BUCKET, EXPERIENCE_BUCKET_SORT,
    ANNUAL_COMP_USD, SALARY_BAND, SALARY_BAND_SORT, YEARS_CODE_PRO_INT,
    USES_AI_TOOLS, AI_TOOL_CURRENTLY_USING, JOB_SAT, JOB_SAT_SCORE,
    LANGUAGE_HAVE_WORKED_WITH, PRIMARY_LANGUAGE, DATABASE_HAVE_WORKED_WITH,
    PLATFORM_HAVE_WORKED_WITH, EMPLOYMENT, REMOTE_WORK, ORG_SIZE,
    ED_LEVEL, INDUSTRY, AI_THREAT_JOB
)
SELECT
    RESPONSE_ID, COUNTRY, PRIMARY_DEV_ROLE, EXPERIENCE_BUCKET, EXPERIENCE_BUCKET_SORT,
    ANNUAL_COMP_USD, SALARY_BAND, SALARY_BAND_SORT, YEARS_CODE_PRO_INT,
    USES_AI_TOOLS, AI_TOOL_CURRENTLY_USING, JOB_SAT, JOB_SAT_SCORE,
    LANGUAGE_HAVE_WORKED_WITH, PRIMARY_LANGUAGE, DATABASE_HAVE_WORKED_WITH,
    PLATFORM_HAVE_WORKED_WITH, EMPLOYMENT, REMOTE_WORK, ORG_SIZE,
    ED_LEVEL, INDUSTRY, AI_THREAT_JOB
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;

-- Confirm seed row count matches ANALYTICS
SELECT COUNT(*) AS SEEDED_ROWS FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES;


-- ---------------------------------------------------------------------------
-- SECTION 3: Cortex SENTIMENT — job satisfaction sentiment score
-- Applied to JOB_SAT text. Skips NULLs.
-- Cost: ~0.0002 credits per row. Expect ~$0.10 total on 65K rows.
-- ---------------------------------------------------------------------------

UPDATE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES e
SET
    JOB_SAT_SENTIMENT_SCORE = SNOWFLAKE.CORTEX.SENTIMENT(a.JOB_SAT),
    JOB_SAT_SENTIMENT_LABEL = CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(a.JOB_SAT) >  0.2 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(a.JOB_SAT) < -0.2 THEN 'Negative'
        ELSE 'Neutral'
    END
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS a
WHERE e.RESPONSE_ID = a.RESPONSE_ID
  AND a.JOB_SAT IS NOT NULL;

-- Verify
SELECT
    JOB_SAT_SENTIMENT_LABEL,
    COUNT(*)                                            AS COUNT,
    ROUND(AVG(JOB_SAT_SENTIMENT_SCORE), 3)             AS AVG_SCORE
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE JOB_SAT_SENTIMENT_LABEL IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;


-- ---------------------------------------------------------------------------
-- SECTION 4: Cortex CLASSIFY_TEXT — standardize developer roles
-- Collapses the 30+ free-text DevType values into 8 canonical categories.
-- ---------------------------------------------------------------------------

UPDATE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES e
SET
    STANDARDIZED_ROLE       = r.LABEL,
    STANDARDIZED_ROLE_SCORE = r.SCORE
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS a,
LATERAL (
    SELECT
        PARSE_JSON(
            SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
                a.DEV_TYPE,
                ARRAY_CONSTRUCT(
                    'Backend Developer',
                    'Frontend Developer',
                    'Full-Stack Developer',
                    'Data Engineer / Analyst',
                    'DevOps / Platform Engineer',
                    'Mobile Developer',
                    'Engineering Manager / Lead',
                    'Other Technical'
                )
            )
        )['label']::VARCHAR   AS LABEL,
        PARSE_JSON(
            SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
                a.DEV_TYPE,
                ARRAY_CONSTRUCT(
                    'Backend Developer',
                    'Frontend Developer',
                    'Full-Stack Developer',
                    'Data Engineer / Analyst',
                    'DevOps / Platform Engineer',
                    'Mobile Developer',
                    'Engineering Manager / Lead',
                    'Other Technical'
                )
            )
        )['score']::FLOAT     AS SCORE
) r
WHERE e.RESPONSE_ID = a.RESPONSE_ID
  AND a.DEV_TYPE IS NOT NULL;

-- Verify distribution
SELECT STANDARDIZED_ROLE, COUNT(*) AS CNT
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE STANDARDIZED_ROLE IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;


-- ---------------------------------------------------------------------------
-- SECTION 5: Cortex COMPLETE — skill cluster assignment
-- Prompts the LLM to assign each respondent's tech stack to a semantic cluster.
-- Applied only to respondents with a language stack (reduces cost).
-- ---------------------------------------------------------------------------

UPDATE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES e
SET
    SKILL_CLUSTER_RAW = SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-7b',
        CONCAT(
            'You are classifying developer skill profiles. ',
            'Given this technology stack: "', a.LANGUAGE_HAVE_WORKED_WITH, '"',
            ', assign it to exactly ONE cluster from this list: ',
            'Web & JavaScript, Data & Python, Systems & Low-Level, ',
            'Cloud & DevOps, Mobile & Cross-Platform, Enterprise & JVM, ',
            'Full-Stack Generalist, Other. ',
            'Respond with only the cluster name. No explanation.'
        )
    ),
    SKILL_CLUSTER = TRIM(
        SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-7b',
            CONCAT(
                'You are classifying developer skill profiles. ',
                'Given this technology stack: "', a.LANGUAGE_HAVE_WORKED_WITH, '"',
                ', assign it to exactly ONE cluster from this list: ',
                'Web & JavaScript, Data & Python, Systems & Low-Level, ',
                'Cloud & DevOps, Mobile & Cross-Platform, Enterprise & JVM, ',
                'Full-Stack Generalist, Other. ',
                'Respond with only the cluster name. No explanation.'
            )
        )
    )
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS a
WHERE e.RESPONSE_ID = a.RESPONSE_ID
  AND a.LANGUAGE_HAVE_WORKED_WITH IS NOT NULL;

-- Clean up any rows where the LLM returned extra text instead of a clean label
UPDATE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
SET SKILL_CLUSTER = 'Other'
WHERE SKILL_CLUSTER IS NOT NULL
  AND SKILL_CLUSTER NOT IN (
    'Web & JavaScript', 'Data & Python', 'Systems & Low-Level',
    'Cloud & DevOps', 'Mobile & Cross-Platform', 'Enterprise & JVM',
    'Full-Stack Generalist', 'Other'
  );

-- Verify cluster distribution
SELECT SKILL_CLUSTER, COUNT(*) AS CNT
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE SKILL_CLUSTER IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;


-- ---------------------------------------------------------------------------
-- SECTION 6: Cortex CLASSIFY_TEXT — AI attitude category
-- ---------------------------------------------------------------------------

UPDATE DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES e
SET AI_ATTITUDE_CATEGORY = r.LABEL
FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES c,
LATERAL (
    SELECT PARSE_JSON(
        SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
            c.AI_SENTIMENT_RAW,
            ARRAY_CONSTRUCT('Enthusiast', 'Cautious', 'Skeptic', 'Neutral')
        )
    )['label']::VARCHAR AS LABEL
) r
WHERE e.RESPONSE_ID = c.RESPONSE_ID
  AND c.AI_SENTIMENT_RAW IS NOT NULL;


-- ---------------------------------------------------------------------------
-- SECTION 7: Final coverage check
-- BRD requires: PCT_SENTIMENT >= 60%, PCT_STD_ROLE >= 80%, PCT_SKILL_CLUSTER >= 50%
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*)                                                               AS TOTAL_ROWS,
    ROUND(SUM(CASE WHEN JOB_SAT_SENTIMENT_SCORE IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1)                                            AS PCT_SENTIMENT,
    ROUND(SUM(CASE WHEN STANDARDIZED_ROLE IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1)                                            AS PCT_STD_ROLE,
    ROUND(SUM(CASE WHEN SKILL_CLUSTER IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1)                                            AS PCT_SKILL_CLUSTER,
    ROUND(SUM(CASE WHEN AI_ATTITUDE_CATEGORY IS NOT NULL THEN 1.0 END)
          / COUNT(*) * 100, 1)                                            AS PCT_AI_ATTITUDE
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES;
-- Expected: PCT_SENTIMENT >= 60, PCT_STD_ROLE >= 80, PCT_SKILL_CLUSTER >= 50

-- =============================================================================
-- END 04_cortex_enrich.sql
-- Next: Run 05_cortex_ml.sql to train the salary forecast model
-- =============================================================================
