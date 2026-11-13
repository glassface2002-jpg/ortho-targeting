# Ortho Targeting — Study Guide

A notebook-ready summary of the whole project: what it is, what every file does,
the concepts behind it, and the DuckDB commands you'll use.

---

## 1. The project in one paragraph

You are pretending to work for a fictional company (e.g. "Kinetiq Orthopedics")
that sells a **robotic knee and hip replacement system**. Its sales reps need to
know **which orthopedic surgeons to visit first and what to say to them**. You
answer that using about **100 million rows of free public CMS data**: how many
knee/hip replacements each surgeon billed to Medicare (2020–2024), which
competitors pay them (Open Payments, 2021–2025), and where they practice. The
output is a **ranked list of surgeons with a 0–100 score, a tier (A/B/C), a
segment and talking points**, shown in a **four-page Tableau dashboard**, with
all the code on **GitHub**.

**The business question (README headline):**
> Which orthopedic surgeons should a robotics sales team visit first, and what should reps say?

**Resume bullet (fill in your numbers at the end):**
> Built a DuckDB pipeline processing [X]M rows of CMS Medicare and Open Payments
> data (5 years) into a physician prioritization model for medtech sales
> targeting; published a 4-view interactive Tableau dashboard with adjustable
> scoring weights.

---

## 2. The pipeline, start to finish

```
 CMS websites
      │  Phase 1: download.py (done)
      ▼
 data/raw/*.csv            57 GB, 14 CSV files, plain text, row by row
      │  Phase 2: sql/01_load.sql (done by Claude)
      ▼
 data/parquet/             5.1 GB, compressed, column by column
      │  Phase 2: sql/02_views.sql
      ▼
 ortho.duckdb views        clean names: clinicians, hospitals, ...
      │  Phase 3: you write sql/03_clean.sql
      ▼
 clean tables              ortho_procs, openpay_clean, clinician_locations, surgeon_hospitals
      │  Phase 4–5
      ▼
 one row per surgeon       target_universe → target_enriched
      │  Phase 6 (Python + SQL)
      ▼
 scored_final              priority_score 0–100, tier, segment
      │  Phase 7
      ▼
 rep_briefs                + territory, rep, talking points
      │  Phase 8: export.py
      ▼
 data/exports/*.csv        5 small CSVs
      │  Phase 9–10
      ▼
 Tableau Public dashboard + GitHub README
```

**Key idea:** every step reads only the step before it. If something looks wrong,
you go back one step, not to the beginning.

---

## 3. Phase status

| Phase | What | Status |
|---|---|---|
| 0 | Tools, folders, .gitignore, run log | ✅ done |
| 1 | Download datasets | ✅ done (data dictionaries into `docs/` still to do) |
| 2 | Convert to Parquet + views | ✅ done: 127M rows, 57 GB → 5.1 GB |
| 3 | Explore and clean | ⬜ **you start here** |
| 4 | Target universe (one row per surgeon) | ⬜ |
| 5 | Enrich: contact, hospitals, competitors | ⬜ |
| 6 | Scoring model | ⬜ |
| 7 | Rep briefs and talking points | ⬜ |
| 8 | Export for Tableau | ⬜ |
| 9 | Tableau dashboards | ⬜ |
| 10 | Publish: Tableau Public, GitHub, LinkedIn | ⬜ |

---

## 4. File and folder map

