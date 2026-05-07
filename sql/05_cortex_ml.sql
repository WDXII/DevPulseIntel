-- =============================================================================
-- DevPulseIntel | 05_cortex_ml.sql
-- Purpose : Train Cortex ML FORECAST model for salary prediction by experience
-- Run as  : ACCOUNTADMIN
-- Run ONCE: Model training consumes credits. Do not retrain unless data changes.
-- Prereq  : 04_cortex_enrich.sql must be run and ENRICHED_RESPONSES populated.
-- =============================================================================
-- Design note:
--   SNOWFLAKE.ML.FORECAST expects a time-series axis. We use YEARS_CODE_PRO_INT
--   as a pseudo-time dimension (0 to 51, representing years of experience).
--   To satisfy the TIMESTAMP input requirement, we convert it to a date offset
--   from a fixed epoch: 2000-01-01 + YEARS_CODE_PRO_INT days.
--   Each COUNTRY is treated as a separate series.
--   The model predicts salary for 10 future experience increments per country.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DEVPULSE_CORTEX_WH;
USE DATABASE DEVPULSEINTEL;
USE SCHEMA ENRICHED;

-- ---------------------------------------------------------------------------
-- SECTION 1: Training view
-- Median salary per experience level per country.
-- Aggregating to median avoids outlier distortion in the training signal.
-- Require at least 5 data points per (country, experience) cell.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW DEVPULSEINTEL.ENRICHED.V_SALARY_TRAINING_INPUT
  COMMENT = 'Training data for Cortex ML FORECAST: median salary by experience (as pseudo-date) and country.'
AS
SELECT
    -- Pseudo-timestamp: fixed epoch + experience years as days
    DATEADD('day', YEARS_CODE_PRO_INT, '2000-01-01'::DATE)::TIMESTAMP_NTZ  AS EXPERIENCE_DATE,
    COUNTRY                                                                  AS SERIES,
    ROUND(MEDIAN(ANNUAL_COMP_USD), 2)                                        AS MEDIAN_SALARY
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE YEARS_CODE_PRO_INT IS NOT NULL
  AND ANNUAL_COMP_USD    IS NOT NULL
  AND COUNTRY            IS NOT NULL
GROUP BY 1, 2
HAVING COUNT(*) >= 5;

-- Preview training data
SELECT * FROM DEVPULSEINTEL.ENRICHED.V_SALARY_TRAINING_INPUT
ORDER BY SERIES, EXPERIENCE_DATE
LIMIT 20;


-- ---------------------------------------------------------------------------
-- SECTION 2: Train the FORECAST model
-- Training takes 2–5 minutes. Progress is visible in query history.
-- ON_ERROR = 'SKIP' allows training to succeed even if some country series
-- have insufficient data points.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE SNOWFLAKE.ML.FORECAST DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_MODEL (
    INPUT_DATA  => SYSTEM$REFERENCE('VIEW', 'DEVPULSEINTEL.ENRICHED.V_SALARY_TRAINING_INPUT'),
    SERIES_COLNAME     => 'SERIES',
    TIMESTAMP_COLNAME  => 'EXPERIENCE_DATE',
    TARGET_COLNAME     => 'MEDIAN_SALARY',
    CONFIG_OBJECT      => { 'ON_ERROR': 'SKIP' }
);

-- Confirm model was created
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA DEVPULSEINTEL.ENRICHED;


