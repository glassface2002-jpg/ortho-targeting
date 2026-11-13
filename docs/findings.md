# Findings Log

A running record of what we did, what we found, what we decided and what we
got wrong, in order from the start. Newest work goes at the bottom of each
section; the status snapshot at the top is always current.

Companion files: `docs/study_guide.md` (concepts and commands),
`run_log.md` (sizes, row counts, run times).

---

## Status snapshot (updated 2026-11-12)

| Phase | Status |
|---|---|
| 0 Setup | done |
| 1 Download | done (data dictionaries into `docs/` still to do) |
| 2 Load to Parquet + views | done: 127.0M rows, 57 GB → 5.1 GB |
| 3 Explore, clean, checks | done: `sql/03_clean.sql`, `sql/qchecks.sql` |
| 4 Target universe | done: 5,563 surgeons |
| 5 Enrich | done: 92–98% match rates |
| 6 Score | done: tiers A/B/C, 5 segments, sensitivity 96/100 |
| 7 Rep briefs | done: 14 territories (Arizona split by ZIP) |
| 8 Export | done: 5 CSVs in `data/exports/`, `python export.py` reruns 03–08 in 36 s |
| 9 Tableau | **next** |
| 10 Publish | not started |

---

## Decisions log

| # | Decision | Why | Phase |
|---|---|---|---|
| 1 | Keep my cleaned-up load (renamed columns, typed) instead of the guide's all-text raw load | Chosen by you. Trade-off: the guide's SQL uses the original CMS names, so use the mapping in `study_guide.md` section 6 | 2 |
| 2 | Only the general-payments CSV from each Open Payments zip | Research and ownership payments don't answer the question | 1 |
| 3 | `ortho_procs` uses all five years, with `year` as a column | Phase 4 needs 2022 vs 2024 growth; Tableau needs the trend | 3b |
| 4 | `entity_type = 'I'` (individuals only) | Removes ambulatory surgical centers and other organizations | 3b |
| 5 | Include Orthopedic Surgery, Sports Medicine, General Surgery | Volume matches surgeons, and every one holds an M.D. or D.O. | 3b |
| 6 | Exclude Physician Assistants and Nurse Practitioners | They assist in surgery and bill the same codes. Judgment from how surgical teams work, not proven by this data | 3b |
| 7 | `ortho_procs` has no grouping or summing | Clean first, summarize later (Phase 4) | 3b |
| 8 | `openpay_clean` drops rows with no NPI (232,208 of 71.2M) | Can't join them to a surgeon. 77% are teaching hospitals, which never have an NPI | 3c |
| 9 | Keep all five product columns in `openpay_clean`, not just product 1 | Product 1 alone misses about 8% of robotic-product payments | 3c |
| 10 | `clinician_locations` keeps every row (no dedupe) | 68% of our surgeons have several locations; Phase 5 picks the primary one | 3c |
| 11 | `surgeon_hospitals` keeps hospital affiliations only | Other types (home health, nursing home, etc.) are referral links, have no names in our data, and would inflate `n_hospitals` | 3c |
| 12 | Universe = 2024 surgeons with 20+ joint cases | Every 2024 surgeon already has 10+ (CMS hides smaller counts), so 20 is the first cutoff that filters | 4 |
| 13 | State median computed with a window function | Simpler than the guide's `ALTER` + `UPDATE` | 4 |
| 14 | Primary location = same ZIP as Medicare, then one with a phone | Gives the rep the location that matches where the surgeon bills | 5 |
| 15 | Robot products matched by exact name (MAKO, MAKOPLASTY, ROSA, ROSA-KNEE, ROSA PKA, ROSA-HIP, VELYS, CORI), all 5 product columns | Avoids INTRAROSA, Torosa, CORIN implants and ROSA/MAKO spine/brain robots | 5 |
| 16 | Competitors: Stryker, Zimmer Biomet, DePuy Synthes, Smith+Nephew; everyone else "Other" (`config/competitor_map.csv`) | Each reports under its own legal names; DePuy has 5 | 5 |
| 17 | Influence = consulting, speaker/faculty and honoraria dollars; royalties left out | Royalties pay for a design, not for influencing peers | 5 |
| 18 | Weights read straight from `config/weights.json` in SQL | No Python needed for scoring | 6 |
| 19 | "Competitive conversion" needs $1,000+ in robot payments, not any amount | 60% of surgeons got some robot money, but the median was $456, mostly meals | 6 |
| 20 | Arizona split into Phoenix Metro, Tucson and Southern Arizona, Northern Arizona (by ZIP3); other states by Census region | Arizona is the home region; Census regions keep the rest simple | 7 |
| 21 | Multi-site talking point = 5+ hospitals | The CMS file lists at most 5 hospitals for our surgeons, and 56% have 3+ | 7 |
| 22 | Every brief starts with the surgeon's 2024 case count | Otherwise some C-tier briefs were empty | 7 |

