-- Exploration Query to find the number of surgeons and total services for specific HCPCS codes related to orthopedic procedures. 
-- The query filters for individual providers (entity_type = 'I') and groups the results by year, HCPCS code, HCPCS description, and provider type. 
-- The final output is ordered by the total number of services in descending order.

SELECT year,
       hcpcs_code,
       hcpcs_desc,
       provider_type,
       COUNT(DISTINCT npi)  AS surgeons,
       SUM(total_services)  AS services
FROM medicare_provider_services
WHERE hcpcs_code IN ('27447', '27130', '27446')
  AND entity_type = 'I'
GROUP BY ALL
ORDER BY services DESC;



-- Check whether sports medicine and general surgery really operate on the same patients as orthopedic surgeons or just refer to them. 
-- This query counts the number of unique NPIs for each provider type and calculates the median and maximum number of cases for each provider type. 
-- It also counts the number of NPIs with 20 or more cases. 
-- The results are filtered to include only orthopedic surgery, sports medicine, and general surgery provider types.
WITH per_npi AS (
  SELECT provider_type, npi, SUM(total_services) AS cases
  FROM medicare_provider_services
  WHERE year = 2024
    AND hcpcs_code IN ('27447', '27130', '27446')
    AND entity_type = 'I'
  GROUP BY ALL
)
SELECT provider_type,
       COUNT(*)                          AS npis,
       MEDIAN(cases)                     AS median_cases,
       MAX(cases)                        AS max_cases,
       COUNT(*) FILTER (WHERE cases >= 20) AS npis_20plus
FROM per_npi
WHERE provider_type IN ('Orthopedic Surgery', 'Sports Medicine', 'General Surgery')
GROUP BY 1
ORDER BY 2 DESC;


-- Create a new table ortho_procs that contains relevant information about orthopedic procedures performed by individual providers.
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

-- Sports medicine and general surgery are kept because the checks showed they are MD/DO surgeons with real volume.




-- Create a new table openpay_clean that contains relevant information about payments made to healthcare providers, including the record ID, 
--program year, NPI, covered recipient type, manufacturer name, payment amount, payment date, payment nature, payment form, 
--and names of drugs or biologicals or devices or medical supplies associated with the payment. The table filters out records where the NPI is NULL.
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

--Creates a new table called clinician_locations that contains relevant information about clinicians, including their NPI, name, specialty, 
--graduation year, practice name, address, city, state, zip code, and phone number.
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

--Creates a new table called surgeon_hospitals that contains distinct combinations of surgeon NPIs and their affiliated hospital information.
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