# Runs the whole pipeline (steps 03 to 08) and exports the CSVs for Tableau.
# Run it from anywhere: python export.py

import os
import time
import duckdb

# Work from the project folder so the relative paths in the SQL files work
os.chdir(os.path.dirname(os.path.abspath(__file__)))

sql_files = [
    "sql/03_clean.sql",
    "sql/04_universe.sql",
    "sql/05_enrich.sql",
    "sql/06_score.sql",
    "sql/07_briefs.sql",
    "sql/08_export.sql",
]

con = duckdb.connect("ortho.duckdb")
start = time.time()

for path in sql_files:
    step_start = time.time()
    with open(path, encoding="utf-8") as f:
        con.execute(f.read())
    print(f"{path}: {time.time() - step_start:.1f} s")

con.close()
print(f"Total: {time.time() - start:.1f} s")
