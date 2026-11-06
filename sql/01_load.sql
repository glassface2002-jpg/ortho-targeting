-- =====================================================================
-- 01_load.sql
-- Converts the raw CMS CSVs in data/raw/ to Parquet in data/parquet/.
-- Slow (tens of minutes); only re-run when the raw CSVs change.
-- Then run 02_views.sql to get the clean table names in ortho.duckdb.
--
-- Parquet outputs (and the view names 02_views.sql gives them):
--   medicare_provider_services   Medicare by Provider and Service, 2020-2024 (has a `year` column)
--   medicare_providers_2024      Medicare by Provider, 2024
--   open_payments_general        Open Payments general payments, PY2021-2025 (has `program_year`)
--   clinicians                   Doctors and Clinicians National Downloadable File
--   facility_affiliations        Clinician-to-facility affiliations
--   hospitals                    Hospital General Information
--
-- Conventions: all column names are lower_snake_case; NPI is BIGINT in every
-- table so they join directly; ZIP codes, FIPS codes, CCNs and HCPCS codes stay
-- text so leading zeros survive.
--
-- Paths are absolute so this works no matter which tool runs it.
-- If you move the project folder, find/replace the path below.
--   C:/Users/glass/Desktop/ortho-targeting
-- =====================================================================

-- Large files spill to disk while sorting/writing.
SET temp_directory = 'C:/Users/glass/Desktop/ortho-targeting/data/tmp';
SET preserve_insertion_order = false;


