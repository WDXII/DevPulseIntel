import streamlit as st
import pandas as pd
import altair as alt
import json
from snowflake.snowpark.context import get_active_session

# =============================================================================
# DevPulseIntel | app.py
# Deploy as Streamlit in Snowflake:
#   Database: DEVPULSEINTEL | Schema: ENRICHED | Warehouse: DEVPULSE_APP_WH
# =============================================================================

st.set_page_config(
    page_title="DevPulseIntel",
    page_icon="📡",
    layout="wide"
)

SNOWFLAKE_BLUE = "#29B5E8"
DARK_BG        = "#1a1a2e"
CARD_BG        = "#16213e"

st.markdown(f"""
<style>
    .stApp {{ background-color: {DARK_BG}; }}
    .metric-card {{
        background: {CARD_BG};
        border: 1px solid {SNOWFLAKE_BLUE};
        border-radius: 8px;
        padding: 16px;
        text-align: center;
    }}
    .metric-value {{ font-size: 2rem; font-weight: 700; color: {SNOWFLAKE_BLUE}; }}
    .metric-label {{ font-size: 0.85rem; color: #aaa; margin-top: 4px; }}
    h1, h2, h3 {{ color: {SNOWFLAKE_BLUE}; }}
</style>
""", unsafe_allow_html=True)

# ─── Session & caching ───────────────────────────────────────────────────────

session = get_active_session()

@st.cache_data(ttl=3600, show_spinner="Loading data…")
def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()

# ─── Sidebar ─────────────────────────────────────────────────────────────────

st.sidebar.image(
    "https://www.snowflake.com/wp-content/themes/snowflake/assets/img/logo-white.svg",
    width=160
)
st.sidebar.title("DevPulseIntel")
st.sidebar.caption("Developer Ecosystem Intelligence\nStack Overflow Survey 2024 · ~65K respondents")

page = st.sidebar.radio(
    "Navigate",
    ["💰 Salary Explorer", "🤖 AI Adoption", "🛠 Skill Demand", "🔍 Semantic Search"]
)

st.sidebar.markdown("---")
st.sidebar.caption("Powered by Snowflake · Dynamic Tables · Cortex LLM/ML · Cortex Search")


# =============================================================================
# PAGE 1 — Salary Explorer
# =============================================================================

