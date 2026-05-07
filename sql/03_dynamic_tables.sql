-- =============================================================================
-- DevPulseIntel | 03_dynamic_tables.sql
-- Purpose : CLEAN and ANALYTICS Dynamic Tables (Medallion layers 2 & 3)
-- Run as  : ACCOUNTADMIN
-- Prereq  : 02_raw_load.sql must be complete; RAW.RAW_SURVEY_RESPONSES has rows
-- Idempotent: Yes — CREATE OR REPLACE
-- =============================================================================
-- Column naming strategy
--   RAW layer  : column names match CSV headers exactly (RESPONSEID, YEARSCODEPRO)
--   CLEAN layer: RAW columns aliased to readable snake_case (RESPONSE_ID, YEARS_CODE_PRO)
--                Type casting and null handling applied here.
--   ANALYTICS  : business logic layered on CLEAN output.
--                Downstream scripts (04-06) and app.py use CLEAN/ANALYTICS names.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DEVPULSE_TRANSFORM_WH;
USE DATABASE DEVPULSEINTEL;

-- ---------------------------------------------------------------------------
-- SECTION 1: CLEAN Dynamic Table
-- Transforms RAW (all VARCHAR, CSV-derived names) into typed, named, clean data.
-- One row per respondent. No aggregation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
  TARGET_LAG = '9999 days'
  WAREHOUSE  = DEVPULSE_TRANSFORM_WH
  COMMENT    = 'Clean layer: typed columns, readable names, null handling. Source: RAW.RAW_SURVEY_RESPONSES.'