| Path | What it is | In Git? |
|---|---|---|
| `download.py` | Finds current CMS download links, streams files in 8 MB chunks, skips files that exist, logs size/time | yes |
| `config/sources.json` | Every download URL, with the dataset name and year | yes |
| `config/weights.json` | Scoring weights for Phase 6 (volume 0.35, accessibility 0.20, growth 0.20, influence 0.15, local 0.10) | yes |
| `run_log.md` | Evidence log: file sizes, row counts, run times. Becomes the "big data" section of the README | yes |
| `data/raw/` | The 14 original CSVs (57 GB) | **no** (too big) |
| `data/parquet/` | The converted Parquet files (5.1 GB) | **no** |
| `data/exports/` | Small CSVs for Tableau (Phase 8) | yes, if small |
| `data/tmp/` | DuckDB scratch space when memory fills up | no |
| `ortho.duckdb` | The database file. Holds views and your tables | **no** |
| `sql/01_load.sql` | CSV → Parquet conversion (slow, run once) | yes |
| `sql/02_views.sql` | Creates the clean table names (fast) | yes |
| `sql/03_...` onward | Your scripts, one per phase | yes |
| `notebooks/` | Jupyter notebooks for exploring | yes |
| `docs/` | Data dictionaries + this guide | yes |
| `screenshots/` | Dashboard images for the README | yes |

**Why the big files stay out of Git:** GitHub rejects files over 100 MB, and the
data is public anyway. The code + `sources.json` let anyone rebuild it.

---

## 5. The datasets

### Raw file → view name

| Raw CSV | View you query | One row = | Rows |
|---|---|---|---|
| `phys_svc_2020–2024.csv` | `medicare_provider_services` | one provider × one procedure code × one place of service × one year | 48.5M |
| `phys_prov_2024.csv` | `medicare_providers_2024` | one provider (2024 totals) | 1.3M |
| `op_gnrl_2021–2025.csv` | `open_payments_general` | one payment from a company to a doctor/hospital | 71.2M |
| `pdc_clinicians.csv` | `clinicians` | one clinician × one practice location | 3.6M |
| `pdc_facility_affil.csv` | `facility_affiliations` | one clinician × one hospital they work at | 2.3M |
| `pdc_hospital_info.csv` | `hospitals` | one hospital | 5,419 |
| | **Total** | | **127.0M rows** |

**"One row = ..." is called the grain.** Always know the grain before you
`SUM` or `JOIN`, or you'll double count.

### What each dataset tells you

- **Medicare Physician & Other Practitioners – by Provider and Service.** What
  each doctor billed Medicare for, per procedure code, per year. Your **volume**
  signal: count of knee/hip replacements per surgeon.
- **Medicare … – by Provider.** One summary row per doctor: total patients,
  total payments, patient demographics.
- **Open Payments – General Payments.** Every payment a drug or device company
  made to a doctor: consulting, speaking, food, travel. Shows **which
  competitors are courting which surgeons**, and whether it's robot-related.
- **Doctors and Clinicians National Downloadable File.** Practice address,
  phone, group name, specialty, graduation year. Your **contact info**.
- **Facility Affiliation Data.** Which hospitals each clinician works at.
- **Hospital General Information.** Hospital names, addresses, types, star ratings.

### How the datasets connect

```
                 npi                                  npi
open_payments_general ─────┐              ┌───── clinicians
                           ▼              ▼
           medicare_provider_services  (npi = the surgeon)
                           ▲
                           │ npi
                 facility_affiliations ── facility_ccn = facility_id ──► hospitals
```

- **NPI** (National Provider Identifier): a 10-digit ID every US clinician has.
  It is the join key across all the datasets. In this project it's a `BIGINT`
  (whole number) in every view, so joins work directly.
- **CCN** (CMS Certification Number): the hospital ID. `facility_affiliations.facility_ccn`
  joins to `hospitals.facility_id`. Kept as text because it has leading zeros (`090012`).

### Procedure codes you care about (HCPCS / CPT)

| Code | Procedure |
|---|---|
| 27447 | Total knee replacement |
| 27130 | Total hip replacement |
| 27446 | Partial knee replacement |

---

## 6. Column names: guide → this project

`01_load.sql` already renamed columns to lower_snake_case, so the SQL in the
build guide needs these names instead. Always confirm with `DESCRIBE <view>;`.

### `medicare_provider_services` (guide calls it `raw_phys_svc`)