if page == "💰 Salary Explorer":
    st.title("💰 Salary Explorer")
    st.caption("Salary distributions and Cortex ML predictions across countries, roles, and experience levels.")

    # ── Filters ──────────────────────────────────────────────────────────────
    countries_df = run_query("""
        SELECT DISTINCT COUNTRY
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE COUNTRY IS NOT NULL
        ORDER BY COUNTRY
    """)
    roles_df = run_query("""
        SELECT DISTINCT STANDARDIZED_ROLE
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE STANDARDIZED_ROLE IS NOT NULL
        ORDER BY STANDARDIZED_ROLE
    """)

    col1, col2 = st.columns(2)
    with col1:
        selected_country = st.selectbox(
            "Country",
            ["All"] + countries_df["COUNTRY"].tolist()
        )
    with col2:
        selected_role = st.selectbox(
            "Developer Role",
            ["All"] + roles_df["STANDARDIZED_ROLE"].tolist()
        )

    country_filter = "" if selected_country == "All" else f"AND COUNTRY = '{selected_country}'"
    role_filter    = "" if selected_role    == "All" else f"AND STANDARDIZED_ROLE = '{selected_role}'"

    # ── KPI cards ─────────────────────────────────────────────────────────────
    kpi_df = run_query(f"""
        SELECT
            COUNT(*)                                         AS TOTAL_DEVS,
            ROUND(MEDIAN(ANNUAL_COMP_USD), 0)               AS MEDIAN_SALARY,
            ROUND(AVG(ANNUAL_COMP_USD), 0)                  AS AVG_SALARY,
            ROUND(SUM(CASE WHEN USES_AI_TOOLS THEN 1.0 ELSE 0 END)
                  / NULLIF(COUNT(*), 0) * 100, 1)           AS AI_ADOPTION_PCT
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE ANNUAL_COMP_USD IS NOT NULL {country_filter} {role_filter}
    """)

    k = kpi_df.iloc[0]
    c1, c2, c3, c4 = st.columns(4)
    for col, label, value in [
        (c1, "Developers",     f"{int(k['TOTAL_DEVS']):,}"),
        (c2, "Median Salary",  f"${int(k['MEDIAN_SALARY']):,}" if k["MEDIAN_SALARY"] else "N/A"),
        (c3, "Average Salary", f"${int(k['AVG_SALARY']):,}"   if k["AVG_SALARY"]    else "N/A"),
        (c4, "Use AI Tools",   f"{k['AI_ADOPTION_PCT']}%"     if k["AI_ADOPTION_PCT"] else "N/A"),
    ]:
        col.markdown(f"""
        <div class="metric-card">
            <div class="metric-value">{value}</div>
            <div class="metric-label">{label}</div>
        </div>""", unsafe_allow_html=True)

    st.markdown("---")

    # ── Salary by experience ──────────────────────────────────────────────────
    exp_df = run_query(f"""
        SELECT
            EXPERIENCE_BUCKET,
            EXPERIENCE_BUCKET_SORT,
            ROUND(MEDIAN(ANNUAL_COMP_USD), 0) AS MEDIAN_SALARY,
            COUNT(*)                           AS DEVS
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE ANNUAL_COMP_USD IS NOT NULL
          AND EXPERIENCE_BUCKET != 'Unknown'
          {country_filter} {role_filter}
        GROUP BY 1, 2
        ORDER BY EXPERIENCE_BUCKET_SORT
    """)

    if not exp_df.empty:
        st.subheader("Median Salary by Experience")
        chart = alt.Chart(exp_df).mark_bar(color=SNOWFLAKE_BLUE).encode(
            x=alt.X("EXPERIENCE_BUCKET:N", sort=None, title="Experience"),
            y=alt.Y("MEDIAN_SALARY:Q", title="Median Salary (USD)"),
            tooltip=["EXPERIENCE_BUCKET", "MEDIAN_SALARY", "DEVS"]
        ).properties(height=320)
        st.altair_chart(chart, use_container_width=True)

    # ── Salary band distribution ──────────────────────────────────────────────
    band_df = run_query(f"""
        SELECT SALARY_BAND, SALARY_BAND_SORT, COUNT(*) AS DEVS
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE SALARY_BAND != 'Unknown' {country_filter} {role_filter}
        GROUP BY 1, 2 ORDER BY SALARY_BAND_SORT
    """)

    if not band_df.empty:
        st.subheader("Salary Band Distribution")
        chart = alt.Chart(band_df).mark_bar(color=SNOWFLAKE_BLUE).encode(
            x=alt.X("SALARY_BAND:N", sort=None, title="Salary Band"),
            y=alt.Y("DEVS:Q", title="Developers"),
            tooltip=["SALARY_BAND", "DEVS"]
        ).properties(height=280)
        st.altair_chart(chart, use_container_width=True)

    # ── Cortex ML forecast ────────────────────────────────────────────────────
    st.markdown("---")
    st.subheader("🔮 Cortex ML — Salary Forecast by Experience")
    st.caption("Trained with SNOWFLAKE.ML.FORECAST using experience years as a pseudo-time axis.")

    forecast_countries = run_query("""
        SELECT DISTINCT SERIES AS COUNTRY
        FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
        ORDER BY COUNTRY
    """)

    fc_country = st.selectbox(
        "Select country for forecast",
        forecast_countries["COUNTRY"].tolist(),
        key="fc_country"
    )

    forecast_df = run_query(f"""
        SELECT
            DATEDIFF('day', '2000-01-01'::DATE, EXPERIENCE_DATE::DATE) AS YEARS_EXP,
            ROUND(FORECAST, 0)      AS FORECAST,
            ROUND(LOWER_BOUND, 0)   AS LOWER_BOUND,
            ROUND(UPPER_BOUND, 0)   AS UPPER_BOUND
        FROM DEVPULSEINTEL.ENRICHED.SALARY_FORECAST_RESULTS
        WHERE SERIES = '{fc_country}'
        ORDER BY YEARS_EXP
    """)

    actuals_df = run_query(f"""
        SELECT
            YEARS_CODE_PRO_INT AS YEARS_EXP,
            ROUND(MEDIAN(ANNUAL_COMP_USD), 0) AS ACTUAL_SALARY
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE COUNTRY = '{fc_country}'
          AND YEARS_CODE_PRO_INT IS NOT NULL
          AND ANNUAL_COMP_USD IS NOT NULL
        GROUP BY 1 ORDER BY 1
    """)

    if not forecast_df.empty and not actuals_df.empty:
        merged = actuals_df.merge(forecast_df, on="YEARS_EXP", how="outer").sort_values("YEARS_EXP")
        actual_chart = alt.Chart(merged.dropna(subset=["ACTUAL_SALARY"])).mark_line(
            color="white", strokeWidth=2
        ).encode(
            x=alt.X("YEARS_EXP:Q", title="Years of Professional Experience"),
            y=alt.Y("ACTUAL_SALARY:Q", title="Salary (USD)"),
        )
        forecast_chart = alt.Chart(merged.dropna(subset=["FORECAST"])).mark_line(
            color=SNOWFLAKE_BLUE, strokeDash=[5, 3], strokeWidth=2
        ).encode(
            x="YEARS_EXP:Q",
            y="FORECAST:Q"
        )
        band_chart = alt.Chart(merged.dropna(subset=["LOWER_BOUND", "UPPER_BOUND"])).mark_area(
            opacity=0.2, color=SNOWFLAKE_BLUE
        ).encode(
            x="YEARS_EXP:Q",
            y="LOWER_BOUND:Q",
            y2="UPPER_BOUND:Q"
        )
        st.altair_chart(band_chart + actual_chart + forecast_chart, use_container_width=True)
        st.caption("White line = actual median salary · Blue dashed = Cortex ML forecast · Shaded = 80% prediction interval")

    # ── Where do I stand ─────────────────────────────────────────────────────
    st.markdown("---")
    st.subheader("📍 Where Do I Stand?")
    col1, col2, col3 = st.columns(3)
    with col1:
        my_country = st.selectbox("Your country", countries_df["COUNTRY"].tolist(), key="my_c")
    with col2:
        my_role = st.selectbox("Your role", roles_df["STANDARDIZED_ROLE"].tolist(), key="my_r")
    with col3:
        my_salary = st.number_input("Your annual salary (USD)", min_value=0, step=5000, value=60000)

    benchmark = run_query(f"""
        SELECT P25_SALARY_USD, MEDIAN_SALARY_USD, P75_SALARY_USD, P90_SALARY_USD, RESPONDENT_COUNT
        FROM DEVPULSEINTEL.ENRICHED.SALARY_BENCHMARKS
        WHERE COUNTRY = '{my_country}'
          AND PRIMARY_DEV_ROLE = '{my_role}'
        ORDER BY ABS(MEDIAN_SALARY_USD - {my_salary})
        LIMIT 1
    """)

    if not benchmark.empty:
        b = benchmark.iloc[0]
        percentile = (
            "below the 25th percentile" if my_salary < b["P25_SALARY_USD"] else
            "25th–50th percentile"      if my_salary < b["MEDIAN_SALARY_USD"] else
            "50th–75th percentile"      if my_salary < b["P75_SALARY_USD"] else
            "75th–90th percentile"      if my_salary < b["P90_SALARY_USD"] else
            "top 10%"
        )
        st.info(f"Your ${my_salary:,} salary puts you in the **{percentile}** for {my_role}s in {my_country}. "
                f"Median: ${int(b['MEDIAN_SALARY_USD']):,} · P75: ${int(b['P75_SALARY_USD']):,} "
                f"(n={int(b['RESPONDENT_COUNT'])} respondents)")
    else:
        st.warning("Not enough data for this country/role combination.")