---

## Corrections log (things we got wrong, and the fix)

| What | Fix |
|---|---|
| I said Sports Medicine probably isn't surgical | Wrong. 163 providers with a median of 32 cases, all M.D./D.O. |
| I said PAs/NPs would show low volume | Wrong. Their median (42, 44) is almost the same as orthopedic surgeons (48). Volume can't separate assistants from surgeons |
| A first check "proved" Sports Medicine and General Surgery operate from volume alone | Volume doesn't prove that. The credentials check is the real evidence |
| First load crashed on hospital star ratings ("Not Available") | `TRY_CAST(NULLIF(rating, 'Not Available') AS INTEGER)` in `01_load.sql` |
| `ortho.duckdb` locked by an open DuckDB window | Only one program can write to the file at a time. Close the CLI first |
| I first read "0.9% office" in your notes | It's 99.4% facility / 0.6% office |
| Guide's Phase 5 uses `product ILIKE ANY ('%mako%', ...)` | DuckDB gives a syntax error on `ILIKE ANY`. Use `regexp_matches(product, 'mako\|rosa\|velys\|cori', 'i')` instead (tested) |
| Guide's `%rosa%` wildcard looks fine | It also matches the drug INTRAROSA and others (see Phase 3c). Needs a tighter match |

---

## Phase 0: setup (2026-11-05)

- Project folder `ortho-targeting/` with `data/raw`, `data/parquet`, `data/exports`, `sql`, `notebooks`, `config`, `docs`, `screenshots`.
- `.gitignore` excludes `data/raw/`, `data/parquet/`, `*.duckdb`, `data/tmp`.
- `config/weights.json` holds the scoring weights: volume 0.35, accessibility 0.20, growth 0.20, influence 0.15, local 0.10.

## Phase 1: download (2026-11-05)

- `download.py` reads the CMS catalogs, saves 14 URLs to `config/sources.json`, and streams each file in 8 MB chunks. It skips files that exist and logs size and time to `run_log.md`.
- 14 files in `data/raw/`, about 57 GB:
  - Medicare by Provider and Service, 2020–2024: 3.0–3.3 GB each
  - Medicare by Provider, 2024: 509 MB
  - Open Payments general payments, PY2021–2025: 6.5–9.2 GB each
  - Provider Data: clinicians 900 MB, facility affiliations 134 MB, hospitals 1.5 MB
- **Finding:** CMS's Provider Data Catalog returns HTTP 403 to scripts. Those three files were downloaded by hand in a browser. The log marks them as manual.
- **Finding:** Open Payments catalog lists a CSV per year, but the full program-year zips sit next to them. The script uses the zips and unzips only the general payments file.
- Nobody plans to re-download, so the script is evidence of reproducibility, not something to rerun.

## Phase 2: load (2026-11-05)

Converted every CSV to Parquet with DuckDB, then created views with clean names.

| View | Rows | CSV → Parquet | Time |
|---|---|---|---|
| `medicare_provider_services` (2020–2024) | 48,533,285 | 15.5 GB → 1.7 GB | 3 min |
| `medicare_providers_2024` | 1,296,739 | 509 MB → 135 MB | 10 s |
| `open_payments_general` (PY2021–2025) | 71,245,399 | 40.3 GB → 3.2 GB | 62 min |
| `clinicians` | 3,630,233 | 900 MB → 165 MB | 7 s |
| `facility_affiliations` | 2,276,877 | 134 MB → 25 MB | 1 s |
| `hospitals` | 5,419 | 1.5 MB → 0.2 MB | <1 s |
| **Total** | **126,987,952** | **57 GB → 5.1 GB** | **~66 min** |

