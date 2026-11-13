-- Phase 7: Rep briefs (one row per surgeon with territory, numbers and talking points)


-- Territories come from config/territories.csv
-- Arizona is split by 3-digit ZIP, every other state is grouped by Census region
CREATE OR REPLACE TABLE territories AS
SELECT * FROM read_csv('config/territories.csv', types = {'zip3': 'VARCHAR'});


CREATE OR REPLACE TABLE rep_briefs AS
WITH with_territory AS (
  SELECT
    s.*,
    COALESCE(tz.territory, ts.territory) AS territory,
    COALESCE(tz.rep_name, ts.rep_name)   AS rep_name
  FROM scored_final s
  -- Arizona: match on the first 3 digits of the ZIP
  LEFT JOIN territories tz ON tz.zip3 = LEFT(s.zip5, 3)
  -- Everyone else (and any Arizona ZIP not in the list): match on state
  LEFT JOIN territories ts ON ts.state = s.state AND ts.zip3 IS NULL
)
SELECT
  territory,
  rep_name,
  tier,
  priority_score,
  segment,
  npi,
  first_name || ' ' || last_name || COALESCE(', ' || credentials, '') AS surgeon_name,
  specialty,
  practice_name,
  address,
  COALESCE(practice_city, city) AS city,
  state,
  COALESCE(practice_zip, zip5)  AS zip5,
  phone,
  n_hospitals,
  hospitals,
  joint_cases,
  knee_cases,
  hip_cases,
  partial_cases,
  growth_2yr,
  vs_state_median,
  top_competitor,
  robotic_total,
  influence_total,
  years_in_practice,
  p_volume,
  p_access,
  p_growth,
  p_influence,
  p_local,
  -- Each talking point cites a number from the data. Empty ones are skipped.
  CONCAT_WS(' | ',
    CAST(joint_cases AS INT) || ' Medicare joint replacements in 2024',
    CASE WHEN vs_state_median >= 2
      THEN 'Does ' || ROUND(vs_state_median, 1) || 'x the ' || state || ' median joint volume' END,
    CASE WHEN growth_2yr >= 0.25
      THEN 'Joint cases up ' || CAST(ROUND(100 * growth_2yr) AS INT) || '% since 2022 - capacity conversation' END,
    CASE WHEN segment = 'Greenfield'
      THEN 'No real robot-program payments on record - lead with a first-robot evaluation' END,
    CASE WHEN segment = 'Competitive conversion'
      THEN 'Existing ' || COALESCE(top_competitor, 'competitor') || ' relationship - lead with workflow and outcomes comparison' END,
    CASE WHEN partial_cases >= 10
      THEN 'Active partial-knee surgeon (' || CAST(partial_cases AS INT) || ' cases) - robotic precision angle' END,
    -- The CMS file lists at most 5 hospitals for our surgeons, so 5 means "5 or more"
    CASE WHEN n_hospitals >= 5
      THEN 'Affiliated with 5+ hospitals - multi-site opportunity' END,
    CASE WHEN segment = 'KOL'
      THEN 'Industry consultant/speaker - potential peer-education partner' END
  ) AS talking_points
FROM with_territory;


-- Check: every surgeon got a territory
SELECT COUNT(*) AS surgeons, COUNT(territory) AS with_territory FROM rep_briefs;

-- Surgeons and A-tier surgeons per territory
SELECT territory, rep_name, COUNT(*) AS surgeons, COUNT(*) FILTER (WHERE tier = 'A') AS a_tier
FROM rep_briefs
GROUP BY ALL
ORDER BY surgeons DESC;

-- 10 random briefs to read out loud
SELECT surgeon_name, territory, tier, segment, talking_points
FROM rep_briefs
USING SAMPLE 10;