# =============================================================================
# PAGE 2 — AI Adoption Dashboard
# =============================================================================

elif page == "🤖 AI Adoption":
    st.title("🤖 AI Adoption Dashboard")
    st.caption("AI tool adoption, job threat perception, and attitude distribution across developer roles.")

    # Adoption by role
    adoption_df = run_query("""
        SELECT
            STANDARDIZED_ROLE,
            COUNT(*)                                                         AS TOTAL,
            SUM(CASE WHEN USES_AI_TOOLS THEN 1 ELSE 0 END)                  AS AI_USERS,
            ROUND(SUM(CASE WHEN USES_AI_TOOLS THEN 1.0 ELSE 0 END)
                  / NULLIF(COUNT(*),0) * 100, 1)                            AS ADOPTION_PCT
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE STANDARDIZED_ROLE IS NOT NULL
        GROUP BY 1 HAVING COUNT(*) >= 20
        ORDER BY ADOPTION_PCT DESC
    """)

    if not adoption_df.empty:
        st.subheader("AI Tool Adoption by Developer Role")
        chart = alt.Chart(adoption_df).mark_bar(color=SNOWFLAKE_BLUE).encode(
            x=alt.X("ADOPTION_PCT:Q", title="Adoption Rate (%)"),
            y=alt.Y("STANDARDIZED_ROLE:N", sort="-x", title="Role"),
            tooltip=["STANDARDIZED_ROLE", "ADOPTION_PCT", "AI_USERS", "TOTAL"]
        ).properties(height=320)
        st.altair_chart(chart, use_container_width=True)

    st.markdown("---")

    col1, col2 = st.columns(2)

    # AI attitude distribution
    with col1:
        attitude_df = run_query("""
            SELECT AI_ATTITUDE_CATEGORY, COUNT(*) AS CNT
            FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
            WHERE AI_ATTITUDE_CATEGORY IS NOT NULL
            GROUP BY 1 ORDER BY 2 DESC
        """)
        if not attitude_df.empty:
            st.subheader("AI Attitude Distribution")
            colors = ["#29B5E8", "#2E86AB", "#A23B72", "#F18F01"]
            chart = alt.Chart(attitude_df).mark_arc(innerRadius=60).encode(
                theta=alt.Theta("CNT:Q"),
                color=alt.Color("AI_ATTITUDE_CATEGORY:N",
                                scale=alt.Scale(range=colors)),
                tooltip=["AI_ATTITUDE_CATEGORY", "CNT"]
            ).properties(height=280)
            st.altair_chart(chart, use_container_width=True)

    # AI threat perception
    with col2:
        threat_df = run_query("""
            SELECT AI_THREAT_JOB, COUNT(*) AS CNT
            FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
            WHERE AI_THREAT_JOB IS NOT NULL AND AI_THREAT_JOB != ''
            GROUP BY 1 ORDER BY 2 DESC
            LIMIT 6
        """)
        if not threat_df.empty:
            st.subheader("AI Job Threat Perception")
            chart = alt.Chart(threat_df).mark_bar(color="#A23B72").encode(
                x=alt.X("CNT:Q", title="Respondents"),
                y=alt.Y("AI_THREAT_JOB:N", sort="-x", title=""),
                tooltip=["AI_THREAT_JOB", "CNT"]
            ).properties(height=280)
            st.altair_chart(chart, use_container_width=True)

    # Sentiment by role
    st.markdown("---")
    st.subheader("Job Satisfaction Sentiment by Role (Cortex SENTIMENT)")
    sentiment_df = run_query("""
        SELECT
            STANDARDIZED_ROLE,
            ROUND(AVG(JOB_SAT_SENTIMENT_SCORE), 3) AS AVG_SENTIMENT,
            COUNT(*)                                AS CNT
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE JOB_SAT_SENTIMENT_SCORE IS NOT NULL
          AND STANDARDIZED_ROLE IS NOT NULL
        GROUP BY 1 HAVING COUNT(*) >= 20
        ORDER BY AVG_SENTIMENT DESC
    """)
    if not sentiment_df.empty:
        chart = alt.Chart(sentiment_df).mark_bar().encode(
            x=alt.X("STANDARDIZED_ROLE:N", sort="-y", title="Role"),
            y=alt.Y("AVG_SENTIMENT:Q", title="Avg Sentiment Score (-1 to 1)"),
            color=alt.condition(
                alt.datum.AVG_SENTIMENT > 0,
                alt.value(SNOWFLAKE_BLUE), alt.value("#e74c3c")
            ),
            tooltip=["STANDARDIZED_ROLE", "AVG_SENTIMENT", "CNT"]
        ).properties(height=300)
        st.altair_chart(chart, use_container_width=True)