- Medicare rows per year: 2020 9.45M, 2021 9.89M, 2022 9.76M, 2023 9.66M, 2024 9.78M.
- Open Payments rows per program year: 2021 11.56M, 2022 13.32M, 2023 14.73M, 2024 15.50M, 2025 16.13M.
- Split into two scripts: `01_load.sql` (slow, CSV → Parquet) and `02_views.sql` (a second, creates the names).
- The database file is tiny (about 270 KB) because the views only point at the Parquet files.
- **Checks passed:** every NPI is 10 digits; ZIPs keep leading zeros (`02062`).

**Early observations to follow up (not yet investigated):**
- Total knee replacements (27447) rose every year: 378K (2020) → 534K (2024). Part of that is probably the 2020 COVID dip. Check before using it as a headline.
- Open Payments has a payment dated in the year 0002 (a CMS data-entry error).
- About 232,000 Open Payments rows have no NPI. Find out what kind of recipient they are.

## Phase 3a: explore (2026-11-05)

2024 Medicare data, codes 27447 (total knee), 27130 (total hip), 27446 (partial knee).

| Finding | Detail |
|---|---|
| Orthopedic Surgery dominates | 6,492 surgeons billed 294,263 knees |
| PAs bill a lot | 4,178 billed 162,710 knees |
| NPs | 564 billed 22,724 knees |
| Ambulatory Surgical Centers | Show up as a "provider type" (711). They're organizations |
| Place of service | 99.4% facility (F), 0.6% office (O). Can't separate hospital from outpatient surgery center |
| Noise | Pediatrics, OB/GYN, Radiology billed a few knees or hips: likely registration errors |
| Partial knee is small | About 5K for orthopedic surgeons vs 294K total knees |

## Phase 3b: `ortho_procs` (2026-11-09)

**Specialty check (2024, per-provider yearly joint cases):**

| | NPIs | Median cases | Max | 20+ cases |
|---|---|---|---|---|
| General Surgery | 13 | 52 | 227 | 11 |
| Sports Medicine | 124 | 32 | 230 | 91 |
| Orthopedic Surgery | 6,817 | 48 | 810 | 5,461 |
| Physician Assistant | 4,371 | 42 | 513 | 3,344 |
| Nurse Practitioner | 604 | 44 | 1,037 | 463 |

**Credentials check (all years, Sports Medicine + General Surgery):** everyone is
an M.D. or D.O. (Sports Medicine 162, General Surgery 28), with 2 missing in
each. No PAs or NPs under those specialties.

**Final table:**

```sql
CREATE OR REPLACE TABLE ortho_procs AS
SELECT
  year,
  npi,
  last_or_org_name        AS last_name,
  first_name,
  credentials,
  provider_type           AS specialty,
  city,
  state,
  zip5,
  hcpcs_code              AS hcpcs,
  CASE hcpcs_code WHEN '27447' THEN 'Total knee'
                  WHEN '27130' THEN 'Total hip'
                  WHEN '27446' THEN 'Partial knee' END AS proc_group,
  place_of_service        AS pos,
  total_beneficiaries     AS patients,
  total_services          AS services,
  avg_medicare_payment    AS avg_payment
FROM medicare_provider_services
WHERE entity_type = 'I'
  AND hcpcs_code IN ('27447', '27130', '27446')
  AND provider_type IN ('Orthopedic Surgery', 'Sports Medicine', 'General Surgery');
```

**Result (all five years):**

| specialty | rows | distinct NPIs |
|---|---|---|
| Orthopedic Surgery | 55,502 | 9,036 |
| Sports Medicine | 683 | 163 |
| General Surgery | 140 | 30 |
| **Total** | **56,325** | **about 9,200** |

