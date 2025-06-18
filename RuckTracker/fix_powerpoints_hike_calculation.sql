-- Fix powerpoints calculation for hikes (ruck_weight_kg = 0) and flat routes (elevation_gain_m = 0 or null)
-- When ruck_weight_kg = 0, treat it as 1 for the calculation
-- When elevation_gain_m = 0 or null, treat it as 1 meter for the calculation

-- Drop the existing computed column
ALTER TABLE ruck_session DROP COLUMN IF EXISTS power_points;

-- Recreate with fixed formula that treats 0 weight as 1 and 0/null elevation as 1
ALTER TABLE ruck_session 
ADD COLUMN power_points NUMERIC GENERATED ALWAYS AS (
    GREATEST(ruck_weight_kg, 1) * 
    COALESCE(distance_km, 0) * 
    GREATEST(COALESCE(elevation_gain_m, 1), 1)
) STORED;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_ruck_session_power_points ON ruck_session(power_points) WHERE status = 'completed';