-- ---------------------------------------------------------------------------
-- SECTION 3: Generate and store forecast results
-- Forecasts 10 periods (experience increments) beyond each country's
-- last observed data point.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS (
    SERIES          VARCHAR,
    EXPERIENCE_DATE TIMESTAMP_NTZ,
    FORECAST        FLOAT,
    LOWER_BOUND     FLOAT,
    UPPER_BOUND     FLOAT,
    FORECAST_AT     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Cortex ML FORECAST results: predicted salary by experience increment per country.';
COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS.SERIES
  IS 'Country name';
COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS.FORECAST
  IS 'Predicted median salary (USD)';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS.LOWER_BOUND
  IS '80% prediction interval lower bound';
COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS.LOWER_BOUND
  IS '80% prediction interval lower bound';

COMMENT ON COLUMN DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS.UPPER_BOUND
  IS '80% prediction interval upper bound';

CALL DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_MODEL!FORECAST(
    FORECASTING_PERIODS => 10,
    CONFIG_OBJECT       => { 'prediction_interval': 0.8 }
);

-- Move results from temp output into the permanent table
INSERT INTO DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS (
    SERIES, EXPERIENCE_DATE, FORECAST, LOWER_BOUND, UPPER_BOUND
)
SELECT
    SERIES,
    TS          AS EXPERIENCE_DATE,
    FORECAST,
    LOWER_BOUND,
    UPPER_BOUND
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Verify
SELECT SERIES, COUNT(*) AS PERIODS, ROUND(AVG(FORECAST), 0) AS AVG_PREDICTED_SALARY
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
GROUP BY 1 ORDER BY AVG_PREDICTED_SALARY DESC
LIMIT 10;


-- ---------------------------------------------------------------------------
-- SECTION 4: Pre-aggregated salary benchmarks table
-- Used by the Streamlit "Where do I Stand?" widget for fast, free lookups.
-- Computed once from ENRICHED_RESPONSES; no Cortex calls at query time.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE DEVPULSEINTEL.ENRICHED.SALARY_BENCHMARKS
  COMMENT = 'Pre-computed salary percentiles by country, experience bucket, and role. Read by Streamlit app.'
AS
SELECT
    COUNTRY,
    EXPERIENCE_BUCKET,
    EXPERIENCE_BUCKET_SORT,
    PRIMARY_DEV_ROLE,
    COUNT(*)                                                                AS RESPONDENT_COUNT,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP
          (ORDER BY ANNUAL_COMP_USD), 0)                                    AS P25_SALARY_USD,
    ROUND(MEDIAN(ANNUAL_COMP_USD), 0)                                       AS MEDIAN_SALARY_USD,
    ROUND(AVG(ANNUAL_COMP_USD), 0)                                          AS AVG_SALARY_USD,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
          (ORDER BY ANNUAL_COMP_USD), 0)                                    AS P75_SALARY_USD,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP
          (ORDER BY ANNUAL_COMP_USD), 0)                                    AS P90_SALARY_USD
FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
WHERE ANNUAL_COMP_USD IS NOT NULL
  AND COUNTRY IS NOT NULL
  AND EXPERIENCE_BUCKET != 'Unknown'
  AND PRIMARY_DEV_ROLE IS NOT NULL
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) >= 10;

-- Verify benchmarks
SELECT COUNT(*) AS BENCHMARK_COMBINATIONS FROM DEVPULSEINTEL.ENRICHED.SALARY_BENCHMARKS;
SELECT * FROM DEVPULSEINTEL.ENRICHED.SALARY_BENCHMARKS
WHERE COUNTRY = 'UNITED STATES OF AMERICA'
ORDER BY EXPERIENCE_BUCKET_SORT LIMIT 10;


-- ---------------------------------------------------------------------------
-- SECTION 5: Actual vs forecast combined view
-- Used by the Streamlit salary trend chart.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW DEVPULSEINTEL.ENRICHED.V_SALARY_ACTUAL_VS_FORECAST
  COMMENT = 'Actual median salary (from training data) combined with forecast. Feeds Streamlit salary trend chart.'
AS
-- Actuals
SELECT
    SERIES                                                     AS COUNTRY,
    DATEDIFF('day', '2000-01-01'::DATE, EXPERIENCE_DATE::DATE) AS YEARS_EXPERIENCE,
    MEDIAN_SALARY                                              AS SALARY_USD,
    'Actual'                                                   AS DATA_TYPE
FROM DEVPULSEINTEL.ENRICHED.V_SALARY_TRAINING_INPUT

UNION ALL

-- Forecast
SELECT
    SERIES                                                     AS COUNTRY,
    DATEDIFF('day', '2000-01-01'::DATE, EXPERIENCE_DATE::DATE) AS YEARS_EXPERIENCE,
    ROUND(FORECAST, 0)                                         AS SALARY_USD,
    'Forecast'                                                 AS DATA_TYPE
FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS;

-- =============================================================================
-- END 05_cortex_ml.sql
-- Next: Run 06_cortex_search.sql to create the Cortex Search service
-- =============================================================================
