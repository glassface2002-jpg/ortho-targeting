-- Phase 4: Target universe (one row per surgeon)


-- Total joint cases for each surgeon in each year
CREATE OR REPLACE TABLE surgeon_year AS
SELECT
  npi,
  year,
  SUM(services) AS joint_cases,
  COALESCE(SUM(services) FILTER (WHERE proc_group = 'Total knee'), 0)   AS knee_cases,
  COALESCE(SUM(services) FILTER (WHERE proc_group = 'Total hip'), 0)    AS hip_cases,
  COALESCE(SUM(services) FILTER (WHERE proc_group = 'Partial knee'), 0) AS partial_cases
FROM ortho_procs
GROUP BY npi, year;


-- One row per surgeon with 2024 volume, growth since 2022, and where they practice
-- Only surgeons with 20 or more joint cases in 2024 are kept
CREATE OR REPLACE TABLE target_universe AS
WITH latest AS (
  SELECT * FROM surgeon_year WHERE year = 2024
),
base AS (
  SELECT npi, joint_cases AS cases_2022 FROM surgeon_year WHERE year = 2022
),
ident AS (
  SELECT DISTINCT ON (npi)
    npi, first_name, last_name, credentials, specialty, city, state, zip5
  FROM ortho_procs
  WHERE year = 2024
  ORDER BY npi, services DESC
),
universe AS (
  SELECT
    i.*,
    l.joint_cases,
    l.knee_cases,
    l.hip_cases,
    l.partial_cases,
    b.cases_2022,
    (l.joint_cases - b.cases_2022) / NULLIF(b.cases_2022, 0) AS growth_2yr
  FROM latest l
  JOIN ident i USING (npi)
  LEFT JOIN base b USING (npi)
  WHERE l.joint_cases >= 20
)
-- Compare each surgeon to the median surgeon in their state
SELECT
  *,
  joint_cases / MEDIAN(joint_cases) OVER (PARTITION BY state) AS vs_state_median
FROM universe;


-- Checkpoint: these two numbers should match (one row per surgeon)
SELECT COUNT(*) AS rows, COUNT(DISTINCT npi) AS surgeons FROM target_universe;

-- Top 10 surgeons by 2024 joint cases
SELECT first_name, last_name, specialty, city, state, joint_cases, growth_2yr
FROM target_universe
ORDER BY joint_cases DESC
LIMIT 10;
