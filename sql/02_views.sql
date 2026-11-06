-- =====================================================================
-- 02_views.sql
-- Creates the clean, readable table names in ortho.duckdb. Each view
-- reads the Parquet files that 01_load.sql wrote, so the database stays
-- small and always shows the latest load. Takes about a second.
--
-- In the DuckDB CLI, connected to ortho.duckdb:
--   .read sql/02_views.sql
-- =====================================================================
CREATE OR REPLACE VIEW medicare_provider_services AS
    SELECT * FROM read_parquet(
        'C:/Users/glass/Desktop/ortho-targeting/data/parquet/medicare_provider_services/*/*.parquet',
        hive_partitioning = true, hive_types = {'year': INTEGER});

CREATE OR REPLACE VIEW medicare_providers_2024 AS
    SELECT * FROM read_parquet('C:/Users/glass/Desktop/ortho-targeting/data/parquet/medicare_providers_2024.parquet');

CREATE OR REPLACE VIEW open_payments_general AS
    SELECT * FROM read_parquet(
        'C:/Users/glass/Desktop/ortho-targeting/data/parquet/open_payments_general/*/*.parquet',
        hive_partitioning = true, hive_types = {'program_year': INTEGER});

CREATE OR REPLACE VIEW clinicians AS
    SELECT * FROM read_parquet('C:/Users/glass/Desktop/ortho-targeting/data/parquet/clinicians.parquet');

CREATE OR REPLACE VIEW facility_affiliations AS
    SELECT * FROM read_parquet('C:/Users/glass/Desktop/ortho-targeting/data/parquet/facility_affiliations.parquet');

CREATE OR REPLACE VIEW hospitals AS
    SELECT * FROM read_parquet('C:/Users/glass/Desktop/ortho-targeting/data/parquet/hospitals.parquet');


-- Quick check: row counts per view
SELECT 'medicare_provider_services' AS view_name, count(*) AS row_count FROM medicare_provider_services
UNION ALL SELECT 'medicare_providers_2024', count(*) FROM medicare_providers_2024
UNION ALL SELECT 'open_payments_general',   count(*) FROM open_payments_general
UNION ALL SELECT 'clinicians',              count(*) FROM clinicians
UNION ALL SELECT 'facility_affiliations',   count(*) FROM facility_affiliations
UNION ALL SELECT 'hospitals',               count(*) FROM hospitals;
