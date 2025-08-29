-- Backfill missing session data by calculating from location points
-- This script will calculate distance, pace, calories, and elevation for sessions with missing data

-- Step 1: Create a temporary table with calculated metrics for all affected sessions
CREATE TEMP TABLE session_calculations AS
WITH session_points AS (
    -- Get all location points for affected sessions with their previous point for distance calculation
    SELECT 
        lp.session_id,
        lp.latitude,
        lp.longitude,
        lp.altitude,
        lp.timestamp,
        LAG(lp.latitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_lat,
        LAG(lp.longitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_lng,
        LAG(lp.altitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_altitude,
        ROW_NUMBER() OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as point_order,
        COUNT(*) OVER (PARTITION BY lp.session_id) as total_points
    FROM location_point lp
    INNER JOIN ruck_session rs ON lp.session_id = rs.id
    WHERE rs.status = 'completed'
      AND rs.duration_seconds >= 600  -- 10+ minute sessions
      AND (rs.distance_km IS NULL 
           OR rs.average_pace IS NULL 
           OR rs.calories_burned IS NULL 
           OR rs.elevation_gain_m IS NULL)
    ORDER BY lp.session_id, lp.timestamp
),
segment_calculations AS (
    -- Calculate distance and elevation gain for each segment
    SELECT 
        session_id,
        CASE 
            WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                -- Haversine formula for distance in meters
                6371000 * 2 * ASIN(
                    SQRT(
                        POWER(SIN(RADIANS(latitude - prev_lat) / 2), 2) +
                        COS(RADIANS(prev_lat)) * COS(RADIANS(latitude)) *
                        POWER(SIN(RADIANS(longitude - prev_lng) / 2), 2)
                    )
                )
            ELSE 0
        END as segment_distance_m,
        CASE 
            WHEN prev_altitude IS NOT NULL 
                 AND altitude > prev_altitude 
                 AND (altitude - prev_altitude) > 2.0 THEN
                altitude - prev_altitude
            ELSE 0
        END as elevation_gain_segment,
        total_points
    FROM session_points
    WHERE prev_lat IS NOT NULL  -- Skip first point of each session
),
session_totals AS (
    -- Sum up totals for each session
    SELECT 
        sc.session_id,
        SUM(sc.segment_distance_m) as total_distance_m,
        SUM(sc.elevation_gain_segment) as total_elevation_gain_m,
        MAX(sc.total_points) as point_count
    FROM segment_calculations sc
    GROUP BY sc.session_id
)
SELECT 
    st.session_id,
    rs.duration_seconds,
    rs.ruck_weight_kg,
    st.point_count,
    -- Distance calculations
    ROUND((st.total_distance_m / 1000.0)::numeric, 6) as calculated_distance_km,
    -- Pace calculation (minutes per km)
    CASE 
        WHEN st.total_distance_m > 0 THEN
            ROUND(((rs.duration_seconds / 60.0) / (st.total_distance_m / 1000.0))::numeric, 6)
        ELSE NULL
    END as calculated_pace_min_per_km,
    -- Elevation gain
    ROUND(st.total_elevation_gain_m::numeric, 2) as calculated_elevation_gain_m,
    -- Calories calculation (approximate formula: weight_kg * distance_km * 1.036)
    CASE 
        WHEN st.total_distance_m > 0 AND rs.ruck_weight_kg > 0 THEN
            ROUND((rs.ruck_weight_kg * (st.total_distance_m / 1000.0) * 1.036)::numeric, 2)
        WHEN st.total_distance_m > 0 THEN
            -- Default to 70kg if no weight specified
            ROUND((70 * (st.total_distance_m / 1000.0) * 1.036)::numeric, 2)
        ELSE 0
    END as calculated_calories_burned
FROM session_totals st
INNER JOIN ruck_session rs ON st.session_id = rs.id
WHERE st.total_distance_m > 0;  -- Only process sessions with valid GPS data

-- Step 2: Show preview of calculations before applying
SELECT 
    'PREVIEW' as action,
    session_id,
    duration_seconds,
    ROUND((duration_seconds / 60.0)::numeric, 1) as duration_minutes,
    calculated_distance_km,
    ROUND((calculated_distance_km * 0.621371)::numeric, 2) as calculated_distance_miles,
    calculated_pace_min_per_km,
    calculated_elevation_gain_m,
    calculated_calories_burned,
    point_count
FROM session_calculations
ORDER BY session_id DESC
LIMIT 20;

-- Step 3: Apply the backfill updates (UNCOMMENT TO EXECUTE)
/*
UPDATE ruck_session 
SET 
    distance_km = sc.calculated_distance_km,
    average_pace = sc.calculated_pace_min_per_km::text,
    elevation_gain_m = sc.calculated_elevation_gain_m,
    calories_burned = sc.calculated_calories_burned,
    updated_at = NOW()
FROM session_calculations sc
WHERE ruck_session.id = sc.session_id
  AND ruck_session.status = 'completed'
  AND sc.calculated_distance_km > 0;
*/

-- Step 4: Verification query (UNCOMMENT TO EXECUTE AFTER UPDATE)
/*
SELECT 
    'VERIFICATION' as action,
    COUNT(*) as sessions_updated,
    COUNT(CASE WHEN distance_km IS NOT NULL THEN 1 END) as has_distance,
    COUNT(CASE WHEN average_pace IS NOT NULL THEN 1 END) as has_pace,
    COUNT(CASE WHEN calories_burned IS NOT NULL THEN 1 END) as has_calories,
    COUNT(CASE WHEN elevation_gain_m IS NOT NULL THEN 1 END) as has_elevation,
    ROUND(AVG(distance_km)::numeric, 2) as avg_distance_km,
    MIN(updated_at) as earliest_update,
    MAX(updated_at) as latest_update
FROM ruck_session rs
INNER JOIN session_calculations sc ON rs.id = sc.session_id
WHERE rs.status = 'completed';
*/

-- Step 5: Show specific sessions that will be updated
SELECT 
    'WILL_UPDATE' as action,
    rs.id as session_id,
    rs.user_id,
    rs.duration_seconds,
    ROUND((rs.duration_seconds / 60.0)::numeric, 1) as duration_minutes,
    rs.completed_at,
    -- Current values
    rs.distance_km as current_distance_km,
    rs.average_pace as current_pace,
    rs.calories_burned as current_calories,
    rs.elevation_gain_m as current_elevation,
    -- Calculated values
    sc.calculated_distance_km as new_distance_km,
    ROUND((sc.calculated_distance_km * 0.621371)::numeric, 2) as new_distance_miles,
    sc.calculated_pace_min_per_km as new_pace,
    sc.calculated_calories_burned as new_calories,
    sc.calculated_elevation_gain_m as new_elevation,
    sc.point_count
FROM ruck_session rs
INNER JOIN session_calculations sc ON rs.id = sc.session_id
WHERE rs.status = 'completed'
  AND sc.calculated_distance_km > 0
ORDER BY rs.completed_at DESC;

-- Cleanup
DROP TABLE session_calculations;