All-years NPI counts are higher than 2024-only counts (163 vs 124) because they
include providers who stopped billing before 2024.

**Notes:**
- Credentials are spelled inconsistently (`M.D.`, `MD`, `M.D`). Clean with `REPLACE(UPPER(credentials), '.', '')` if you filter on them.
- One Sports Medicine provider has two credential spellings across years, which is why the credential counts add to 164 instead of 163.
- Four providers (2 + 2) have no credentials; kept, since 4 of about 9,200 doesn't matter.
- Some double counting remains where orthopedic surgeons assist each other.

## Phase 3c: Open Payments profile and `openpay_clean` (2026-11-09)

**Who has no NPI (answers the open question from Phase 2):** 232,208 rows.

| Recipient type | No NPI | Has NPI |
|---|---|---|
| Teaching Hospital | 180,110 | 0 |
| Physician | 26,842 | 46,736,955 |
| Non-Physician Practitioner | 25,256 | 24,276,236 |

Teaching hospitals are organizations and never have an NPI, so dropping null-NPI rows is correct. About 52K rows are people with a missing NPI; they can't be matched, so they're dropped too.

**Non-physician practitioners** (PAs, NPs, etc.) are 24.3M rows. They stay in the table and fall out later when you join to `ortho_procs` by NPI.

**Payment types (rows with an NPI).** Row counts and dollars tell different stories:

| Nature | Rows | Total $ |
|---|---|---|
| Food and Beverage | 65.1M | $1.8B |
| Travel and Lodging | 2.5M | $0.8B |
| Other compensation (faculty/speaker outside CE) | 1.16M | $2.7B |
| Consulting Fee | 0.90M | $2.6B |
| Royalty or License | 71K | $2.7B |
| Education | 0.82M | $0.3B |

Food and beverage is 92% of rows but is small money, so counting rows would hide the real relationships. Phase 5's "influence" signal should use dollars from consulting, speaking and faculty payments, as the guide does. Royalty or License is large dollars on few rows; decide in Phase 5 whether it belongs in "influence".

**Product columns:** each payment can list up to 5 products. 92.2% of rows have product 1.

**Robotic-product matches (names containing mako, rosa, velys or cori):**
- Product 1 only: 165,394 payments
- Any of products 1–5: 180,262 payments (8% more)
- Top product 1 values: MAKO 125,118, ROSA 14,149, Velys 10,765, **INTRAROSA 8,371**, ROSA-Knee 4,013, CORI 1,909, MAKOPLASTY 512, **Torosa 154**

`%rosa%` also matches INTRAROSA (a drug) and Torosa. ROSA is also, I believe, used for Zimmer's brain/spine robots, so it may not always mean knee. To tighten it in Phase 5: match exact product names (MAKO, ROSA, ROSA-Knee, Velys, CORI) and check `product_category_or_therapeutic_area_1` for those rows.

**Data quality:** no negative or missing amounts. 75 payments are dated before 2015 (including year 0002). Use `program_year`, not `payment_date`, when filtering by year.

**Draft table (71,013,191 rows, 1,571,253 distinct NPIs, `record_id` unique):**

```sql
CREATE OR REPLACE TABLE openpay_clean AS
SELECT
  record_id,
  program_year,
  npi,
  covered_recipient_type,
  manufacturer_name,
  payment_amount  AS amount,
  payment_date,
  payment_nature  AS nature,
  payment_form    AS form,
  name_of_drug_or_biological_or_device_or_medical_supply_1 AS product_1,
  name_of_drug_or_biological_or_device_or_medical_supply_2 AS product_2,
  name_of_drug_or_biological_or_device_or_medical_supply_3 AS product_3,
  name_of_drug_or_biological_or_device_or_medical_supply_4 AS product_4,
  name_of_drug_or_biological_or_device_or_medical_supply_5 AS product_5
FROM open_payments_general
WHERE npi IS NOT NULL;
```

Names that `01_load.sql` already shortened: `npi`, `manufacturer_name`, `payment_amount`, `payment_date`, `payment_nature`, `payment_form`, `payment_count`, `program_year`. Only the product columns still had long names.

### `clinician_locations` (2026-11-09)