| Guide uses | Use instead | Notes |
|---|---|---|
| `data_year` | `year` | already an INTEGER |
| `Rndrng_NPI` | `npi` | BIGINT |
| `Rndrng_Prvdr_Last_Org_Name` | `last_or_org_name` | |
| `Rndrng_Prvdr_First_Name` | `first_name` | |
| `Rndrng_Prvdr_Crdntls` | `credentials` | |
| `Rndrng_Prvdr_Ent_Cd` | `entity_type` | `'I'` individual, `'O'` organization |
| `Rndrng_Prvdr_City` | `city` | |
| `Rndrng_Prvdr_State_Abrvtn` | `state` | |
| `Rndrng_Prvdr_Zip5` | `zip5` | already text |
| `Rndrng_Prvdr_Type` | `provider_type` | specialty, e.g. `'Orthopedic Surgery'` |
| `HCPCS_Cd` | `hcpcs_code` | text |
| `HCPCS_Desc` | `hcpcs_desc` | |
| `Place_Of_Srvc` | `place_of_service` | `'F'` facility, `'O'` office |
| `Tot_Benes` | `total_beneficiaries` | patients; BIGINT |
| `Tot_Srvcs` | `total_services` | procedures; DOUBLE |
| `Avg_Mdcr_Pymt_Amt` | `avg_medicare_payment` | DOUBLE |

### `open_payments_general` (guide calls it `raw_openpay`)

| Guide uses | Use instead |
|---|---|
| `Covered_Recipient_NPI` | `npi` (BIGINT) |
| `Applicable_Manufacturer_or_Applicable_GPO_Making_Payment_Name` | `manufacturer_name` |
| `Total_Amount_of_Payment_USDollars` | `payment_amount` (DECIMAL) |
| `Date_of_Payment` | `payment_date` (DATE) |
| `Nature_of_Payment_or_Transfer_of_Value` | `payment_nature` |
| `Name_of_Drug_or_Biological_or_Device_or_Medical_Supply_1` | `name_of_drug_or_biological_or_device_or_medical_supply_1` |
| `Program_Year` | `program_year` (INTEGER) |

Every other Open Payments column is the original name in lowercase, stored as text.

### `clinicians` (National Downloadable File)

| Guide wants | Column |
|---|---|
| npi | `npi` |
| name | `provider_first_name`, `provider_last_name` |
| primary specialty | `primary_specialty` |
| graduation year | `graduation_year` |
| practice name | `facility_name` |
| address | `address_1`, `address_2` |
| city / state / ZIP | `city`, `state`, `zip_code` (9 digits sometimes: use `LEFT(zip_code, 5)`) |
| phone | `telephone_number` |

### `facility_affiliations` and `hospitals`

- `facility_affiliations`: `npi`, `facility_type`, `facility_ccn`, `parent_facility_ccn`
- `hospitals`: `facility_id`, `facility_name`, `city`, `state`, `zip_code`,
  `hospital_type`, `hospital_ownership`, `hospital_overall_rating` (1–5, NULL if not rated)

---

## 7. Core concepts (know these for interviews)

**CSV vs Parquet.**
- CSV is plain text, stored row by row. To sum one column, the computer still
  reads every column.
- Parquet is binary, compressed, stored **column by column**. A query that needs
  2 of 90 columns reads only those 2. Files shrink 5–10×; queries get much faster.
- Your proof: 48.5M Medicare rows went from 15 GB CSV → 1.7 GB Parquet.

**Partitioning.** `PARTITION_BY (year)` writes one folder per year
(`year=2024/`). A query with `WHERE year = 2024` skips the other folders
entirely. This is called **partition pruning**.