# =============================================================================
# PAGE 3 — Skill Demand Analyzer
# =============================================================================

elif page == "🛠 Skill Demand":
    st.title("🛠 Skill Demand Analyzer")
    st.caption("Skill clusters, language adoption, and salary by tech stack — enriched by Cortex COMPLETE.")

    col1, col2 = st.columns([1, 2])

    # Skill cluster salary distribution
    with col1:
        cluster_df = run_query("""
            SELECT
                SKILL_CLUSTER,
                ROUND(MEDIAN(ANNUAL_COMP_USD), 0) AS MEDIAN_SALARY,
                COUNT(*)                           AS DEVS
            FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
            WHERE SKILL_CLUSTER IS NOT NULL AND ANNUAL_COMP_USD IS NOT NULL
            GROUP BY 1 ORDER BY MEDIAN_SALARY DESC
        """)
        if not cluster_df.empty:
            st.subheader("Median Salary by Skill Cluster")
            chart = alt.Chart(cluster_df).mark_bar(color=SNOWFLAKE_BLUE).encode(
                x=alt.X("MEDIAN_SALARY:Q", title="Median Salary (USD)"),
                y=alt.Y("SKILL_CLUSTER:N", sort="-x", title=""),
                tooltip=["SKILL_CLUSTER", "MEDIAN_SALARY", "DEVS"]
            ).properties(height=320)
            st.altair_chart(chart, use_container_width=True)

    # Top languages globally
    with col2:
        country_opts = run_query("""
            SELECT DISTINCT COUNTRY FROM DEVPULSEINTEL.ANALYTICS.V_LANGUAGE_DEMAND
            ORDER BY COUNTRY
        """)
        sel_country = st.selectbox(
            "Filter by country",
            ["Global"] + country_opts["COUNTRY"].tolist(),
            key="lang_country"
        )

        lang_filter = "" if sel_country == "Global" else f"WHERE COUNTRY = '{sel_country}'"
        agg_col     = "LANGUAGE" if sel_country == "Global" else "LANGUAGE, COUNTRY"

        lang_df = run_query(f"""
            SELECT LANGUAGE, SUM(USAGE_COUNT) AS USAGE_COUNT
            FROM DEVPULSEINTEL.ANALYTICS.V_LANGUAGE_DEMAND
            {lang_filter}
            GROUP BY LANGUAGE
            ORDER BY USAGE_COUNT DESC
            LIMIT 20
        """)

        if not lang_df.empty:
            st.subheader(f"Top Languages — {sel_country}")
            chart = alt.Chart(lang_df).mark_bar(color=SNOWFLAKE_BLUE).encode(
                x=alt.X("LANGUAGE:N", sort="-y", title="Language"),
                y=alt.Y("USAGE_COUNT:Q", title="Developers"),
                tooltip=["LANGUAGE", "USAGE_COUNT"]
            ).properties(height=320)
            st.altair_chart(chart, use_container_width=True)

    # Skill cluster composition
    st.markdown("---")
    st.subheader("Skill Cluster Size")
    size_df = run_query("""
        SELECT SKILL_CLUSTER, COUNT(*) AS DEVS
        FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
        WHERE SKILL_CLUSTER IS NOT NULL
        GROUP BY 1 ORDER BY DEVS DESC
    """)
    if not size_df.empty:
        chart = alt.Chart(size_df).mark_arc(innerRadius=50).encode(
            theta=alt.Theta("DEVS:Q"),
            color=alt.Color("SKILL_CLUSTER:N"),
            tooltip=["SKILL_CLUSTER", "DEVS"]
        ).properties(height=300)
        st.altair_chart(chart, use_container_width=True)


