-- Add unit_preference column to achievements table
ALTER TABLE achievements ADD COLUMN unit_preference VARCHAR(10);

-- Update achievements with standard (imperial) preference
UPDATE achievements SET unit_preference = 'standard' WHERE achievement_key IN (
  'one_mile_club',           -- 1 mile
  'ten_mile_warrior',        -- 10 miles  
  'fifty_mile_club',         -- 50 miles
  'mile_marker'              -- 1 mile single session
);

-- Update achievements with metric preference  
UPDATE achievements SET unit_preference = 'metric' WHERE achievement_key IN (
  'getting_started',         -- 5km total
  'half_marathon',           -- 21.1km total
  'marathon_equivalence',    -- 42.2km total
  'century_mark',            -- 100km total
  'distance_warrior',        -- 500km total
  'ultra_endurance',         -- 1000km total
  '5k_finisher',            -- 5km single session
  '10k_achiever',           -- 10km single session
  '15k_warrior',            -- 15km single session
  '20k_beast',              -- 20km single session
  'half_marathon_ruck',     -- 21.1km single session
  '25k_ultra',              -- 25km single session
  '30k_extreme',            -- 30km single session
  'marathon_ruck',          -- 42.2km single session
  'monthly_distance',       -- 50km+ per month
  'quarterly_challenge'     -- 200km+ per quarter
);

-- Leave unit_preference as NULL for universal achievements that apply to both systems:
-- - first_steps (any distance)
-- - All weight achievements (since they show both units in description)
-- - All power achievements (universal formula)
-- - All pace achievements (apply to both systems)
-- - All time achievements (duration-based)
-- - All consistency achievements (count-based)
-- - All special achievements (not distance-based)

-- Verify the updates
SELECT achievement_key, name, unit_preference, description 
FROM achievements 
ORDER BY unit_preference NULLS LAST, achievement_key;
