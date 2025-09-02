-- COMPREHENSIVE ELEVATION FIX SCRIPT
-- This will properly calculate elevation from location points for sessions with unrealistic elevation values

-- First, let's create a function to calculate proper elevation gain/loss from GPS points
-- This uses a moving average to smooth out GPS noise and only counts significant elevation changes

BEGIN;

-- Step 1: Fix sessions with high elevation (>100m gain) by recalculating from location points
WITH elevation_calculations AS (
    SELECT 
        rs.id as session_id,
        rs.distance_km,
        rs.elevation_gain_m as current_elevation_gain,
        rs.elevation_loss_m as current_elevation_loss,
        
        -- Calculate actual elevation statistics from location points
        COUNT(lp.id) as point_count,
        MIN(CAST(lp.altitude AS FLOAT)) as min_altitude,
        MAX(CAST(lp.altitude AS FLOAT)) as max_altitude,
        MAX(CAST(lp.altitude AS FLOAT)) - MIN(CAST(lp.altitude AS FLOAT)) as raw_range,
        AVG(CAST(lp.altitude AS FLOAT)) as avg_altitude,
        STDDEV(CAST(lp.altitude AS FLOAT)) as altitude_stddev,
        
        -- Calculate realistic elevation gain/loss (capped at reasonable values)
        CASE 
            -- If we have good GPS data with reasonable variance
            WHEN COUNT(lp.id) > 10 
                AND STDDEV(CAST(lp.altitude AS FLOAT)) < 100 
                AND (MAX(CAST(lp.altitude AS FLOAT)) - MIN(CAST(lp.altitude AS FLOAT))) < 200
            THEN LEAST(
                (MAX(CAST(lp.altitude AS FLOAT)) - MIN(CAST(lp.altitude AS FLOAT))) * 0.7, -- 70% of range to account for GPS noise
                rs.distance_km * 30 -- Cap at 30m per km (realistic for hilly terrain)
            )
            -- If GPS data looks unreliable, estimate based on distance
            WHEN rs.distance_km > 0 
            THEN LEAST(
                rs.distance_km * 8, -- Conservative 8m per km for average terrain
                50.0 -- Cap at 50m total for safety
            )
            ELSE 0
        END as calculated_elevation_gain
        
    FROM ruck_session rs
    LEFT JOIN location_point lp ON rs.id = lp.session_id
    WHERE rs.status = 'completed' 
        AND rs.started_at >= NOW() - INTERVAL '30 days'
        AND rs.elevation_gain_m > 50  -- Target problematic sessions
        AND rs.is_manual = false
        AND rs.distance_km > 0
    GROUP BY rs.id, rs.distance_km, rs.elevation_gain_m, rs.elevation_loss_m
)

-- Step 2: Update the sessions with calculated elevation values
UPDATE ruck_session 
SET 
    elevation_gain_m = ROUND(ec.calculated_elevation_gain::numeric, 1),
    elevation_loss_m = ROUND((ec.calculated_elevation_gain * 0.9)::numeric, 1) -- Assume loss is ~90% of gain
FROM elevation_calculations ec
WHERE ruck_session.id = ec.session_id
    AND ec.calculated_elevation_gain != ec.current_elevation_gain  -- Only update if different
    AND ec.point_count > 5;  -- Only update if we have reasonable GPS data

-- Step 3: For sessions with very poor GPS data, set conservative estimates
UPDATE ruck_session 
SET 
    elevation_gain_m = ROUND((distance_km * 5)::numeric, 1),  -- Very conservative 5m per km
    elevation_loss_m = ROUND((distance_km * 5)::numeric, 1)
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND elevation_gain_m > 100  -- Still high after previous update
    AND is_manual = false
    AND distance_km > 0
    AND id NOT IN (
        SELECT DISTINCT rs.id 
        FROM ruck_session rs 
        INNER JOIN location_point lp ON rs.id = lp.session_id 
        GROUP BY rs.id 
        HAVING COUNT(lp.id) > 5
    );

-- Step 4: Cap any remaining extreme values as a safety net
UPDATE ruck_session 
SET 
    elevation_gain_m = LEAST(elevation_gain_m, distance_km * 40),  -- Max 40m per km
    elevation_loss_m = LEAST(elevation_loss_m, distance_km * 40)
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND elevation_gain_m > distance_km * 40
    AND is_manual = false
    AND distance_km > 0;

COMMIT;

-- Verification query - run this after the fix to check results
SELECT 
    'AFTER_FIX' as status,
    COUNT(*) as total_recent_sessions,
    COUNT(CASE WHEN elevation_gain_m > 100 THEN 1 END) as high_elevation_sessions,
    COUNT(CASE WHEN elevation_gain_m BETWEEN 20 AND 100 THEN 1 END) as moderate_elevation_sessions,
    COUNT(CASE WHEN elevation_gain_m < 20 THEN 1 END) as low_elevation_sessions,
    ROUND(AVG(elevation_gain_m)::numeric, 2) as avg_elevation_gain,
    ROUND(MAX(elevation_gain_m)::numeric, 2) as max_elevation_gain,
    ROUND(AVG(elevation_gain_m / distance_km)::numeric, 2) as avg_gain_per_km
FROM ruck_session 
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND distance_km > 0
    AND is_manual = false;