**DuckDB.** An analytics database that lives in one file with no server.
Built for scanning and aggregating large data on one machine ("SQLite for
analytics"). It can query CSV and Parquet files directly without loading them.

**View vs table.**
- **View:** a saved query. Stores no data; runs every time you use it. Your
  `02_views.sql` views just point at Parquet files.
- **Table:** stores the result. Use `CREATE TABLE ... AS SELECT` (CTAS) for your
  clean and summary tables, so later steps don't redo the work.

**Raw → clean → mart layers.** Raw data you never edit, clean typed tables,
then business-ready tables (`scored_final`, `rep_briefs`). Industry term:
"medallion" (bronze/silver/gold) or "staging/marts."

**Type casting.** CSVs have no types. ZIP `02134` read as a number becomes
`2134`. That's why ZIPs, codes and CCNs are stored as text, and why `TRY_CAST`
is used for messy columns (returns NULL instead of crashing).

**Percentile rank.** Turns any metric into 0–1 ("better than X% of surgeons"),
so volume (hundreds) and dollars (thousands) can be combined in one score.

**Grain.** What one row represents. Check it before every join.

---

## 8. Data limits (put these in the README)

- **Medicare fee-for-service only.** Medicare Advantage and private insurance are
  missing, so real volume is higher.
- **Small counts are suppressed.** CMS drops rows with 10 or fewer patients.
- **Time lag.** Physician data ends at 2024; Open Payments at program year 2025.
- **Place of service is coarse.** F/O can't separate hospital from surgery center.
- **A payment is not proof of product use**, and doesn't imply wrongdoing.
- **Manufacturer names vary**, so your `competitor_map` is a judgment call. Document it.
- **Use responsibly.** A planning aid, not a judgment of any doctor.

---

## 9. DuckDB command cheat sheet

### Open and leave

```
duckdb ortho.duckdb          -- open the database (run from the project folder)
.exit                        -- leave (or Ctrl+C twice)
```

Only one program can **write** to `ortho.duckdb` at a time. Close the CLI
before running a Python script that writes to it, and vice versa.

### Dot commands (CLI only, no semicolon)

| Command | Does |
|---|---|
| `.tables` | list tables and views |
| `.schema clinicians` | show how a view/table was created |
| `.timer on` | print run time after each query (use for the run log) |
| `.mode box` / `.mode line` / `.mode csv` | change output style (`line` = one column per line, good for wide rows) |
| `.maxrows 50` | show more rows |
| `.read sql/02_views.sql` | run a whole SQL file |
| `.output out.txt` / `.output` | send results to a file / back to screen |
| `.help` | all commands |

### Look at data

```sql
SHOW TABLES;
DESCRIBE clinicians;                         -- columns and types
SUMMARIZE hospitals;                         -- min/max/nulls/distinct for every column
SELECT * FROM hospitals LIMIT 5;
SELECT COUNT(*) FROM medicare_provider_services;
SELECT year, COUNT(*) FROM medicare_provider_services GROUP BY ALL ORDER BY 1;
```

### Read files directly (no view needed)

```sql
SELECT * FROM read_csv('data/raw/pdc_hospital_info.csv') LIMIT 5;
SELECT * FROM read_parquet('data/parquet/clinicians.parquet') LIMIT 5;
SELECT * FROM 'data/parquet/clinicians.parquet' LIMIT 5;     -- shortcut
DESCRIBE SELECT * FROM read_csv('data/raw/phys_prov_2024.csv');
```

Useful `read_csv` options: `all_varchar = true` (everything as text),
`normalize_names = true` (clean headers), `types = {'col': 'VARCHAR'}`,
`union_by_name = true` (combine files whose columns differ), `filename = true`
(add the source file name as a column), `sample_size = -1` (scan whole file to guess types).

### Create things

```sql
CREATE TABLE ortho_procs AS SELECT ...;            -- save a result (CTAS)
CREATE OR REPLACE TABLE ortho_procs AS SELECT ...; -- rebuild it
CREATE VIEW v AS SELECT ...;
DROP TABLE IF EXISTS ortho_procs;
ALTER TABLE t ADD COLUMN x DOUBLE;
UPDATE t SET x = ... WHERE ...;
```

### Write files

```sql
COPY (SELECT * FROM rep_briefs) TO 'data/exports/surgeons.csv' (HEADER, DELIMITER ',');
COPY (SELECT ...) TO 'out.parquet' (FORMAT parquet, COMPRESSION zstd);
COPY (SELECT ...) TO 'out_dir' (FORMAT parquet, PARTITION_BY (year));
```

### SQL patterns the guide uses

```sql
-- Filter + bucket
CASE hcpcs_code WHEN '27447' THEN 'Total knee'
                WHEN '27130' THEN 'Total hip'
                WHEN '27446' THEN 'Partial knee' END AS proc_group

-- GROUP BY ALL: group by every non-aggregated column automatically
SELECT state, year, SUM(total_services) FROM ... GROUP BY ALL;

-- Conditional sums in one pass
SUM(services) FILTER (WHERE proc_group = 'Total knee') AS knee_cases

-- Safe division (NULL instead of divide-by-zero)
(a - b) / NULLIF(b, 0)

-- Replace NULL with a default
COALESCE(robotic_total, 0)

-- Safe type conversion
TRY_CAST(x AS INTEGER)

-- One row per key (first row by an order)
SELECT DISTINCT ON (npi) * FROM t ORDER BY npi, score DESC;
-- or: SELECT * FROM t QUALIFY ROW_NUMBER() OVER (PARTITION BY npi ORDER BY score DESC) = 1;

-- CTEs: name sub-steps
WITH latest AS (SELECT ...), base AS (SELECT ...)
SELECT ... FROM latest JOIN base USING (npi);

-- Window functions (rank without collapsing rows)
PERCENT_RANK() OVER (ORDER BY joint_cases)          -- 0 to 1
NTILE(10) OVER (ORDER BY priority_score DESC)       -- deciles 1–10
MEDIAN(joint_cases) OVER (PARTITION BY state)

-- Aggregates
STRING_AGG(hospital_name, '; ')                     -- list into one text field
ARG_MAX(competitor, amount)                         -- competitor with the largest amount
COUNT(DISTINCT npi)

-- Text matching
product ILIKE '%mako%'                               -- case-insensitive
product ILIKE ANY ('%mako%', '%rosa%', '%velys%', '%cori%')
CONCAT_WS(' | ', a, b, c)                            -- join non-NULL pieces
LEFT(zip_code, 5)   LPAD(zip5, 5, '0')

-- See how a query runs / where time goes
EXPLAIN ANALYZE SELECT ...;
```

### Join checklist

```sql
-- Before joining, check the key is unique on the side that should be unique:
SELECT COUNT(*), COUNT(DISTINCT npi) FROM target_universe;   -- must match

-- After a LEFT JOIN, measure the match rate (log it):
SELECT AVG(CASE WHEN c.npi IS NOT NULL THEN 1 ELSE 0 END) AS match_rate
FROM target_universe t LEFT JOIN surgeon_contact c USING (npi);
```

### DuckDB from Python (Phase 6, 8)

```python
import duckdb, json
con = duckdb.connect("ortho.duckdb")
df = con.sql("SELECT * FROM hospitals LIMIT 10").df()   # → pandas DataFrame
con.execute("CREATE OR REPLACE TABLE x AS SELECT ...")
w = json.load(open("config/weights.json"))
con.close()                                              # release the file lock
```

---

## 10. Phase-by-phase plan (what you'll build)

**Phase 3 — Explore and clean** (`sql/03_clean.sql`, `sql/checks.sql`)
1. Specialties: `SELECT provider_type, COUNT(DISTINCT npi) FROM medicare_provider_services WHERE year = 2024 GROUP BY ALL ORDER BY 2 DESC;`
2. Who bills 27447/27130/27446, and the F/O split.
3. Build `ortho_procs` (individuals only, the 3 codes), `openpay_clean`
   (non-null NPI, key columns), `clinician_locations`, `surgeon_hospitals`
   (affiliations joined to hospitals).
4. Checks: NPIs are 10 digits, no negatives, stable yearly totals.
- ✔ Checkpoint: 5 years in `ortho_procs`; record distinct surgeon count.

**Phase 4 — Target universe**
- `surgeon_year` (cases per surgeon per year) → `target_universe` (2024 cases,
  2022 cases, 2-year growth, ≥ 20 cases) → `vs_state_median`.
- ✔ Checkpoint: `COUNT(*) = COUNT(DISTINCT npi)`; top 10 look plausible.

**Phase 5 — Enrich**
- Primary location + phone, hospital count + list, competitor payments
  (`competitor_map` CSV in `config/`, robotic flag), combine into `target_enriched`.
- ✔ Checkpoint: log match rates.

**Phase 6 — Score**
- Percentile-rank 5 signals → weighted score from `weights.json` (Python) →
  tiers A/B/C → segments (KOL, Competitive conversion, Greenfield, Rising, Maintain).
- Sensitivity test: volume weight 0.50 → overlap of top 100.
- ✔ Checkpoint: explain why #1 is #1 in one sentence.

**Phase 7 — Rep briefs**
- `config/territories.csv` (ZIP3 → territory), rule-based talking points with `CASE` + `CONCAT_WS`.
- ✔ Checkpoint: read 10 random briefs out loud.

**Phase 8 — Export** (`export.py`)
- `surgeons.csv`, `surgeon_trend.csv`, `state_year.csv`, `competitor_payments.csv`,
  `surgeon_hospitals.csv`. Cast `npi` to text for Tableau.
- ✔ Checkpoint: no duplicate NPIs in `surgeons.csv`.

**Phase 9 — Tableau**: National Market, Territory Planner, Surgeon Profile,
Competitive Landscape; weight sliders + Live Score.

**Phase 10 — Publish**: Tableau Public, README (summary, question, data + row
counts, pipeline diagram, scoring, findings, limits, how to run), resume, LinkedIn.

---

## 11. Glossary

| Term | Meaning |
|---|---|
| CMS | Centers for Medicare & Medicaid Services, the agency publishing the data |
| Medicare FFS | Fee-for-service Medicare (traditional), the part this data covers |
| NPI | 10-digit national ID for every clinician; your join key |
| HCPCS / CPT | Procedure codes (27447 = total knee) |
| CCN | Hospital certification number |
| Open Payments | Federal database of industry payments to doctors (Sunshine Act) |
| Program year (PY) | The year Open Payments payments were made |
| ASC | Ambulatory surgery center (outpatient) |
| KOL | Key opinion leader, an influential doctor |
| Grain | What one row represents |
| CTAS | `CREATE TABLE AS SELECT` |
| CTE | `WITH name AS (...)`, a named sub-query |
| Window function | Calculation across rows without collapsing them (`OVER (...)`) |
| Parquet | Compressed, columnar file format |
| Partition pruning | Skipping folders a query doesn't need |
| Percentile rank | Position from 0 to 1 relative to everyone else |
| Sensitivity test | Changing an assumption to see how much results move |

---

## 12. Interview talking points

1. **Scale:** "Processed 127M rows / 57 GB of raw CSV on a laptop with DuckDB by
   converting to partitioned Parquet (57 GB → 5.1 GB)."
2. **Data modeling:** raw → clean → mart layers; knowing the grain; NPI as the join key.
3. **Data quality:** type casting, leading zeros, suppression, match rates, checks file.
4. **Modeling judgment:** percentile-ranked weighted score, config-driven weights,
   sensitivity test results.
5. **Business translation:** tiers, segments and talking points a rep can act on.
6. **Honesty about limits:** FFS only, payments ≠ product use.