Source view: `clinicians` (National Downloadable File). Grain: one row per clinician per practice location. All rows kept; the primary location is chosen in Phase 5.

```sql
CREATE OR REPLACE TABLE clinician_locations AS
SELECT npi,
  provider_first_name  AS first_name,
  provider_last_name   AS last_name,
  primary_specialty    AS specialty,
  graduation_year      AS grad_year,
  facility_name        AS practice_name,
  address_1            AS address,
  address_2,
  city,
  state,
  LEFT(zip_code, 5)    AS zip5,
  telephone_number     AS phone
FROM clinicians;
```

Tested result: 3,630,233 rows, 1,637,594 distinct NPIs.

| Finding | Detail |
|---|---|
| Locations per clinician | 1: 822K · 2: 429K · 3: 161K · 4: 85K · 5 or more: 140K |
| Among our surgeons | 68% have more than one location; the most is 50 |
| ZIPs | All 3.63M are 5 digits after `LEFT(zip_code, 5)` |
| Missing values | Practice name 357K (10%), phone 646K (18%), graduation year 2.8K |
| Match to `ortho_procs` surgeons | **8,030 of 9,194 (87.3%)** found in the clinician file |

About 1,164 surgeons who billed Medicare joint codes don't appear in the National Downloadable File. Possible reasons (not yet checked): retired, no longer enrolled, or not listed. They'll have no phone or practice name in the briefs; record the final match rate in `run_log.md` in Phase 5.

### `surgeon_hospitals` (2026-11-09)

Source: `facility_affiliations` joined to `hospitals` on `facility_ccn = facility_id`.

**Decision: hospitals only** (`facility_type = 'Hospital'`).

Affiliation types for our surgeons:

| Facility type | Rows | Surgeons |
|---|---|---|
| Hospital | 23,215 | 7,878 |
| Home health agency | 11,247 | 5,313 |
| Inpatient rehabilitation facility | 973 | 884 |
| Nursing home | 254 | 234 |
| Long-term care hospital | 170 | 170 |
| Hospice | 1 | 1 |
| Dialysis facility | 0 | 0 |

Why only hospitals:
- A robot is bought by a hospital or surgery center. Home health, hospice and nursing-home affiliations mostly mean a surgeon signs orders for patients after surgery, which is a referral link, not where they operate.
- Counting them would inflate `n_hospitals` and make the Phase 7 "operates at 3+ hospitals" talking point wrong.
- `hospitals` has names only for hospitals. Every home health, hospice, nursing home and dialysis row matches nothing (0 names).
- Inpatient rehabilitation is arguably relevant (joint replacement patients rehab there) but has no names and only 884 surgeons. Skipped for now. If wanted later, add it as a separate count column, not mixed into this table.

```sql
CREATE OR REPLACE TABLE surgeon_hospitals AS
SELECT DISTINCT
  a.npi,
  a.facility_ccn,
  h.facility_name  AS hospital_name,
  h.city,
  h.state,
  h.hospital_type,
  h.hospital_overall_rating
FROM facility_affiliations a
LEFT JOIN hospitals h ON a.facility_ccn = h.facility_id
WHERE a.facility_type = 'Hospital';
```

