"""File integrity check and candidate row-count definitions.

Usage (from the repo root or anywhere):
    python profiling/check_rowcount.py
    python profiling/check_rowcount.py path/to/survey_results_public.csv

Default CSV location: <repo>/data/survey_results_public.csv
"""
import csv
import sys
from pathlib import Path

import pandas as pd

DEFAULT_CSV = Path(__file__).resolve().parent.parent / "data" / "survey_results_public.csv"
csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
if not csv_path.exists():
    sys.exit(f"CSV not found: {csv_path}\nPass the path as an argument or place the file in data/.")

# --- 1. File integrity: would Snowflake's COPY INTO have skipped rows? ---
with open(csv_path, encoding="utf-8", newline="") as f:
    reader = csv.reader(f)
    header = next(reader)
    field_counts = {}
    records = 0
    for row in reader:
        records += 1
        field_counts[len(row)] = field_counts.get(len(row), 0) + 1

with open(csv_path, encoding="utf-8") as f:
    physical_lines = sum(1 for _ in f) - 1

print("=== 1. File integrity ===")
print(f"Header columns:        {len(header)}  (RAW table expects 114)")
print(f"CSV records:           {records:,}")
print(f"Physical lines:        {physical_lines:,}  (more than records = embedded newlines)")
print(f"Fields per record:     {field_counts}  (anything other than 114 = COPY INTO error risk)")

# --- 2. Candidate definitions of "~23K" ---
df = pd.read_csv(csv_path, usecols=["ResponseId", "MainBranch", "DevType",
                                    "ConvertedCompYearly"], low_memory=False)

mb = df["MainBranch"].str.lower()
dt = df["DevType"].str.lower()
sal = df["ConvertedCompYearly"]
sal_ok = sal.notna() & (sal >= 100) & (sal <= 2_000_000)   # CLEAN layer rule

analytics = (df["ResponseId"].notna() & dt.notna()
             & ~dt.str.contains("student", na=False)
             & mb.str.contains("developer", na=False))      # exact ANALYTICS filter
strict_pro = analytics & (df["MainBranch"] == "I am a developer by profession")

print("\n=== 2. Which definition is ~23K? ===")
print(f"A. ANALYTICS filter (as coded):                {analytics.sum():,}")
print(f"B. A + valid salary (= app 'Developers' KPI):  {(analytics & sal_ok).sum():,}")
print(f"C. Strict 'developer by profession' only:      {strict_pro.sum():,}")
print(f"D. C + valid salary:                           {(strict_pro & sal_ok).sum():,}")
print(f"E. Any respondent with a valid salary:         {sal_ok.sum():,}")

print("\n=== 3. MainBranch values ===")
print(df["MainBranch"].value_counts(dropna=False).to_string())
