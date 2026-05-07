-- =============================================================================
-- DevPulseIntel | 01_staging.sql
-- Purpose : Database, schemas, warehouses, file format, internal stage,
--           raw table DDL (RAW.RAW_SURVEY_RESPONSES), and Snowpipe
-- Run as  : ACCOUNTADMIN (or SYSADMIN with sufficient grants)
-- Idempotent: Yes — safe to re-run (CREATE OR REPLACE / IF NOT EXISTS)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- SECTION 1: Database and Schemas
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS DEVPULSEINTEL
  COMMENT = 'DevPulseIntel: Developer Ecosystem Intelligence Platform | SO Survey 2024';

CREATE SCHEMA IF NOT EXISTS DEVPULSEINTEL.INGESTION
  COMMENT = 'Ingestion layer: internal stage, file format, and Snowpipe';

CREATE SCHEMA IF NOT EXISTS DEVPULSEINTEL.RAW
  COMMENT = 'Raw layer: all 114 survey columns as VARCHAR plus load metadata';

CREATE SCHEMA IF NOT EXISTS DEVPULSEINTEL.CLEAN
  COMMENT = 'Clean layer: typed and null-handled Dynamic Table';

CREATE SCHEMA IF NOT EXISTS DEVPULSEINTEL.ANALYTICS
  COMMENT = 'Analytics layer: business-logic Dynamic Table ready for reporting';

CREATE SCHEMA IF NOT EXISTS DEVPULSEINTEL.ENRICHED
  COMMENT = 'Enriched layer: Cortex LLM and ML outputs, materialized once';

-- ---------------------------------------------------------------------------
-- SECTION 2: Warehouses
-- All XSMALL, 60s auto-suspend, separated by workload for cost attribution.
-- ---------------------------------------------------------------------------

USE DATABASE DEVPULSEINTEL;

CREATE WAREHOUSE IF NOT EXISTS DEVPULSE_LOAD_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  COMMENT          = 'Used for COPY INTO loads only';

CREATE WAREHOUSE IF NOT EXISTS DEVPULSE_TRANSFORM_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  COMMENT          = 'Used for Dynamic Table manual refresh operations';

CREATE WAREHOUSE IF NOT EXISTS DEVPULSE_CORTEX_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  COMMENT          = 'Used for all Cortex AI/ML enrichment — run once only';

CREATE WAREHOUSE IF NOT EXISTS DEVPULSE_APP_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  COMMENT          = 'Used by the Streamlit in Snowflake application';

-- ---------------------------------------------------------------------------
-- SECTION 3: File Format and Internal Stage
-- ---------------------------------------------------------------------------

USE SCHEMA DEVPULSEINTEL.INGESTION;
USE WAREHOUSE DEVPULSE_LOAD_WH;

CREATE OR REPLACE FILE FORMAT SURVEY_CSV_FORMAT
  TYPE                        = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER                 = 1
  NULL_IF                     = ('NA', 'NULL', '', 'N/A')
  EMPTY_FIELD_AS_NULL         = TRUE
  ENCODING                    = 'UTF-8'
  COMMENT                     = 'CSV format for Stack Overflow survey export';

CREATE STAGE IF NOT EXISTS RAW_STAGE
  FILE_FORMAT = (FORMAT_NAME = 'DEVPULSEINTEL.INGESTION.SURVEY_CSV_FORMAT')
  COMMENT     = 'Internal stage: upload survey_results_public.csv here before running 02_raw_load.sql';

-- Verify stage is ready (returns 0 rows until file is uploaded — that is expected)
LIST @DEVPULSEINTEL.INGESTION.RAW_STAGE;

-- ---------------------------------------------------------------------------
-- SECTION 4: Raw Table DDL
-- Naming: RAW.RAW_SURVEY_RESPONSES (BRD-aligned)
-- Design: all 114 survey columns as VARCHAR — no casting, no business logic.
--         Two underscore-prefixed metadata columns appended at the end.
-- Note:   CSV column 6 is "Check" — a SQL reserved word. Renamed CHECK_COL.
-- ---------------------------------------------------------------------------

USE SCHEMA DEVPULSEINTEL.RAW;

