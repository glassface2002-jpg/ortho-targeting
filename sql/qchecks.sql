--Make sure all NPIs are 10 digits long and have no leading or trailing spaces 
SELECT 'ortho_procs' AS table_name,
       COUNT(*) FILTER (WHERE npi IS NULL OR LENGTH(CAST(npi AS VARCHAR)) <> 10) AS bad_rows
FROM ortho_procs
UNION ALL
SELECT 'openpay_clean', COUNT(*) FILTER (WHERE npi IS NULL OR LENGTH(CAST(npi AS VARCHAR)) <> 10) FROM openpay_clean
UNION ALL
SELECT 'clinician_locations', COUNT(*) FILTER (WHERE npi IS NULL OR LENGTH(CAST(npi AS VARCHAR)) <> 10) FROM clinician_locations
UNION ALL
SELECT 'surgeon_hospitals', COUNT(*) FILTER (WHERE npi IS NULL OR LENGTH(CAST(npi AS VARCHAR)) <> 10) FROM surgeon_hospitals;



-- No negative services or payments 
SELECT 'ortho_procs.services' AS col, COUNT(*) FILTER (WHERE services < 0) AS negatives FROM ortho_procs
UNION ALL SELECT 'ortho_procs.patients',    COUNT(*) FILTER (WHERE patients < 0)    FROM ortho_procs
UNION ALL SELECT 'ortho_procs.avg_payment', COUNT(*) FILTER (WHERE avg_payment < 0) FROM ortho_procs
UNION ALL SELECT 'openpay_clean.amount',    COUNT(*) FILTER (WHERE amount < 0)      FROM openpay_clean;

-- One name and specialty per year for each surgeon 
SELECT year, npi,
       COUNT(DISTINCT last_name || ', ' || first_name) AS names,
       COUNT(DISTINCT specialty)                       AS specialties
FROM ortho_procs
GROUP BY year, npi
HAVING names > 1 OR specialties > 1;

-- Makes sure all the yearly totals are stable
SELECT year,
       COUNT(*)                     AS rows,
       COUNT(DISTINCT npi)          AS surgeons,
       ROUND(SUM(services))         AS services,
       ROUND(100.0 * (SUM(services) / LAG(SUM(services)) OVER (ORDER BY year) - 1), 1) AS pct_change
FROM ortho_procs
GROUP BY year
ORDER BY year;