AS
SELECT
    -- -----------------------------------------------------------------------
    -- Identity
    -- -----------------------------------------------------------------------
    RESPONSEID                                          AS RESPONSE_ID,
    MAINBRANCH                                          AS MAIN_BRANCH,
    TBRANCH                                             AS T_BRANCH,
    ICORPM                                              AS IND_REF,          -- ICorPM: Individual contributor or manager
    INDUSTRY,

    -- -----------------------------------------------------------------------
    -- Demographics
    -- -----------------------------------------------------------------------
    TRIM(UPPER(COUNTRY))                                AS COUNTRY,
    CURRENCY,
    TRIM(AGE)                                           AS AGE,
    TRIM(EDLEVEL)                                       AS ED_LEVEL,
    TRIM(EMPLOYMENT)                                    AS EMPLOYMENT,
    TRIM(REMOTEWORK)                                    AS REMOTE_WORK,
    TRIM(ORGSIZE)                                       AS ORG_SIZE,

    -- -----------------------------------------------------------------------
    -- Experience — normalize text values to integers for analysis
    -- "Less than 1 year" → 0, "More than 50 years" → 51, numeric → cast
    -- -----------------------------------------------------------------------
    CASE
        WHEN LOWER(YEARSCODE)    = 'less than 1 year'   THEN 0
        WHEN LOWER(YEARSCODE)    = 'more than 50 years' THEN 51
        WHEN TRY_CAST(YEARSCODE AS INTEGER) IS NOT NULL
        THEN TRY_CAST(YEARSCODE AS INTEGER)
        ELSE NULL
    END                                                 AS YEARS_CODE_INT,

    CASE
        WHEN LOWER(YEARSCODEPRO) = 'less than 1 year'   THEN 0
        WHEN LOWER(YEARSCODEPRO) = 'more than 50 years' THEN 51
        WHEN TRY_CAST(YEARSCODEPRO AS INTEGER) IS NOT NULL
        THEN TRY_CAST(YEARSCODEPRO AS INTEGER)
        ELSE NULL
    END                                                 AS YEARS_CODE_PRO_INT,

    TRY_CAST(WORKEXP AS INTEGER)                        AS WORK_EXP_INT,

    -- -----------------------------------------------------------------------
    -- Compensation
    -- Remove clearly erroneous values (< $100 or > $2M USD).
    -- CONVERTEDCOMPYEARLY is already normalized to USD by Stack Overflow.
    -- -----------------------------------------------------------------------
    CASE
        WHEN TRY_CAST(CONVERTEDCOMPYEARLY AS FLOAT) IS NULL         THEN NULL
        WHEN TRY_CAST(CONVERTEDCOMPYEARLY AS FLOAT) < 100           THEN NULL
        WHEN TRY_CAST(CONVERTEDCOMPYEARLY AS FLOAT) > 2000000       THEN NULL
        ELSE TRY_CAST(CONVERTEDCOMPYEARLY AS FLOAT)
    END                                                 AS ANNUAL_COMP_USD,

    -- -----------------------------------------------------------------------
    -- Role
    -- -----------------------------------------------------------------------
    TRIM(DEVTYPE)                                       AS DEV_TYPE,

    -- -----------------------------------------------------------------------
    -- Technologies (kept as semicolon-delimited; split in ANALYTICS)
    -- -----------------------------------------------------------------------
    LANGUAGEHAVEWORKEDWITH                              AS LANGUAGE_HAVE_WORKED_WITH,
    LANGUAGEWANTTOWORKWITH                              AS LANGUAGE_WANT_TO_WORK_WITH,
    LANGUAGEADMIRED                                     AS LANGUAGE_ADMIRED,
    DATABASEHAVEWORKEDWITH                              AS DATABASE_HAVE_WORKED_WITH,
    DATABASEWANTTOWORKWITH                              AS DATABASE_WANT_TO_WORK_WITH,
    PLATFORMHAVEWORKEDWITH                              AS PLATFORM_HAVE_WORKED_WITH,
    PLATFORMWANTTOWORKWITH                              AS PLATFORM_WANT_TO_WORK_WITH,
    WEBFRAMEHAVEWORKEDWITH                              AS WEBFRAME_HAVE_WORKED_WITH,
    WEBFRAMEWANTTOWORKWITH                              AS WEBFRAME_WANT_TO_WORK_WITH,
    MISCTECHHAVEWORKEDWITH                              AS MISC_TECH_HAVE_WORKED_WITH,
    TOOLSTECHHAVEWORKEDWITH                             AS TOOLS_TECH_HAVE_WORKED_WITH,
    NEWCOLLABTOOLSHAVEWORKEDWITH                        AS COLLAB_TOOLS_HAVE_WORKED_WITH,

    -- -----------------------------------------------------------------------
    -- AI tools and attitudes
    -- -----------------------------------------------------------------------
    TRIM(AISELECT)                                      AS AI_SELECT,
    TRIM(AISENT)                                        AS AI_SENTIMENT_RAW,
    TRIM(AIBEN)                                         AS AI_BENEFIT_RAW,
    TRIM(AIACC)                                         AS AI_ACCURACY_TRUST,
    TRIM(AICOMPLEX)                                     AS AI_COMPLEXITY_TRUST,
    AITOOLCURRENTLY_USING                               AS AI_TOOL_CURRENTLY_USING,
    AITOOLINTERESTED_IN_USING                           AS AI_TOOL_WANT_TO_USE,
    AITOOLNOT_INTERESTED_IN_USING                       AS AI_TOOL_NOT_INTERESTED,
    TRIM(AITHREAT)                                      AS AI_THREAT_JOB,
    TRIM(AIETHICS)                                      AS AI_ETHICS,

    -- AI next integration expectations (five-point scale, kept separate)
    AINEXTMUCH_MORE_INTEGRATED                          AS AI_NEXT_MUCH_MORE,
    AINEXTMORE_INTEGRATED                               AS AI_NEXT_MORE,
    AINEXTNO_CHANGE                                     AS AI_NEXT_NO_CHANGE,
    AINEXTLESS_INTEGRATED                               AS AI_NEXT_LESS,
    AINEXTMUCH_LESS_INTEGRATED                          AS AI_NEXT_MUCH_LESS,

    -- AI search / developer tools
    AISEARCHDEVHAVEWORKEDWITH                           AS AI_SEARCH_DEV_USED,
    AISEARCHDEVWANTTOWORKWITH                           AS AI_SEARCH_DEV_WANT,

    -- -----------------------------------------------------------------------
    -- Satisfaction
    -- -----------------------------------------------------------------------
    TRIM(JOBSAT)                                        AS JOB_SAT,

    -- -----------------------------------------------------------------------
    -- Learning and SO community
    -- -----------------------------------------------------------------------
    LEARNCODE                                           AS LEARN_CODE,
    LEARNCODEONLINE                                     AS LEARN_CODE_ONLINE,
    TRIM(CODINGACTIVITIES)                              AS CODING_ACTIVITIES,
    TRIM(SOVISITFREQ)                                   AS SO_VISIT_FREQ,
    SOACCOUNT                                           AS SO_ACCOUNT,
    TRIM(SOPARTFREQ)                                    AS SO_PART_FREQ,

    -- -----------------------------------------------------------------------
    -- Survey meta
    -- -----------------------------------------------------------------------
    TRIM(SURVEYLENGTH)                                  AS SURVEY_LENGTH,
    TRIM(SURVEYEASE)                                    AS SURVEY_EASE,

    -- -----------------------------------------------------------------------
    -- Load metadata (pass-through)
    -- -----------------------------------------------------------------------
    _SOURCE_FILE_NAME,
    _LOAD_TIMESTAMP

FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
WHERE RESPONSEID IS NOT NULL;


-- ---------------------------------------------------------------------------
-- SECTION 2: ANALYTICS Dynamic Table
-- Builds on CLEAN. Adds business logic: salary bands, experience buckets,
-- AI adoption flags, primary role/language extraction, developer filter.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
  TARGET_LAG = '9999 days'
  WAREHOUSE  = DEVPULSE_TRANSFORM_WH
  COMMENT    = 'Analytics layer: professional developers only, enriched with business metrics. Source: CLEAN.DT_CLEAN_RESPONSES.'
AS
SELECT
    RESPONSE_ID,
    COUNTRY,
    EMPLOYMENT,
    REMOTE_WORK,
    ORG_SIZE,
    ED_LEVEL,
    INDUSTRY,
    IND_REF,
    DEV_TYPE,
    YEARS_CODE_PRO_INT,
    WORK_EXP_INT,
    ANNUAL_COMP_USD,
    AI_SELECT,
    AI_THREAT_JOB,
    AI_TOOL_CURRENTLY_USING,
    AI_TOOL_WANT_TO_USE,
    AI_SENTIMENT_RAW,
    AI_SEARCH_DEV_USED,
    JOB_SAT,
    LANGUAGE_HAVE_WORKED_WITH,
    LANGUAGE_WANT_TO_WORK_WITH,
    DATABASE_HAVE_WORKED_WITH,
    PLATFORM_HAVE_WORKED_WITH,
    WEBFRAME_HAVE_WORKED_WITH,
    MISC_TECH_HAVE_WORKED_WITH,
    TOOLS_TECH_HAVE_WORKED_WITH,
    COLLAB_TOOLS_HAVE_WORKED_WITH,

    -- -----------------------------------------------------------------------
    -- Salary band
    -- -----------------------------------------------------------------------
    CASE
        WHEN ANNUAL_COMP_USD IS NULL         THEN 'Unknown'
        WHEN ANNUAL_COMP_USD < 30000         THEN 'Under $30K'
        WHEN ANNUAL_COMP_USD < 60000         THEN '$30K–$60K'
        WHEN ANNUAL_COMP_USD < 100000        THEN '$60K–$100K'
        WHEN ANNUAL_COMP_USD < 150000        THEN '$100K–$150K'
        WHEN ANNUAL_COMP_USD < 200000        THEN '$150K–$200K'
        ELSE                                      'Over $200K'
    END                                             AS SALARY_BAND,

    CASE
        WHEN ANNUAL_COMP_USD IS NULL         THEN 0
        WHEN ANNUAL_COMP_USD < 30000         THEN 1
        WHEN ANNUAL_COMP_USD < 60000         THEN 2
        WHEN ANNUAL_COMP_USD < 100000        THEN 3
        WHEN ANNUAL_COMP_USD < 150000        THEN 4
        WHEN ANNUAL_COMP_USD < 200000        THEN 5
        ELSE                                      6
    END                                             AS SALARY_BAND_SORT,

    -- -----------------------------------------------------------------------
    -- Experience bucket
    -- -----------------------------------------------------------------------
    CASE
        WHEN YEARS_CODE_PRO_INT IS NULL      THEN 'Unknown'
        WHEN YEARS_CODE_PRO_INT = 0          THEN '< 1 year'
        WHEN YEARS_CODE_PRO_INT <= 2         THEN '1–2 years'
        WHEN YEARS_CODE_PRO_INT <= 5         THEN '3–5 years'
        WHEN YEARS_CODE_PRO_INT <= 10        THEN '6–10 years'
        WHEN YEARS_CODE_PRO_INT <= 20        THEN '11–20 years'
        ELSE                                      '20+ years'
    END                                             AS EXPERIENCE_BUCKET,

    CASE
        WHEN YEARS_CODE_PRO_INT IS NULL      THEN 0
        WHEN YEARS_CODE_PRO_INT = 0          THEN 1
        WHEN YEARS_CODE_PRO_INT <= 2         THEN 2
        WHEN YEARS_CODE_PRO_INT <= 5         THEN 3
        WHEN YEARS_CODE_PRO_INT <= 10        THEN 4
        WHEN YEARS_CODE_PRO_INT <= 20        THEN 5
        ELSE                                      6
    END                                             AS EXPERIENCE_BUCKET_SORT,

    -- -----------------------------------------------------------------------
    -- Primary language (first value in semicolon-delimited string)
    -- -----------------------------------------------------------------------
    TRIM(SPLIT_PART(LANGUAGE_HAVE_WORKED_WITH, ';', 1))  AS PRIMARY_LANGUAGE,

    -- -----------------------------------------------------------------------
    -- Primary developer role (first value in semicolon-delimited string)
    -- -----------------------------------------------------------------------
    TRIM(SPLIT_PART(DEV_TYPE, ';', 1))                   AS PRIMARY_DEV_ROLE,

    -- -----------------------------------------------------------------------
    -- AI adoption flag
    -- -----------------------------------------------------------------------
    CASE
        WHEN LOWER(AI_SELECT) IN ('yes', 'i use it in my dev work') THEN TRUE
        ELSE FALSE
    END                                                  AS USES_AI_TOOLS,

    -- -----------------------------------------------------------------------
    -- Job satisfaction score (ordinal: 1 = very dissatisfied → 5 = very satisfied)
    -- -----------------------------------------------------------------------
    CASE
        WHEN LOWER(JOB_SAT) LIKE '%very satisfied%'       THEN 5
        WHEN LOWER(JOB_SAT) LIKE '%satisfied%'            THEN 4
        WHEN LOWER(JOB_SAT) LIKE '%neither%'              THEN 3
        WHEN LOWER(JOB_SAT) LIKE '%dissatisfied%'         THEN 2
        WHEN LOWER(JOB_SAT) LIKE '%very dissatisfied%'    THEN 1
        ELSE NULL
    END                                                  AS JOB_SAT_SCORE

FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
WHERE
    -- Professional developers only
    LOWER(DEV_TYPE) NOT LIKE '%student%'
    -- Must have identified as a developer (exclude pure hobbyists / PMs)
    AND LOWER(MAIN_BRANCH) LIKE '%developer%'
    -- Require a valid response ID
    AND RESPONSE_ID IS NOT NULL;


-- ---------------------------------------------------------------------------
-- SECTION 3: Supporting views (convenience — no compute cost)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW DEVPULSEINTEL.ANALYTICS.V_SALARY_BY_COUNTRY
  COMMENT = 'Median salary and respondent count by country. Source: DT_ANALYTICS_DEVELOPERS.'
AS
SELECT
    COUNTRY,
    COUNT(*)                                            AS RESPONDENT_COUNT,
    ROUND(MEDIAN(ANNUAL_COMP_USD), 0)                  AS MEDIAN_SALARY_USD,
    ROUND(AVG(ANNUAL_COMP_USD), 0)                     AS AVG_SALARY_USD,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP
          (ORDER BY ANNUAL_COMP_USD), 0)               AS P25_SALARY_USD,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
          (ORDER BY ANNUAL_COMP_USD), 0)               AS P75_SALARY_USD
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
WHERE ANNUAL_COMP_USD IS NOT NULL
  AND COUNTRY IS NOT NULL