CREATE OR REPLACE TABLE RAW_SURVEY_RESPONSES (
    -- -----------------------------------------------------------------------
    -- Survey columns ($1–$114), order matches survey_results_public.csv header
    -- -----------------------------------------------------------------------
    RESPONSEID                                         VARCHAR,
    MAINBRANCH                                         VARCHAR,
    AGE                                                VARCHAR,
    EMPLOYMENT                                         VARCHAR,
    REMOTEWORK                                         VARCHAR,
    CHECK_COL                                          VARCHAR,   -- source: "Check" — reserved word
    CODINGACTIVITIES                                   VARCHAR,
    EDLEVEL                                            VARCHAR,
    LEARNCODE                                          VARCHAR,
    LEARNCODEONLINE                                    VARCHAR,
    TECHDOC                                            VARCHAR,
    YEARSCODE                                          VARCHAR,
    YEARSCODEPRO                                       VARCHAR,
    DEVTYPE                                            VARCHAR,
    ORGSIZE                                            VARCHAR,
    PURCHASEINFLUENCE                                  VARCHAR,
    BUYNEWTOOL                                         VARCHAR,
    BUILDVSBUY                                         VARCHAR,
    TECHENDORSE                                        VARCHAR,
    COUNTRY                                            VARCHAR,
    CURRENCY                                           VARCHAR,
    COMPTOTAL                                          VARCHAR,
    LANGUAGEHAVEWORKEDWITH                             VARCHAR,
    LANGUAGEWANTTOWORKWITH                             VARCHAR,
    LANGUAGEADMIRED                                    VARCHAR,
    DATABASEHAVEWORKEDWITH                             VARCHAR,
    DATABASEWANTTOWORKWITH                             VARCHAR,
    DATABASEADMIRED                                    VARCHAR,
    PLATFORMHAVEWORKEDWITH                             VARCHAR,
    PLATFORMWANTTOWORKWITH                             VARCHAR,
    PLATFORMADMIRED                                    VARCHAR,
    WEBFRAMEHAVEWORKEDWITH                             VARCHAR,
    WEBFRAMEWANTTOWORKWITH                             VARCHAR,
    WEBFRAMEADMIRED                                    VARCHAR,
    EMBEDDEDHAVEWORKEDWITH                             VARCHAR,
    EMBEDDEDWANTTOWORKWITH                             VARCHAR,
    EMBEDDEDADMIRED                                    VARCHAR,
    MISCTECHHAVEWORKEDWITH                             VARCHAR,
    MISCTECHWANTTOWORKWITH                             VARCHAR,
    MISCTECHADMIRED                                    VARCHAR,
    TOOLSTECHHAVEWORKEDWITH                            VARCHAR,
    TOOLSTECHWANTTOWORKWITH                            VARCHAR,
    TOOLSTECHADMIRED                                   VARCHAR,
    NEWCOLLABTOOLSHAVEWORKEDWITH                       VARCHAR,
    NEWCOLLABTOOLSWANTTOWORKWITH                       VARCHAR,
    NEWCOLLABTOOLSADMIRED                              VARCHAR,
    OPSYSPERSONAL_USE                                  VARCHAR,
    OPSYSPROFESSIONAL_USE                              VARCHAR,
    OFFICESTACKASYNCHAVEWORKEDWITH                     VARCHAR,
    OFFICESTACKASYNCWANTTOWORKWITH                     VARCHAR,
    OFFICESTACKASYNCADMIRED                            VARCHAR,
    OFFICESTACKSYNCHAVEWORKEDWITH                      VARCHAR,
    OFFICESTACKSYNCWANTTOWORKWITH                      VARCHAR,
    OFFICESTACKSYNCADMIRED                             VARCHAR,
    AISEARCHDEVHAVEWORKEDWITH                          VARCHAR,
    AISEARCHDEVWANTTOWORKWITH                          VARCHAR,
    AISEARCHDEVADMIRED                                 VARCHAR,
    NEWSOSITES                                         VARCHAR,
    SOVISITFREQ                                        VARCHAR,
    SOACCOUNT                                          VARCHAR,
    SOPARTFREQ                                         VARCHAR,
    SOHOW                                              VARCHAR,
    SOCOMM                                             VARCHAR,
    AISELECT                                           VARCHAR,
    AISENT                                             VARCHAR,
    AIBEN                                              VARCHAR,
    AIACC                                              VARCHAR,
    AICOMPLEX                                          VARCHAR,
    AITOOLCURRENTLY_USING                              VARCHAR,
    AITOOLINTERESTED_IN_USING                          VARCHAR,
    AITOOLNOT_INTERESTED_IN_USING                      VARCHAR,
    AINEXTMUCH_MORE_INTEGRATED                         VARCHAR,
    AINEXTNO_CHANGE                                    VARCHAR,
    AINEXTMORE_INTEGRATED                              VARCHAR,
    AINEXTLESS_INTEGRATED                              VARCHAR,
    AINEXTMUCH_LESS_INTEGRATED                         VARCHAR,
    AITHREAT                                           VARCHAR,
    AIETHICS                                           VARCHAR,
    AICHALLENGES                                       VARCHAR,
    TBRANCH                                            VARCHAR,
    ICORPM                                             VARCHAR,
    WORKEXP                                            VARCHAR,
    KNOWLEDGE_1                                        VARCHAR,
    KNOWLEDGE_2                                        VARCHAR,
    KNOWLEDGE_3                                        VARCHAR,
    KNOWLEDGE_4                                        VARCHAR,
    KNOWLEDGE_5                                        VARCHAR,
    KNOWLEDGE_6                                        VARCHAR,
    KNOWLEDGE_7                                        VARCHAR,
    KNOWLEDGE_8                                        VARCHAR,
    KNOWLEDGE_9                                        VARCHAR,
    FREQUENCY_1                                        VARCHAR,
    FREQUENCY_2                                        VARCHAR,
    FREQUENCY_3                                        VARCHAR,
    TIMESEARCHING                                      VARCHAR,
    TIMEANSWERING                                      VARCHAR,
    FRUSTRATION                                        VARCHAR,
    PROFESSIONALTECH                                   VARCHAR,
    PROFESSIONALCLOUD                                  VARCHAR,
    PROFESSIONALQUESTION                               VARCHAR,
    INDUSTRY                                           VARCHAR,
    JOBSATPOINTS_1                                     VARCHAR,
    JOBSATPOINTS_4                                     VARCHAR,
    JOBSATPOINTS_5                                     VARCHAR,
    JOBSATPOINTS_6                                     VARCHAR,
    JOBSATPOINTS_7                                     VARCHAR,
    JOBSATPOINTS_8                                     VARCHAR,
    JOBSATPOINTS_9                                     VARCHAR,
    JOBSATPOINTS_10                                    VARCHAR,
    JOBSATPOINTS_11                                    VARCHAR,
    SURVEYLENGTH                                       VARCHAR,
    SURVEYEASE                                         VARCHAR,
    CONVERTEDCOMPYEARLY                                VARCHAR,
    JOBSAT                                             VARCHAR,

    -- -----------------------------------------------------------------------
    -- Load metadata — populated by COPY INTO, not from CSV content
    -- -----------------------------------------------------------------------
    _SOURCE_FILE_NAME                                  VARCHAR,
    _LOAD_TIMESTAMP                                    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
    
)
COMMENT = 'RAW layer: 114 SO 2024 survey columns (all VARCHAR) + 2 load metadata columns. No transformations applied here.';

