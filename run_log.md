# Download run log

## Run 2026-11-05 17:30

| File | Size | Download time | Status |
|---|---|---|---|
| op_gnrl_2021.csv | 6.46 GB | 1m 48.0s | ok (zip download 1m 37.5s, unzipped general payments CSV) |
| op_gnrl_2022.csv | 7.44 GB | 2m 38.7s | ok (zip download 2m 25.6s, unzipped general payments CSV) |
| op_gnrl_2023.csv | 8.23 GB | 2m 34.2s | ok (zip download 2m 20.8s, unzipped general payments CSV) |
| op_gnrl_2024.csv | 8.97 GB | 2m 18.6s | ok (zip download 2m 03.7s, unzipped general payments CSV) |
| op_gnrl_2025.csv | 9.23 GB | 3m 05.0s | ok (zip download 2m 49.5s, unzipped general payments CSV) |
| pdc_clinicians.csv | - | 0.1s | FAILED: HTTP Error 403: Forbidden |
| pdc_facility_affil.csv | - | 0.1s | FAILED: HTTP Error 403: Forbidden |
| pdc_hospital_info.csv | - | 0.1s | FAILED: HTTP Error 403: Forbidden |

## Manual downloads 2026-11-05 17:40

The Provider Data Catalog returns HTTP 403 to scripts, so these were saved from a browser and moved in.

| File | Size | Download time | Status |
|---|---|---|---|
| pdc_clinicians.csv | 899.7 MB | - | ok (manual browser download) |
| pdc_facility_affil.csv | 133.6 MB | - | ok (manual browser download) |
| pdc_hospital_info.csv | 1.5 MB | - | ok (manual browser download) |

## Run 2026-11-05 17:51

| File | Size | Download time | Status |
|---|---|---|---|
| phys_prov_2024.csv | 508.8 MB | 1m 18.9s | ok |
| phys_svc_2020.csv | 2.99 GB | 10m 31.8s | ok |
| phys_svc_2021.csv | 3.10 GB | 4m 41.3s | ok |
| phys_svc_2022.csv | 3.07 GB | 7m 16.4s | ok |
| phys_svc_2023.csv | 3.06 GB | 4m 12.3s | ok |
| phys_svc_2024.csv | 3.25 GB | 4m 22.9s | ok |

## Phase 2: CSV → Parquet (sql/01_load.sql), 2026-11-05

DuckDB 2.0.0, run on this laptop. Views created by sql/02_views.sql.

| View | Rows | Raw CSV | Parquet | Run time |
|---|---|---|---|---|
| medicare_provider_services (2020–2024) | 48,533,285 | 15.5 GB | 1.7 GB | 2m 56s |
| medicare_providers_2024 | 1,296,739 | 509 MB | 135 MB | 10s |
| open_payments_general (PY2021–2025) | 71,245,399 | 40.3 GB | 3.2 GB | 62m 30s |
| clinicians | 3,630,233 | 900 MB | 165 MB | 7s |
| facility_affiliations | 2,276,877 | 134 MB | 25 MB | 1s |
| hospitals | 5,419 | 1.5 MB | 0.2 MB | <1s |
| **Total** | **126,987,952** | **57 GB** | **5.1 GB** | **~66 min** |

Rows per year, medicare_provider_services: 2020 9.45M · 2021 9.89M · 2022 9.76M · 2023 9.66M · 2024 9.78M
Rows per program year, open_payments_general: 2021 11.56M · 2022 13.32M · 2023 14.73M · 2024 15.50M · 2025 16.13M

## Phases 3–8: build the target list (2026-11-12)

`python export.py` runs sql/03 to sql/08 in order.

| Step | Output | Rows | Run time |
|---|---|---|---|
| 03_clean.sql | ortho_procs, openpay_clean, clinician_locations, surgeon_hospitals | 56,325 · 71,013,191 · 3,630,233 · 1,933,611 | 31.0 s |
| 04_universe.sql | target_universe | 5,563 surgeons | 0.1 s |
| 05_enrich.sql | target_enriched | 5,563 | 1.8 s |
| 06_score.sql | scored_final | 5,563 | 1.8 s |
| 07_briefs.sql | rep_briefs | 5,563 | 0.0 s |
| 08_export.sql | 5 CSVs in data/exports | 154,926 total | 0.3 s |
| **Total** | | | **36.2 s** |

Match rates (5,563 surgeons): practice 94.4% · phone 92.3% · hospital 96.1% · industry payments 97.8%
Sensitivity test: 96 of the top 100 stay in the top 100 with volume weight 0.50
