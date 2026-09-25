"""JobSat value distribution and estimated sentiment coverage.

Usage (from the repo root or anywhere):
    python profiling/check_jobsat.py
    python profiling/check_jobsat.py path/to/survey_results_public.csv

Default CSV location: <repo>/data/survey_results_public.csv
"""
import sys
from pathlib import Path

import pandas as pd

DEFAULT_CSV = Path(__file__).resolve().parent.parent / "data" / "survey_results_public.csv"
csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
if not csv_path.exists():
    sys.exit(f"CSV not found: {csv_path}\nPass the path as an argument or place the file in data/.")

df = pd.read_csv(
    csv_path,
    usecols=["ResponseId", "MainBranch", "DevType", "JobSat"],
    low_memory=False,
)

print("=== 1. Full JobSat breakdown (all respondents) ===")
print(f"Total rows: {len(df):,}")
print(df["JobSat"].value_counts(dropna=False).sort_index().to_string())

# Same filter as DT_ANALYTICS_DEVELOPERS in sql/03_dynamic_tables.sql
pro = df[
    df["ResponseId"].notna()
    & df["DevType"].notna()
    & ~df["DevType"].str.lower().str.contains("student", na=False)
    & df["MainBranch"].str.lower().str.contains("developer", na=False)
]

has_jobsat = pro["JobSat"].notna().sum()
pct = has_jobsat / len(pro) * 100

print("\n=== 2. Professional developers (ANALYTICS layer equivalent) ===")
print(f"Rows:                 {len(pro):,}")
print(f"With a JobSat value:  {has_jobsat:,}")
print(f"Est. PCT_SENTIMENT:   {pct:.1f}%   (BRD threshold: 60%)")
print(f"Est. 10% sample size: ~{len(pro) // 10:,} rows")