GROUP BY 1
HAVING COUNT(*) >= 30
ORDER BY MEDIAN_SALARY_USD DESC;


CREATE OR REPLACE VIEW DEVPULSEINTEL.ANALYTICS.V_AI_ADOPTION_BY_ROLE
  COMMENT = 'AI adoption rate by primary developer role. Source: DT_ANALYTICS_DEVELOPERS.'
AS
SELECT
    PRIMARY_DEV_ROLE,
    COUNT(*)                                            AS TOTAL_DEVS,
    SUM(CASE WHEN USES_AI_TOOLS THEN 1 ELSE 0 END)    AS AI_ADOPTERS,
    ROUND(SUM(CASE WHEN USES_AI_TOOLS THEN 1.0 ELSE 0 END)
          / NULLIF(COUNT(*), 0) * 100, 1)             AS ADOPTION_RATE_PCT
FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS
WHERE PRIMARY_DEV_ROLE IS NOT NULL
  AND PRIMARY_DEV_ROLE != ''
GROUP BY 1
HAVING COUNT(*) >= 20
ORDER BY ADOPTION_RATE_PCT DESC;


CREATE OR REPLACE VIEW DEVPULSEINTEL.ANALYTICS.V_LANGUAGE_DEMAND
  COMMENT = 'Language usage count by country. Feeds Skill Demand Analyzer page. Source: DT_ANALYTICS_DEVELOPERS.'
AS
WITH LANG_EXPLODE AS (
    SELECT
        COUNTRY,
        TRIM(VALUE::VARCHAR)                            AS LANGUAGE
    FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS,
        LATERAL FLATTEN(INPUT => SPLIT(LANGUAGE_HAVE_WORKED_WITH, ';'))
    WHERE LANGUAGE_HAVE_WORKED_WITH IS NOT NULL
      AND COUNTRY IS NOT NULL
)
SELECT
    COUNTRY,
    LANGUAGE,
    COUNT(*)                                            AS USAGE_COUNT
FROM LANG_EXPLODE
WHERE LANGUAGE != ''
GROUP BY 1, 2
ORDER BY COUNTRY, USAGE_COUNT DESC;


-- ---------------------------------------------------------------------------
-- SECTION 4: Trigger initial refresh
-- TARGET_LAG = 9999 days means tables do not auto-refresh.
-- Run this once after creation to populate them.
-- ---------------------------------------------------------------------------

ALTER DYNAMIC TABLE DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES       REFRESH;
ALTER DYNAMIC TABLE DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS REFRESH;


-- ---------------------------------------------------------------------------
-- SECTION 5: Verification
-- ---------------------------------------------------------------------------

SHOW DYNAMIC TABLES IN DATABASE DEVPULSEINTEL;

-- Row counts across layers
SELECT 'RAW'       AS LAYER, COUNT(*) AS ROW_COUNT FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
UNION ALL
SELECT 'CLEAN',              COUNT(*)          FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES
UNION ALL
SELECT 'ANALYTICS',          COUNT(*)          FROM DEVPULSEINTEL.ANALYTICS.DT_ANALYTICS_DEVELOPERS;

-- Salary data survival rate through CLEAN filter
SELECT
    COUNT(*)                                                AS TOTAL_CLEAN_ROWS,
    COUNT(ANNUAL_COMP_USD)                                  AS HAS_SALARY,
    ROUND(COUNT(ANNUAL_COMP_USD) / COUNT(*) * 100, 1)      AS PCT_HAS_SALARY,
    ROUND(MEDIAN(ANNUAL_COMP_USD), 0)                       AS GLOBAL_MEDIAN_USD
FROM DEVPULSEINTEL.CLEAN.DT_CLEAN_RESPONSES;

-- =============================================================================
-- END 03_dynamic_tables.sql
-- Next: Run 04_cortex_enrich.sql to populate ENRICHED.ENRICHED_RESPONSES
-- =============================================================================
