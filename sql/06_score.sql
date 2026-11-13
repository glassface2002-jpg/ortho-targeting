-- Phase 6: Score every surgeon from 0 to 100, then give a tier and a segment


-- Rank each signal from 0 to 1 (1 = best)
-- Accessibility is flipped: less competitor robot money = easier to win
CREATE OR REPLACE TABLE scored AS
SELECT
  *,
  PERCENT_RANK() OVER (ORDER BY joint_cases)             AS p_volume,
  1 - PERCENT_RANK() OVER (ORDER BY robotic_total)       AS p_access,
  PERCENT_RANK() OVER (ORDER BY COALESCE(growth_2yr, 0)) AS p_growth,
  PERCENT_RANK() OVER (ORDER BY influence_total)         AS p_influence,
  PERCENT_RANK() OVER (ORDER BY vs_state_median)         AS p_local
FROM target_enriched;


-- Weighted score using the weights in config/weights.json
-- Tier: A = top 20%, B = next 30%, C = the rest
-- Segment: checked in order, first match wins
-- A robot "relationship" means $1,000+ in robot product payments (smaller amounts are mostly meals)
CREATE OR REPLACE TABLE scored_final AS
WITH w AS (
  SELECT * FROM read_json('config/weights.json')
),
scores AS (
  SELECT
    s.*,
    ROUND(100 * (w.volume        * s.p_volume
               + w.accessibility * s.p_access
               + w.growth        * s.p_growth
               + w.influence     * s.p_influence
               + w.local         * s.p_local), 1) AS priority_score
  FROM scored s, w
)
SELECT
  *,
  CASE
    WHEN PERCENT_RANK() OVER (ORDER BY priority_score DESC) < 0.20 THEN 'A'
    WHEN PERCENT_RANK() OVER (ORDER BY priority_score DESC) < 0.50 THEN 'B'
    ELSE 'C'
  END AS tier,
  CASE
    WHEN p_influence >= 0.90 AND influence_total > 0           THEN 'KOL'
    WHEN robotic_total >= 1000                                 THEN 'Competitive conversion'
    WHEN joint_cases > MEDIAN(joint_cases) OVER ()             THEN 'Greenfield'
    WHEN growth_2yr > 0.25                                     THEN 'Rising'
    ELSE 'Maintain'
  END AS segment
FROM scores;


-- Check: average volume should go down from tier A to C
SELECT tier, COUNT(*) AS surgeons, ROUND(AVG(joint_cases)) AS avg_cases, ROUND(AVG(priority_score), 1) AS avg_score
FROM scored_final
GROUP BY tier
ORDER BY tier;

-- How many surgeons are in each segment
SELECT segment, COUNT(*) AS surgeons
FROM scored_final
GROUP BY segment
ORDER BY surgeons DESC;

-- Top 10 surgeons by score
SELECT first_name, last_name, state, priority_score, tier, segment, joint_cases, robotic_total, influence_total
FROM scored_final
ORDER BY priority_score DESC
LIMIT 10;


-- Sensitivity test: raise the volume weight to 0.50 and see how many of the top 100 stay in the top 100
WITH w AS (
  SELECT * FROM read_json('config/weights.json')
),
normal AS (
  SELECT npi FROM scored_final ORDER BY priority_score DESC LIMIT 100
),
more_volume AS (
  SELECT s.npi
  FROM scored s, w
  ORDER BY (0.50 * s.p_volume + w.accessibility * s.p_access + w.growth * s.p_growth
          + w.influence * s.p_influence + w.local * s.p_local) DESC
  LIMIT 100
)
SELECT COUNT(*) AS top100_overlap
FROM normal
JOIN more_volume USING (npi);
