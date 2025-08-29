-- Fix unrealistic calorie calculations in ruck_session table
-- This will recalculate calories for sessions with obviously wrong values

-- First, let's see the current fucked up values
SELECT 
  id,
  distance_km,
  duration_seconds / 3600.0 as duration_hours,
  calories_burned as current_calories,
  calories_burned / distance_km as calories_per_km,
  ruck_weight_kg
FROM ruck_session 
WHERE status = 'completed' 
  AND distance_km > 0 
  AND (
    calories_burned > distance_km * 200 OR  -- More than 200 cal/km is suspicious
    calories_burned < distance_km * 30      -- Less than 30 cal/km is too low
  )
ORDER BY calories_burned / distance_km DESC
LIMIT 20;

-- Use the helper functions from the comparison queries (run those first!)

-- Update the broken calorie calculations using subquery approach
UPDATE ruck_session 
SET 
  calories_burned = (
    SELECT calculate_mechanical_calories(
      u.weight_kg,
      COALESCE(ruck_session.ruck_weight_kg, 0.0),
      ruck_session.distance_km,
      COALESCE(ruck_session.elevation_gain_m, 0.0),
      ruck_session.duration_seconds
    )
    FROM "user" u 
    WHERE u.id = ruck_session.user_id
  ),
  updated_at = NOW()
WHERE status = 'completed'
  AND distance_km > 0
  AND duration_seconds > 0
  AND EXISTS (SELECT 1 FROM "user" u WHERE u.id = ruck_session.user_id AND u.weight_kg > 0)
  AND (
    -- Target obviously fucked up calculations
    calories_burned > distance_km * 200 OR  -- More than 200 cal/km
    calories_burned < distance_km * 30 OR   -- Less than 30 cal/km  
    calories_burned > 5000 OR               -- More than 5000 total calories
    calories_burned < 50                    -- Less than 50 total calories
  );

-- Show the fixed values
SELECT 
  'Fixed' as status,
  COUNT(*) as sessions_updated,
  AVG(calories_burned) as avg_calories_after,
  MIN(calories_burned) as min_calories_after,
  MAX(calories_burned) as max_calories_after
FROM ruck_session rs
JOIN "user" u ON rs.user_id = u.id
WHERE rs.status = 'completed' 
  AND rs.distance_km > 0
  AND rs.updated_at > NOW() - INTERVAL '1 minute';

-- Verify the results look sane
SELECT 
  id,
  distance_km,
  duration_seconds / 3600.0 as duration_hours,
  calories_burned as fixed_calories,
  ROUND((calories_burned / distance_km)::NUMERIC, 1) as calories_per_km,
  ruck_weight_kg
FROM ruck_session 
WHERE status = 'completed' 
  AND distance_km > 0 
  AND updated_at > NOW() - INTERVAL '1 minute'
ORDER BY calories_burned DESC
LIMIT 20;
