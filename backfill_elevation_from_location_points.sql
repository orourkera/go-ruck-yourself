-- Backfill elevation gain and loss for ruck sessions without elevation data
-- This script finds sessions missing elevation and calculates both gain and loss from location points

-- Step 1: Find most recent 50 sessions without elevation data that have location points
WITH recent_sessions AS (
    SELECT rs.id as session_id
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND (rs.elevation_gain_m IS NULL OR rs.elevation_gain_m = 0)
      AND rs.duration_seconds >= 300  -- At least 5 minutes
    ORDER BY rs.completed_at DESC
    LIMIT 50
),
sessions_without_elevation AS (
    SELECT DISTINCT rs.session_id
    FROM recent_sessions rs
    INNER JOIN location_point lp ON rs.session_id = lp.session_id
),

-- Step 2: Calculate elevation gain AND loss from location points for each session
elevation_calculations AS (
    SELECT 
        lp.session_id,
        -- Calculate elevation gain using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude > prev_altitude 
                     AND (lp.altitude - prev_altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (lp.altitude - prev_altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN lp.altitude - prev_altitude
                ELSE 0
            END
        ) as calculated_elevation_gain_m,
        -- Calculate elevation loss using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude < prev_altitude 
                     AND (prev_altitude - lp.altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (prev_altitude - lp.altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN prev_altitude - lp.altitude
                ELSE 0
            END
        ) as calculated_elevation_loss_m,
        COUNT(*) as total_points,
        MIN(lp.altitude) as min_altitude,
        MAX(lp.altitude) as max_altitude
    FROM (
        SELECT 
            lp.session_id,
            lp.altitude,
            lp.timestamp,
            LAG(lp.altitude) OVER (
                PARTITION BY lp.session_id 
                ORDER BY lp.timestamp
            ) as prev_altitude
        FROM location_point lp
        INNER JOIN sessions_without_elevation swe ON lp.session_id = swe.session_id
        WHERE lp.altitude IS NOT NULL
          AND lp.altitude BETWEEN -500 AND 9000  -- Reasonable altitude range
        ORDER BY lp.session_id, lp.timestamp
    ) lp
    WHERE prev_altitude IS NOT NULL  -- Skip first point of each session
    GROUP BY lp.session_id
)

-- Step 3: Preview the calculations before applying
SELECT 
    'PREVIEW' as action,
    rs.id as session_id,
    rs.user_id,
    rs.completed_at,
    rs.duration_seconds,
    ROUND((rs.duration_seconds / 60.0)::numeric, 1) as duration_minutes,
    rs.distance_km,
    -- Current elevation data
    rs.elevation_gain_m as current_elevation_m,
    -- Calculated elevation data
    ROUND(ec.calculated_elevation_gain_m::numeric, 1) as new_elevation_gain_m,
    ROUND(ec.calculated_elevation_loss_m::numeric, 1) as new_elevation_loss_m,
    ROUND((ec.calculated_elevation_gain_m * 3.28084)::numeric, 0) as new_elevation_gain_ft,
    ROUND((ec.calculated_elevation_loss_m * 3.28084)::numeric, 0) as new_elevation_loss_ft,
    ec.total_points,
    ROUND(ec.min_altitude::numeric, 1) as min_altitude_m,
    ROUND(ec.max_altitude::numeric, 1) as max_altitude_m,
    ROUND((ec.max_altitude - ec.min_altitude)::numeric, 1) as total_elevation_range_m
FROM elevation_calculations ec
INNER JOIN ruck_session rs ON ec.session_id = rs.id
WHERE ec.calculated_elevation_gain_m > 0  -- Only show sessions with measurable elevation gain
ORDER BY ec.calculated_elevation_gain_m DESC
LIMIT 50;

-- Step 4: Show summary statistics
WITH recent_sessions AS (
    SELECT rs.id as session_id
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND (rs.elevation_gain_m IS NULL OR rs.elevation_gain_m = 0)
      AND rs.duration_seconds >= 300  -- At least 5 minutes
    ORDER BY rs.completed_at DESC
    LIMIT 50
),
sessions_without_elevation AS (
    SELECT DISTINCT rs.session_id
    FROM recent_sessions rs
    INNER JOIN location_point lp ON rs.session_id = lp.session_id
),
elevation_calculations AS (
    SELECT 
        lp.session_id,
        -- Calculate elevation gain using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude > prev_altitude 
                     AND (lp.altitude - prev_altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (lp.altitude - prev_altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN lp.altitude - prev_altitude
                ELSE 0
            END
        ) as calculated_elevation_gain_m,
        -- Calculate elevation loss using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude < prev_altitude 
                     AND (prev_altitude - lp.altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (prev_altitude - lp.altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN prev_altitude - lp.altitude
                ELSE 0
            END
        ) as calculated_elevation_loss_m,
        COUNT(*) as total_points,
        MIN(lp.altitude) as min_altitude,
        MAX(lp.altitude) as max_altitude
    FROM (
        SELECT 
            lp.session_id,
            lp.altitude,
            lp.timestamp,
            LAG(lp.altitude) OVER (
                PARTITION BY lp.session_id 
                ORDER BY lp.timestamp
            ) as prev_altitude
        FROM location_point lp
        INNER JOIN sessions_without_elevation swe ON lp.session_id = swe.session_id
        WHERE lp.altitude IS NOT NULL
          AND lp.altitude BETWEEN -500 AND 9000  -- Reasonable altitude range
        ORDER BY lp.session_id, lp.timestamp
    ) lp
    WHERE prev_altitude IS NOT NULL  -- Skip first point of each session
    GROUP BY lp.session_id
)
SELECT 
    'SUMMARY' as action,
    COUNT(*) as sessions_found,
    COUNT(CASE WHEN ec.calculated_elevation_gain_m > 0 THEN 1 END) as sessions_with_elevation,
    ROUND(AVG(ec.calculated_elevation_gain_m)::numeric, 1) as avg_elevation_gain_m,
    ROUND(AVG(ec.calculated_elevation_loss_m)::numeric, 1) as avg_elevation_loss_m,
    ROUND(MIN(ec.calculated_elevation_gain_m)::numeric, 1) as min_elevation_gain_m,
    ROUND(MAX(ec.calculated_elevation_gain_m)::numeric, 1) as max_elevation_gain_m,
    ROUND(AVG(ec.total_points)::numeric, 0) as avg_points_per_session
FROM elevation_calculations ec
WHERE ec.calculated_elevation_gain_m > 0;

-- Step 5: Apply the elevation backfill (UNCOMMENT TO EXECUTE)
/*
WITH recent_sessions AS (
    SELECT rs.id as session_id
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND (rs.elevation_gain_m IS NULL OR rs.elevation_gain_m = 0)
      AND rs.duration_seconds >= 300  -- At least 5 minutes
    ORDER BY rs.completed_at DESC
    LIMIT 50
),
sessions_without_elevation AS (
    SELECT DISTINCT rs.session_id
    FROM recent_sessions rs
    INNER JOIN location_point lp ON rs.session_id = lp.session_id
),
elevation_calculations AS (
    SELECT 
        lp.session_id,
        -- Calculate elevation gain using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude > prev_altitude 
                     AND (lp.altitude - prev_altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (lp.altitude - prev_altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN lp.altitude - prev_altitude
                ELSE 0
            END
        ) as calculated_elevation_gain_m,
        -- Calculate elevation loss using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude < prev_altitude 
                     AND (prev_altitude - lp.altitude) > 0.5  -- Filter minor noise < 0.5m
                     AND (prev_altitude - lp.altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN prev_altitude - lp.altitude
                ELSE 0
            END
        ) as calculated_elevation_loss_m,
        COUNT(*) as total_points,
        MIN(lp.altitude) as min_altitude,
        MAX(lp.altitude) as max_altitude
    FROM (
        SELECT 
            lp.session_id,
            lp.altitude,
            lp.timestamp,
            LAG(lp.altitude) OVER (
                PARTITION BY lp.session_id 
                ORDER BY lp.timestamp
            ) as prev_altitude
        FROM location_point lp
        INNER JOIN sessions_without_elevation swe ON lp.session_id = swe.session_id
        WHERE lp.altitude IS NOT NULL
          AND lp.altitude BETWEEN -500 AND 9000  -- Reasonable altitude range
        ORDER BY lp.session_id, lp.timestamp
    ) lp
    WHERE prev_altitude IS NOT NULL  -- Skip first point of each session
    GROUP BY lp.session_id
)
UPDATE ruck_session 
SET 
    elevation_gain_m = ROUND(ec.calculated_elevation_gain_m::numeric, 1),
    elevation_loss_m = ROUND(ec.calculated_elevation_loss_m::numeric, 1)
FROM elevation_calculations ec
WHERE ruck_session.id = ec.session_id
  AND ruck_session.status = 'completed'
  AND ec.calculated_elevation_gain_m > 0;
*/

-- Step 6: Verification query (UNCOMMENT TO EXECUTE AFTER UPDATE)
/*
SELECT 
    'VERIFICATION' as action,
    COUNT(*) as total_sessions_updated,
    ROUND(AVG(elevation_gain_m)::numeric, 1) as avg_elevation_gain_m,
    ROUND(MIN(elevation_gain_m)::numeric, 1) as min_elevation_gain_m,
    ROUND(MAX(elevation_gain_m)::numeric, 1) as max_elevation_gain_m,
    COUNT(CASE WHEN elevation_gain_m > 100 THEN 1 END) as sessions_over_100m,
    COUNT(CASE WHEN elevation_gain_m > 500 THEN 1 END) as sessions_over_500m
FROM ruck_session rs
WHERE rs.updated_at >= NOW() - INTERVAL '5 minutes'
  AND rs.elevation_gain_m IS NOT NULL
  AND rs.status = 'completed';
*/

-- Step 7: Find sessions that still need elevation data after this script
/*
SELECT 
    'STILL_MISSING' as action,
    COUNT(*) as sessions_still_without_elevation
FROM ruck_session rs
WHERE rs.status = 'completed'
  AND (rs.elevation_gain_m IS NULL OR rs.elevation_gain_m = 0)
  AND rs.duration_seconds >= 300
  AND EXISTS (
      SELECT 1 FROM location_point lp 
      WHERE lp.session_id = rs.id 
      AND lp.altitude IS NOT NULL
  );
*/
