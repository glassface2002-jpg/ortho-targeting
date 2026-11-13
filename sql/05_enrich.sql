-- Phase 5: Add contact info, hospitals and competitor payments


-- Pick one practice location per surgeon
-- First choice: same ZIP as their Medicare address. Second choice: a location with a phone number.
CREATE OR REPLACE TABLE surgeon_contact AS
SELECT DISTINCT ON (c.npi)
  c.npi,
  c.practice_name,
  c.address,
  c.address_2,
  c.city  AS practice_city,
  c.zip5  AS practice_zip,
  c.phone,
  c.grad_year,
  2026 - c.grad_year AS years_in_practice
FROM clinician_locations c
JOIN target_universe t USING (npi)
ORDER BY c.npi, (c.zip5 = t.zip5) DESC, (c.phone IS NOT NULL) DESC, c.address;


-- Count each surgeon's hospitals and list the names
CREATE OR REPLACE TABLE surgeon_hosp_summary AS
SELECT
  npi,
  COUNT(*) AS n_hospitals,
  STRING_AGG(hospital_name, '; ' ORDER BY hospital_name) AS hospitals
FROM surgeon_hospitals
WHERE npi IN (SELECT npi FROM target_universe)
GROUP BY npi;


-- Payments to our surgeons, with the competitor name and a flag for robot products
-- Competitor names come from config/competitor_map.csv; anyone not in the file is 'Other'
-- Robot products are matched by exact name so drugs like INTRAROSA don't count
CREATE OR REPLACE TABLE openpay_enriched AS
SELECT
  o.*,
  COALESCE(m.competitor, 'Other') AS competitor,
  list_has_any(
    [UPPER(o.product_1), UPPER(o.product_2), UPPER(o.product_3), UPPER(o.product_4), UPPER(o.product_5)],
    ['MAKO', 'MAKOPLASTY', 'ROSA', 'ROSA-KNEE', 'ROSA PKA', 'ROSA-HIP', 'VELYS', 'CORI']
  ) AS is_robotic
FROM openpay_clean o
LEFT JOIN read_csv('config/competitor_map.csv') m USING (manufacturer_name)
WHERE o.npi IN (SELECT npi FROM target_universe);


-- One row per surgeon, using payments from the last 3 program years (2023-2025)
CREATE OR REPLACE TABLE surgeon_competitor AS
WITH recent AS (
  SELECT * FROM openpay_enriched WHERE program_year >= 2023
),
-- Total paid by each of the 4 big competitors, to find each surgeon's top one
by_competitor AS (
  SELECT npi, competitor, SUM(amount) AS total
  FROM recent
  WHERE competitor <> 'Other'
  GROUP BY npi, competitor
)
SELECT
  r.npi,
  SUM(r.amount) AS industry_total,
  SUM(r.amount) FILTER (WHERE r.is_robotic) AS robotic_total,
  SUM(r.amount) FILTER (WHERE r.nature IN (
    'Consulting Fee',
    'Honoraria',
    'Compensation for serving as faculty or as a speaker for a medical education program',
    'Compensation for services other than consulting, including serving as faculty or as a speaker at a venue other than a continuing education program'
  )) AS influence_total,
  COUNT(*) AS n_payments,
  (SELECT ARG_MAX(b.competitor, b.total) FROM by_competitor b WHERE b.npi = r.npi) AS top_competitor
FROM recent r
GROUP BY r.npi;


-- Put everything together, one row per surgeon (missing payments become 0)
CREATE OR REPLACE TABLE target_enriched AS
SELECT
  t.*,
  c.practice_name,
  c.address,
  c.address_2,
  c.practice_city,
  c.practice_zip,
  c.phone,
  c.grad_year,
  c.years_in_practice,
  COALESCE(h.n_hospitals, 0)     AS n_hospitals,
  h.hospitals,
  COALESCE(p.industry_total, 0)  AS industry_total,
  COALESCE(p.robotic_total, 0)   AS robotic_total,
  COALESCE(p.influence_total, 0) AS influence_total,
  COALESCE(p.n_payments, 0)      AS n_payments,
  p.top_competitor
FROM target_universe t
LEFT JOIN surgeon_contact c      USING (npi)
LEFT JOIN surgeon_hosp_summary h USING (npi)
LEFT JOIN surgeon_competitor p   USING (npi);


-- Match rates (how many surgeons got each piece of info)
SELECT
  COUNT(*) AS surgeons,
  ROUND(100.0 * COUNT(practice_name) / COUNT(*), 1) AS pct_with_practice,
  ROUND(100.0 * COUNT(phone) / COUNT(*), 1)         AS pct_with_phone,
  ROUND(100.0 * COUNT(*) FILTER (WHERE n_hospitals > 0) / COUNT(*), 1) AS pct_with_hospital,
  ROUND(100.0 * COUNT(*) FILTER (WHERE n_payments > 0) / COUNT(*), 1)  AS pct_with_payments,
  ROUND(100.0 * COUNT(*) FILTER (WHERE robotic_total > 0) / COUNT(*), 1) AS pct_with_robot_payments
FROM target_enriched;