COMMENT ON COLUMN DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES._SOURCE_FILE_NAME
  IS 'Populated from METADATA$FILENAME at load time';

COMMENT ON COLUMN DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES._LOAD_TIMESTAMP
  IS 'Wall-clock time when the row was inserted';
-- ---------------------------------------------------------------------------
-- SECTION 5: Snowpipe
-- AUTO_INGEST = FALSE — triggered manually via COPY INTO in 02_raw_load.sql.
-- Pipe is defined here to register the intent; actual load runs in script 02.
-- ---------------------------------------------------------------------------

USE SCHEMA DEVPULSEINTEL.INGESTION;

CREATE OR REPLACE PIPE SURVEY_PIPE
  AUTO_INGEST = FALSE
  COMMENT     = 'Snowpipe definition for RAW_SURVEY_RESPONSES. Trigger manually via 02_raw_load.sql.'
AS
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
FILE_FORMAT = (FORMAT_NAME = 'DEVPULSEINTEL.INGESTION.SURVEY_CSV_FORMAT');
-- Note: _LOAD_TIMESTAMP is excluded from COPY INTO — it uses DEFAULT CURRENT_TIMESTAMP()

-- ---------------------------------------------------------------------------
-- SECTION 6: Verify objects were created
-- ---------------------------------------------------------------------------

SHOW SCHEMAS   IN DATABASE DEVPULSEINTEL;
SHOW WAREHOUSES LIKE 'DEVPULSE%';
SHOW STAGES    IN SCHEMA  DEVPULSEINTEL.INGESTION;
SHOW PIPES     IN SCHEMA  DEVPULSEINTEL.INGESTION;

-- Confirm table structure (should show 116 columns: 114 survey + 2 metadata)
DESCRIBE TABLE DEVPULSEINTEL.RAW.RAW_SURVEY_RESPONSES;

-- =============================================================================
-- END 01_staging.sql
-- Next: Upload survey_results_public.csv to @RAW_STAGE, then run 02_raw_load.sql
-- =============================================================================
