-- Phase 8: Export small CSVs for Tableau (they all join on npi)
-- NPI is saved as text so Tableau doesn't add it up like a number


-- 1. One row per surgeon (everything from the rep briefs)
COPY (
  SELECT
    CAST(npi AS VARCHAR)            AS npi,
    territory,
    rep_name,
    tier,
    priority_score,
    segment,
    surgeon_name,
    specialty,
    practice_name,
    address,
    city,
    state,
    zip5,
    phone,
    n_hospitals,
    hospitals,
    CAST(joint_cases AS INT)        AS joint_cases,
    CAST(knee_cases AS INT)         AS knee_cases,
    CAST(hip_cases AS INT)          AS hip_cases,
    CAST(partial_cases AS INT)      AS partial_cases,
    ROUND(100 * growth_2yr, 1)      AS growth_2yr_pct,
    ROUND(vs_state_median, 2)       AS vs_state_median,
    top_competitor,
    ROUND(robotic_total, 2)         AS robotic_total,
    ROUND(influence_total, 2)       AS influence_total,
    years_in_practice,
    ROUND(p_volume, 3)              AS p_volume,
    ROUND(p_access, 3)              AS p_access,
    ROUND(p_growth, 3)              AS p_growth,
    ROUND(p_influence, 3)           AS p_influence,
    ROUND(p_local, 3)               AS p_local,
    talking_points
  FROM rep_briefs
  ORDER BY priority_score DESC
) TO 'data/exports/surgeons.csv' (HEADER, DELIMITER ',');


-- 2. Surgeon x year x procedure (for each surgeon's trend line)
COPY (
  SELECT
    CAST(npi AS VARCHAR)       AS npi,
    year,
    proc_group,
    CAST(SUM(services) AS INT) AS cases
  FROM ortho_procs
  WHERE npi IN (SELECT npi FROM rep_briefs)
  GROUP BY ALL
  ORDER BY npi, year, proc_group
) TO 'data/exports/surgeon_trend.csv' (HEADER, DELIMITER ',');


-- 3. State x year x procedure (for the national map and trend), all surgeons
COPY (
  SELECT
    state,
    year,
    proc_group,
    CAST(SUM(services) AS INT) AS cases,
    COUNT(DISTINCT npi)        AS surgeons
  FROM ortho_procs
  GROUP BY ALL
  ORDER BY state, year, proc_group
) TO 'data/exports/state_year.csv' (HEADER, DELIMITER ',');


-- 4. Surgeon x competitor x program year x payment type (for the competitive landscape)
COPY (
  SELECT
    CAST(npi AS VARCHAR)         AS npi,
    competitor,
    program_year,
    nature,
    is_robotic,
    ROUND(SUM(amount), 2)        AS amount,
    COUNT(*)                     AS n_payments
  FROM openpay_enriched
  GROUP BY ALL
  ORDER BY npi, program_year, competitor
) TO 'data/exports/competitor_payments.csv' (HEADER, DELIMITER ',');


-- 5. Surgeon x hospital
COPY (
  SELECT
    CAST(npi AS VARCHAR) AS npi,
    facility_ccn,
    hospital_name,
    city,
    state,
    hospital_type,
    hospital_overall_rating
  FROM surgeon_hospitals
  WHERE npi IN (SELECT npi FROM rep_briefs)
  ORDER BY npi, hospital_name
) TO 'data/exports/surgeon_hospitals.csv' (HEADER, DELIMITER ',');


-- Checkpoint: surgeons.csv should have no duplicate NPIs
SELECT COUNT(*) AS rows, COUNT(DISTINCT npi) AS surgeons
FROM read_csv('data/exports/surgeons.csv');
