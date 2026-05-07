-- =============================================================================
-- DevPulseIntel | 02_raw_load.sql
-- Purpose : Load survey_results_public.csv into RAW.RAW_SURVEY_RESPONSES
-- Prereq  : 01_staging.sql must be run first
--           survey_results_public.csv must be uploaded to @RAW_STAGE
-- Idempotent: FORCE = FALSE means already-loaded files are skipped safely
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DEVPULSE_LOAD_WH;
USE DATABASE DEVPULSEINTEL;
USE SCHEMA INGESTION;

-- ---------------------------------------------------------------------------
-- SECTION 1: Pre-load checks
-- ---------------------------------------------------------------------------

-- Confirm the file is on the stage before loading
-- Expected: one row showing survey_results_public.csv with file size and md5
LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE;

-- Preview first 5 rows to verify column alignment before committing the full load
-- If column 1 is not a numeric ResponseId, the file format or header skip is wrong
SELECT
    $1  AS RESPONSEID_PREVIEW,
    $20 AS COUNTRY_PREVIEW,
    $22 AS COMPTOTAL_PREVIEW,
    $113 AS CONVERTEDCOMPYEARLY_PREVIEW,
    $114 AS JOBSAT_PREVIEW
FROM @DEVPULSEINTEL.INGESTION.RAW_STAGE
(FILE_FORMAT => 'DEVPULSEINTEL.INGESTION.SURVEY_CSV_FORMAT')
LIMIT 5;

-- ---------------------------------------------------------------------------
-- SECTION 2: Load raw data
-- Design notes:
--   ON_ERROR = CONTINUE : Skip malformed rows rather than failing the load.
--     Survey free-text responses can contain embedded newlines or unescaped
--     quotes. Minor row loss at RAW is acceptable; CLEAN layer handles quality.
--   PURGE = FALSE        : Keep the file on the stage for reloads if needed.
--   FORCE = FALSE        : Skip files already successfully loaded (default).
--     Set FORCE = TRUE only if you dropped and recreated the table.
--   _LOAD_TIMESTAMP      : Excluded from the column list — table DEFAULT handles it.
--   _SOURCE_FILE_NAME    : Populated from METADATA$FILENAME.
-- ---------------------------------------------------------------------------

COPY INTO DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES (
    RESPONSEID, MAINBRANCH, AGE, EMPLOYMENT, REMOTEWORK,
    CHECK_COL, CODINGACTIVITIES, EDLEVEL, LEARNCODE, LEARNCODEONLINE,
    TECHDOC, YEARSCODE, YEARSCODEPRO, DEVTYPE, ORGSIZE,
    PURCHASEINFLUENCE, BUYNEWTOOL, BUILDVSBUY, TECHENDORSE, COUNTRY,
    CURRENCY, COMPTOTAL,
    LANGUAGEHAVEWORKEDWITH, LANGUAGEWANTTOWORKWITH, LANGUAGEADMIRED,
    DATABASEHAVEWORKEDWITH, DATABASEWANTTOWORKWITH, DATABASEADMIRED,
    PLATFORMHAVEWORKEDWITH, PLATFORMWANTTOWORKWITH, PLATFORMADMIRED,
    WEBFRAMEHAVEWORKEDWITH, WEBFRAMEWANTTOWORKWITH, WEBFRAMEADMIRED,
    EMBEDDEDHAVEWORKEDWITH, EMBEDDEDWANTTOWORKWITH, EMBEDDEDADMIRED,
    MISCTECHHAVEWORKEDWITH, MISCTECHWANTTOWORKWITH, MISCTECHADMIRED,
    TOOLSTECHHAVEWORKEDWITH, TOOLSTECHWANTTOWORKWITH, TOOLSTECHADMIRED,
    NEWCOLLABTOOLSHAVEWORKEDWITH, NEWCOLLABTOOLSWANTTOWORKWITH, NEWCOLLABTOOLSADMIRED,
    OPSYSPERSONAL_USE, OPSYSPROFESSIONAL_USE,
    OFFICESTACKASYNCHAVEWORKEDWITH, OFFICESTACKASYNCWANTTOWORKWITH, OFFICESTACKASYNCADMIRED,
    OFFICESTACKSYNCHAVEWORKEDWITH, OFFICESTACKSYNCWANTTOWORKWITH, OFFICESTACKSYNCADMIRED,
    AISEARCHDEVHAVEWORKEDWITH, AISEARCHDEVWANTTOWORKWITH, AISEARCHDEVADMIRED,
    NEWSOSITES, SOVISITFREQ, SOACCOUNT, SOPARTFREQ, SOHOW, SOCOMM,
    AISELECT, AISENT, AIBEN, AIACC, AICOMPLEX,
    AITOOLCURRENTLY_USING, AITOOLINTERESTED_IN_USING, AITOOLNOT_INTERESTED_IN_USING,
    AINEXTMUCH_MORE_INTEGRATED, AINEXTNO_CHANGE, AINEXTMORE_INTEGRATED,
    AINEXTLESS_INTEGRATED, AINEXTMUCH_LESS_INTEGRATED,
    AITHREAT, AIETHICS, AICHALLENGES,
    TBRANCH, ICORPM, WORKEXP,
    KNOWLEDGE_1, KNOWLEDGE_2, KNOWLEDGE_3, KNOWLEDGE_4, KNOWLEDGE_5,
    KNOWLEDGE_6, KNOWLEDGE_7, KNOWLEDGE_8, KNOWLEDGE_9,
    FREQUENCY_1, FREQUENCY_2, FREQUENCY_3,
    TIMESEARCHING, TIMEANSWERING, FRUSTRATION,
    PROFESSIONALTECH, PROFESSIONALCLOUD, PROFESSIONALQUESTION,
    INDUSTRY,
    JOBSATPOINTS_1, JOBSATPOINTS_4, JOBSATPOINTS_5, JOBSATPOINTS_6,
    JOBSATPOINTS_7, JOBSATPOINTS_8, JOBSATPOINTS_9, JOBSATPOINTS_10, JOBSATPOINTS_11,
    SURVEYLENGTH, SURVEYEASE, CONVERTEDCOMPYEARLY, JOBSAT,
    _SOURCE_FILE_NAME
)
FROM (
    SELECT
        $1,   $2,   $3,   $4,   $5,   $6,   $7,   $8,   $9,   $10,
        $11,  $12,  $13,  $14,  $15,  $16,  $17,  $18,  $19,  $20,
        $21,  $22,  $23,  $24,  $25,  $26,  $27,  $28,  $29,  $30,
        $31,  $32,  $33,  $34,  $35,  $36,  $37,  $38,  $39,  $40,
        $41,  $42,  $43,  $44,  $45,  $46,  $47,  $48,  $49,  $50,
        $51,  $52,  $53,  $54,  $55,  $56,  $57,  $58,  $59,  $60,
        $61,  $62,  $63,  $64,  $65,  $66,  $67,  $68,  $69,  $70,
        $71,  $72,  $73,  $74,  $75,  $76,  $77,  $78,  $79,  $80,
        $81,  $82,  $83,  $84,  $85,  $86,  $87,  $88,  $89,  $90,
        $91,  $92,  $93,  $94,  $95,  $96,  $97,  $98,  $99,  $100,
        $101, $102, $103, $104, $105, $106, $107, $108, $109, $110,
        $111, $112, $113, $114,
        METADATA$FILENAME
    FROM @DEVPULSEINTEL.INGESTION.RAW_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'DEVPULSEINTEL.INGESTION.SURVEY_CSV_FORMAT')