Tested result: 1,933,611 rows, 934,288 distinct NPIs (`DISTINCT` removed 44 duplicate rows from the source's 1,933,654). `LEFT JOIN` keeps hospital affiliations that aren't in the hospital file.

| Finding | Detail |
|---|---|
| Surgeons with at least one hospital | **7,878 of 9,194 (85.7%)** |
| Unnamed hospital rows for our surgeons | 60 of 23,215 (0.3%) |
| Hospitals per surgeon | 1: 1,585 · 2: 1,844 · 3: 1,625 · 4 or more: 2,824 |

**Watch out in Phase 7:** 56% of our surgeons (4,449 of 7,878) are at 3 or more hospitals, so the guide's "3+ hospitals" talking point wouldn't stand out. Consider raising the threshold (for example 5) after looking at the distribution.

**Phase 3c is done** (all three tables designed and tested).

## Phase 3d: quality checks (2026-11-09)

Tested on in-memory copies of the four clean tables. **All four checks pass.**

| Check | Result |
|---|---|
| NPI is not null and exactly 10 digits (all four tables) | 0 bad rows in each |
| No negative `services`, `patients`, `avg_payment`, or Open Payments `amount` | 0 negatives; 0 nulls in the three Medicare numeric columns |
| One name and one specialty per surgeon per year (`ortho_procs`) | 0 conflicts |
| Yearly totals stable | See below |

**Surgeon-only yearly totals (`ortho_procs`):**

| Year | Rows | Surgeons | Services | Change |
|---|---|---|---|---|
| 2020 | 10,599 | 6,656 | 366,874 | |
| 2021 | 11,177 | 6,867 | 407,830 | +11.2% |
| 2022 | 11,485 | 7,046 | 449,730 | +10.3% |
| 2023 | 11,593 | 7,082 | 470,876 | +4.7% |
| 2024 | 11,471 | 6,954 | 470,302 | -0.1% |

**Open Payments by program year (`openpay_clean`):**

| PY | Rows | Total $ | Row change |
|---|---|---|---|
| 2021 | 11.5M | $2,249M | |
| 2022 | 13.3M | $2,715M | +15.2% |
| 2023 | 14.7M | $2,515M | +10.7% |
| 2024 | 15.4M | $2,735M | +5.2% |
| 2025 | 16.1M | $2,886M | +4.2% |

**What this means:**
- No sudden jumps, so no sign of a load problem.
- **Correction to the early observation in Phase 2:** knee replacements (27447) looked like they grew from 378K to 534K. That counted every provider type, including PAs and NPs billing as assistants. Counting only our surgeons' knee, hip and partial services, growth is 367K → 470K (+28%), and **it flattened in 2023–2024** (+4.7%, then -0.1%). The number of surgeons also dipped in 2024 (7,082 → 6,954).
- 2020 is the lowest year, consistent with the COVID drop in elective surgery (an explanation, not something this data proves).
- Open Payments totals dip in 2023 (about $2,515M vs $2,715M) while row counts keep rising. Worth a look in Phase 5.

## Phase 4 preview: numbers to expect (2026-11-11)

Checked on an in-memory `ortho_procs` before you build anything. Use these to check your own results.

| Check | Expected |
|---|---|
| Distinct surgeons in `ortho_procs` (Phase 3 checkpoint) | 9,194 |
| `surgeon_year` rows (one per surgeon per year) | 34,605, all unique |
| Surgeons billing in 2024 | 6,954 |
| 2024 surgeons with 20+ joint cases (the guide's cutoff) | **5,563** |
| 2024 surgeons with 50+ joint cases | 3,341 |
| Of those 5,563, how many also have a 2022 row (for growth) | 5,030 (533 have no 2022 baseline, so growth is NULL) |
| Top 2024 surgeon | 810 joint cases (NPI 1003966359) |

**Findings:**
- **The guide's 20-case cutoff is the only one that filters anything.** Every 2024 surgeon already has at least 10 cases, because CMS hides rows with 10 or fewer patients. A cutoff of 10 would keep all 6,954. At 20, you keep 5,563 (80%).
- **No surgeon has more than one city or state in 2024,** so picking one identity row per NPI (`DISTINCT ON`) is safe. Still add an `ORDER BY` so it's repeatable.
- About 10% of the universe (533 surgeons) has no 2022 baseline, so `growth_2yr` is NULL for them. The scoring step treats NULL growth as 0, as the guide does.
- The guide uses `yr`; your `ortho_procs` column is `year`.

## Phases 4–8 (2026-11-12)

**Fix first:** `sql/03_clean.sql` still filtered to `'Orthopedic Surgery'` only. Changed to all three specialties to match decision 5.

**Phase 4 (`sql/04_universe.sql`):** `surgeon_year` 34,605 rows; `target_universe` 5,563 surgeons, one row each. Top surgeon: 810 joint cases in 2024.

**Phase 5 (`sql/05_enrich.sql`):** match rates for the 5,563 surgeons:

| Info | Match |
|---|---|
| Practice name | 94.4% |
| Phone | 92.3% |
| At least one hospital | 96.1% |
| Any industry payment (PY2023–2025) | 97.8% |
| Any robot-product payment | 60.2% (median $456, mostly meals) |

**Phase 6 (`sql/06_score.sql`):**

| Tier | Surgeons | Avg cases | Avg score |
|---|---|---|---|
| A | 1,117 | 160 | 71.7 |
| B | 1,665 | 91 | 54.5 |
| C | 2,781 | 43 | 32.9 |

Segments: Greenfield 1,849 · Maintain 1,658 · Competitive conversion 863 · Rising 636 · KOL 557.

Sensitivity test: with the volume weight at 0.50, **96 of the top 100 stay in the top 100**.

Why #1 is #1 (score 94.3): 255 joint cases in 2024, 3.9x the Colorado median, up 57% since 2022, and no robot-program payments.

**Phase 7 (`sql/07_briefs.sql`):** every surgeon has a territory. Arizona: Phoenix Metro 90 surgeons (19 A-tier), Tucson and Southern Arizona 24, Northern Arizona 18, Arizona Other 1 (an AZ surgeon with a California ZIP). Biggest territory: South Atlantic, 1,161.

**Phase 8 (`sql/08_export.sql`, `export.py`):**

| File | Rows |
|---|---|
| `surgeons.csv` | 5,563 (no duplicate NPIs) |
| `surgeon_trend.csv` | 44,358 |
| `state_year.csv` | 734 |
| `competitor_payments.csv` | 87,209 |
| `surgeon_hospitals.csv` | 17,062 |

`python export.py` reruns steps 03–08 in 36 seconds.

---

## Open items

- [ ] Phase 9: build the Tableau dashboards
- [ ] Download the data dictionaries into `docs/`
- [ ] Look at why Open Payments dollars dipped in PY2023 while rows rose
- [x] Investigated: knee volume growth. Surgeon-only growth is +28% 2020–2024 and flat in 2024 (see Phase 3d)
- [x] Investigated: Open Payments rows with no NPI (mostly teaching hospitals) and the odd payment dates (75 rows before 2015; use `program_year`)
- [x] Robot-product match tightened (decision 15)
- [x] Royalty left out of influence (decision 17)
- [x] `competitor_map` built (decision 16)
- [x] Better multi-site threshold (decision 21)

---

## README material (collected as we go)

**Method:**
> Included Orthopedic Surgery, Sports Medicine and General Surgery (individual providers only). Sports Medicine (n=163) and General Surgery (n=30) were included after confirming every provider holds an M.D. or D.O. and bills volumes comparable to orthopedic surgeons.

**Limitations:**
- Physician Assistants and Nurse Practitioners were excluded. Their per-provider volume matches orthopedic surgeons (median 42–44 vs 48) because they bill as surgical assistants on the same codes, and CMS data cannot distinguish an assist from a primary surgeon claim. The target list is meant for the physicians who choose the implant. Some double counting remains where orthopedic surgeons assist each other.
- Place of service is 99.4% facility, so hospital and outpatient surgery center cases can't be separated.
- A few providers appear under unrelated specialties (pediatrics, OB/GYN, radiology), likely a registration error. The specialty filter excludes them.
- CMS hides any row with 10 or fewer patients, so results describe providers above that threshold.
- The CMS Provider Data Catalog blocks scripted downloads, so three files were downloaded manually.
- The facility affiliation file lists at most 5 hospitals for our surgeons, so "5" means "5 or more."
- Open Payments shows a financial relationship, not proof a surgeon uses that company's robot. Most robot-product payments are small (median $456 per surgeon, mostly meals).

**Scoring line:**
> Surgeons are scored 0–100 from five percentile-ranked signals (volume 35%, accessibility 20%, growth 20%, influence 15%, local standing 10%). Raising the volume weight to 50% keeps 96 of the top 100 surgeons in the top 100.

**Big-data evidence (for the resume bullet):**
- 127.0M rows, 57 GB of raw CSV on a laptop, converted to 5.1 GB of Parquet in about 66 minutes.