-- ---------------------------------------------------------------------
-- 1. Medicare Physician & Other Practitioners - by Provider and Service
--    5 yearly CSVs (~15 GB) -> one Parquet folder split by year
-- ---------------------------------------------------------------------
COPY (
    SELECT
        CAST(regexp_extract(filename, 'phys_svc_(\d{4})', 1) AS INTEGER) AS year,
        rndrng_npi                    AS npi,
        rndrng_prvdr_last_org_name    AS last_or_org_name,
        rndrng_prvdr_first_name       AS first_name,
        rndrng_prvdr_mi               AS middle_initial,
        rndrng_prvdr_crdntls          AS credentials,
        rndrng_prvdr_ent_cd           AS entity_type,        -- I = individual, O = organization
        rndrng_prvdr_st1              AS street_1,
        rndrng_prvdr_st2              AS street_2,
        rndrng_prvdr_city             AS city,
        rndrng_prvdr_state_abrvtn     AS state,
        rndrng_prvdr_state_fips       AS state_fips,
        rndrng_prvdr_zip5             AS zip5,
        rndrng_prvdr_ruca             AS ruca_code,
        rndrng_prvdr_ruca_desc        AS ruca_desc,
        rndrng_prvdr_cntry            AS country,
        rndrng_prvdr_type             AS provider_type,      -- specialty, e.g. 'Orthopedic Surgery'
        rndrng_prvdr_mdcr_prtcptg_ind AS medicare_participating,
        hcpcs_cd                      AS hcpcs_code,
        hcpcs_desc                    AS hcpcs_desc,
        hcpcs_drug_ind                AS hcpcs_is_drug,
        place_of_srvc                 AS place_of_service,   -- F = facility, O = office
        tot_benes                     AS total_beneficiaries,
        tot_srvcs                     AS total_services,
        tot_bene_day_srvcs            AS total_bene_day_services,
        avg_sbmtd_chrg                AS avg_submitted_charge,
        avg_mdcr_alowd_amt            AS avg_medicare_allowed,
        avg_mdcr_pymt_amt             AS avg_medicare_payment,
        avg_mdcr_stdzd_amt            AS avg_medicare_standardized
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/phys_svc_*.csv',
        normalize_names = true,
        filename = true,
        union_by_name = true,
        types = {
            'rndrng_npi': 'BIGINT',
            'rndrng_prvdr_state_fips': 'VARCHAR',
            'rndrng_prvdr_zip5': 'VARCHAR',
            'rndrng_prvdr_ruca': 'VARCHAR',
            'hcpcs_cd': 'VARCHAR',
            'tot_benes': 'BIGINT',
            'tot_srvcs': 'DOUBLE',
            'tot_bene_day_srvcs': 'BIGINT'
        }
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/medicare_provider_services'
  (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (year), OVERWRITE true);


-- ---------------------------------------------------------------------
-- 2. Medicare Physician & Other Practitioners - by Provider, 2024
--    81 columns: identity columns renamed, the rest just lower-cased.
-- ---------------------------------------------------------------------
COPY (
    SELECT * RENAME (
        rndrng_npi                    AS npi,
        rndrng_prvdr_last_org_name    AS last_or_org_name,
        rndrng_prvdr_first_name       AS first_name,
        rndrng_prvdr_mi               AS middle_initial,
        rndrng_prvdr_crdntls          AS credentials,
        rndrng_prvdr_ent_cd           AS entity_type,
        rndrng_prvdr_st1              AS street_1,
        rndrng_prvdr_st2              AS street_2,
        rndrng_prvdr_city             AS city,
        rndrng_prvdr_state_abrvtn     AS state,
        rndrng_prvdr_state_fips       AS state_fips,
        rndrng_prvdr_zip5             AS zip5,
        rndrng_prvdr_ruca             AS ruca_code,
        rndrng_prvdr_ruca_desc        AS ruca_desc,
        rndrng_prvdr_cntry            AS country,
        rndrng_prvdr_type             AS provider_type,
        rndrng_prvdr_mdcr_prtcptg_ind AS medicare_participating
    )
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/phys_prov_2024.csv',
        normalize_names = true,
        sample_size = -1,             -- scan the whole file to pick types (it's small)
        types = {
            'rndrng_npi': 'BIGINT',
            'rndrng_prvdr_state_fips': 'VARCHAR',
            'rndrng_prvdr_zip5': 'VARCHAR',
            'rndrng_prvdr_ruca': 'VARCHAR'
        }
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/medicare_providers_2024.parquet'
  (FORMAT parquet, COMPRESSION zstd);


-- ---------------------------------------------------------------------
-- 3. Open Payments - General Payments, PY2021-2025 (~40 GB of CSV)
--    Read everything as text (these files have messy columns), then cast
--    the columns you'll actually do math or joins on.
-- ---------------------------------------------------------------------
COPY (
    SELECT
        * EXCLUDE (
            covered_recipient_npi,
            applicable_manufacturer_or_applicable_gpo_making_payment_name,
            total_amount_of_payment_usdollars,
            date_of_payment,
            number_of_payments_included_in_total_amount,
            nature_of_payment_or_transfer_of_value,
            form_of_payment_or_transfer_of_value,
            payment_publication_date,
            program_year
        ),
        TRY_CAST(covered_recipient_npi AS BIGINT)                          AS npi,
        applicable_manufacturer_or_applicable_gpo_making_payment_name      AS manufacturer_name,
        TRY_CAST(total_amount_of_payment_usdollars AS DECIMAL(14, 2))      AS payment_amount,
        TRY_STRPTIME(date_of_payment, '%m/%d/%Y')::DATE                    AS payment_date,
        TRY_CAST(number_of_payments_included_in_total_amount AS INTEGER)   AS payment_count,
        nature_of_payment_or_transfer_of_value                             AS payment_nature,
        form_of_payment_or_transfer_of_value                               AS payment_form,
        TRY_STRPTIME(payment_publication_date, '%m/%d/%Y')::DATE           AS publication_date,
        CAST(program_year AS INTEGER)                                      AS program_year
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/op_gnrl_*.csv',
        normalize_names = true,
        all_varchar = true,
        union_by_name = true
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/open_payments_general'
  (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (program_year), OVERWRITE true);


-- ---------------------------------------------------------------------
-- 4. Doctors and Clinicians National Downloadable File
-- ---------------------------------------------------------------------
COPY (
    SELECT * RENAME (
        gndr         AS gender,
        cred         AS credential,
        med_sch      AS medical_school,
        grd_yr       AS graduation_year,
        pri_spec     AS primary_specialty,
        sec_spec_all AS secondary_specialties,
        telehlth     AS telehealth,
        num_org_mem  AS org_member_count,
        adr_ln_1     AS address_1,
        adr_ln_2     AS address_2,
        citytown     AS city,
        ind_assgn    AS accepts_assignment_individual,
        grp_assgn    AS accepts_assignment_group,
        adrs_id      AS address_id
    )
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/pdc_clinicians.csv',
        normalize_names = true,
        types = {
            'npi': 'BIGINT',
            'zip_code': 'VARCHAR',
            'telephone_number': 'VARCHAR',
            'grd_yr': 'INTEGER',
            'num_org_mem': 'INTEGER'
        }
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/clinicians.parquet'
  (FORMAT parquet, COMPRESSION zstd);


-- ---------------------------------------------------------------------
-- 5. Facility Affiliation Data
-- ---------------------------------------------------------------------
COPY (
    SELECT * RENAME (
        facility_affiliations_certification_number AS facility_ccn,        -- joins to hospitals.facility_id
        facility_type_certification_number         AS parent_facility_ccn
    )
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/pdc_facility_affil.csv',
        normalize_names = true,
        all_varchar = true,
        types = {'npi': 'BIGINT'}
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/facility_affiliations.parquet'
  (FORMAT parquet, COMPRESSION zstd);


-- ---------------------------------------------------------------------
-- 6. Hospital General Information
--    'Not Available' ratings become NULL so the rating is a real number.
-- ---------------------------------------------------------------------
COPY (
    SELECT
        * EXCLUDE (citytown, countyparish, hospital_overall_rating),
        citytown                                      AS city,
        countyparish                                  AS county,
        -- NULLIF first: a bare TRY_CAST gets pushed into the CSV reader and fails on the text
        TRY_CAST(NULLIF(hospital_overall_rating, 'Not Available') AS INTEGER) AS hospital_overall_rating
    FROM read_csv(
        'C:/Users/glass/Desktop/ortho-targeting/data/raw/pdc_hospital_info.csv',
        normalize_names = true,
        all_varchar = true
    )
) TO 'C:/Users/glass/Desktop/ortho-targeting/data/parquet/hospitals.parquet'
  (FORMAT parquet, COMPRESSION zstd);