# =============================================================================
# PAGE 4 — Semantic Search
# =============================================================================

elif page == "🔍 Semantic Search":
    st.title("🔍 Semantic Search")
    st.caption("Search developer profiles by meaning using Cortex Search — not keyword matching.")

    # Filters
    col1, col2, col3 = st.columns(3)
    with col1:
        filter_country = st.selectbox("Country filter", ["Any"] + run_query("""
            SELECT DISTINCT COUNTRY FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
            WHERE COUNTRY IS NOT NULL ORDER BY COUNTRY
        """)["COUNTRY"].tolist(), key="s_country")
    with col2:
        filter_cluster = st.selectbox("Skill cluster filter", ["Any"] + run_query("""
            SELECT DISTINCT SKILL_CLUSTER FROM DEVPULSEINTEL.ENRICHED.ENRICHED_RESPONSES
            WHERE SKILL_CLUSTER IS NOT NULL ORDER BY SKILL_CLUSTER
        """)["SKILL_CLUSTER"].tolist(), key="s_cluster")
    with col3:
        filter_ai = st.selectbox("AI tool usage", ["Any", "Uses AI tools", "Does not use AI tools"], key="s_ai")

    query_text = st.text_input(
        "Search query",
        placeholder="e.g. Python developer with cloud and data engineering experience",
        key="search_q"
    )

    if st.button("Search", type="primary") and query_text:
        # Build filter JSON
        filters = []
        if filter_country != "Any":
            filters.append({"@eq": {"COUNTRY": filter_country}})
        if filter_cluster != "Any":
            filters.append({"@eq": {"SKILL_CLUSTER": filter_cluster}})
        if filter_ai == "Uses AI tools":
            filters.append({"@eq": {"USES_AI_TOOLS": True}})
        elif filter_ai == "Does not use AI tools":
            filters.append({"@eq": {"USES_AI_TOOLS": False}})

        filter_json = ""
        if len(filters) == 1:
            filter_json = f', "filter": {json.dumps(filters[0])}'
        elif len(filters) > 1:
            filter_json = f', "filter": {json.dumps({"@and": filters})}'

        search_payload = f'''{{
            "query": "{query_text}",
            "columns": [
                "RESPONSE_ID", "STANDARDIZED_ROLE", "SKILL_CLUSTER",
                "COUNTRY", "EXPERIENCE_BUCKET", "SALARY_BAND",
                "JOB_SAT_SENTIMENT_LABEL", "AI_ATTITUDE_CATEGORY"
            ],
            "limit": 10
            {filter_json}
        }}'''

        try:
            result_df = run_query(f"""
                SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                    'DEVPULSEINTEL.ENRICHED.DEVPULSE_SEARCH',
                    '{search_payload.replace("'", "''")}'
                ) AS SEARCH_RESULTS
            """)

            raw = result_df["SEARCH_RESULTS"].iloc[0]
            results = json.loads(raw).get("results", [])

            if results:
                st.success(f"{len(results)} results found")
                for i, r in enumerate(results, 1):
                    with st.expander(
                        f"#{i} · {r.get('STANDARDIZED_ROLE','Unknown role')} · "
                        f"{r.get('SKILL_CLUSTER','?')} · {r.get('COUNTRY','?')}"
                    ):
                        col_a, col_b = st.columns(2)
                        col_a.metric("Experience",   r.get("EXPERIENCE_BUCKET", "—"))
                        col_a.metric("Salary Band",  r.get("SALARY_BAND", "—"))
                        col_b.metric("Job Sentiment", r.get("JOB_SAT_SENTIMENT_LABEL", "—"))
                        col_b.metric("AI Attitude",   r.get("AI_ATTITUDE_CATEGORY", "—"))
            else:
                st.warning("No results. Try a broader query or remove filters.")
                st.caption("If this persists, run the search service status check in 06_cortex_search.sql Section 3.")

        except Exception as ex:
            st.error(f"Search error: {ex}")
            st.caption("Ensure DEVPULSE_SEARCH is ACTIVE: `SHOW CORTEX SEARCH SERVICES IN SCHEMA DEVPULSEINTEL.ENRICHED;`")