ON_ERROR    = 'CONTINUE'
PURGE       = FALSE
FORCE       = FALSE;

-- ---------------------------------------------------------------------------
-- SECTION 3: Post-load validation
-- ---------------------------------------------------------------------------

-- Overall row count — expect ~65,000 for the 2024 survey
SELECT COUNT(*) AS TOTAL_ROWS
FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;


-- Metadata column spot-check — confirms _SOURCE_FILE_NAME and _LOAD_TIMESTAMP populated
SELECT
    _SOURCE_FILE_NAME,
    MIN(_LOAD_TIMESTAMP) AS FIRST_LOADED,
    MAX(_LOAD_TIMESTAMP) AS LAST_LOADED,
    COUNT(*)             AS ROW_COUNT
FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
GROUP BY 1;

-- Key column coverage — confirm the columns DevPulseIntel depends on are populated
SELECT
    COUNT(*)                                                        AS TOTAL_ROWS,
    COUNT(CONVERTEDCOMPYEARLY)                                      AS HAS_SALARY,
    COUNT(LANGUAGEHAVEWORKEDWITH)                                   AS HAS_LANGUAGES,
    COUNT(DEVTYPE)                                                  AS HAS_DEV_TYPE,
    COUNT(YEARSCODEPRO)                                             AS HAS_EXPERIENCE,
    COUNT(AISELECT)                                                 AS HAS_AI_RESPONSE,
    COUNT(JOBSAT)                                                   AS HAS_JOB_SAT,
    COUNT(COUNTRY)                                                  AS HAS_COUNTRY,
    ROUND(COUNT(CONVERTEDCOMPYEARLY) / COUNT(*) * 100, 1)          AS PCT_HAS_SALARY
FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;

-- Sample 5 rows — visually verify values land in the right columns
SELECT
    RESPONSEID,
    COUNTRY,
    YEARSCODEPRO,
    DEVTYPE,
    CONVERTEDCOMPYEARLY,
    LANGUAGEHAVEWORKEDWITH,
    AISELECT,
    _SOURCE_FILE_NAME,
    _LOAD_TIMESTAMP
FROM DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES
LIMIT 5;

-- ---------------------------------------------------------------------------
-- SECTION 4: Column alignment troubleshooting (run only if spot-check fails)
-- ---------------------------------------------------------------------------
-- If values are in the wrong columns (e.g. COUNTRY contains a salary value),
-- the $N positional references in the COPY INTO SELECT are misaligned.
-- Steps to fix:
--   1. Open survey_results_schema.csv — lists column names in exact CSV order
--   2. Match each name to its $N position (1-indexed)
--   3. Truncate and reload:
--        TRUNCATE TABLE DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;
--        Re-run SECTION 2 with FORCE = TRUE
-- ---------------------------------------------------------------------------

-- =============================================================================
-- END 02_raw_load.sql
-- Expected output: ~65,000 rows in RAW.RAW_SURVEY_RESPONSES
-- Next: Run 03_dynamic_tables.sql to build CLEAN and ANALYTICS layers
-- =============================================================================
