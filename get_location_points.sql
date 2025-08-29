-- Get location points for a ruck session using the same intelligent sampling as the homepage RPC
-- This uses the get_intelligent_route_points function for optimal performance

-- Replace SESSION_ID with the actual session ID you want to query
-- Example: SELECT * FROM get_location_points(2525);

-- Option 1: Intelligent sampling (simplified version without custom function)
WITH session_info AS (
    SELECT 
        id,
        distance_km,
        (SELECT COUNT(*) FROM location_point WHERE session_id = id) as total_points
    FROM ruck_session 
    WHERE id = 2525  -- Replace with your session ID
),
sampling_params AS (
    SELECT 
        *,
        -- Calculate target points based on distance (same logic as the function)
        CASE 
            WHEN distance_km IS NULL OR distance_km < 1 THEN 60
            WHEN distance_km <= 2 THEN 80
            WHEN distance_km <= 5 THEN 150
            WHEN distance_km <= 10 THEN 250
            WHEN distance_km <= 15 THEN 350
            WHEN distance_km <= 21 THEN 450
            ELSE 500
        END as target_points,
        -- Calculate sampling interval
        GREATEST(1, total_points / 
            CASE 
                WHEN distance_km IS NULL OR distance_km < 1 THEN 60
                WHEN distance_km <= 2 THEN 80
                WHEN distance_km <= 5 THEN 150
                WHEN distance_km <= 10 THEN 250
                WHEN distance_km <= 15 THEN 350
                WHEN distance_km <= 21 THEN 450
                ELSE 500
            END
        ) as sampling_interval
    FROM session_info
),
numbered_points AS (
    SELECT 
        lp.session_id,
        lp.latitude,
        lp.longitude,
        lp."timestamp",
        ROW_NUMBER() OVER (ORDER BY lp."timestamp") as row_num,
        COUNT(*) OVER () as total_count,
        sp.target_points,
        sp.sampling_interval
    FROM location_point lp
    CROSS JOIN sampling_params sp
    WHERE lp.session_id = 2525  -- Replace with your session ID
    ORDER BY lp."timestamp"
)
SELECT 
    session_id,
    latitude,
    longitude,
    "timestamp",
    0.0 as cumulative_distance  -- Placeholder for cumulative distance
FROM numbered_points
WHERE 
    -- Always include first point (start of route)
    row_num = 1 
    -- Always include last point (end of route)  
    OR row_num = total_count
    -- Sample middle points at calculated interval
    OR (row_num > 1 AND row_num < total_count AND (row_num - 1) % sampling_interval = 0)
ORDER BY "timestamp"
LIMIT (SELECT target_points FROM sampling_params);

-- Option 2: Get all raw location points (for detailed analysis)
SELECT 
    session_id,
    latitude,
    longitude,
    altitude,
    "timestamp",
    accuracy,
    speed,
    heading,
    vertical_accuracy,
    speed_accuracy,
    heading_accuracy
FROM location_point 
WHERE session_id = 2525  -- Replace with your session ID
ORDER BY "timestamp";

-- Option 3: Get session info with location point count
SELECT 
    rs.id as session_id,
    rs.user_id,
    rs.distance_km,
    rs.duration_seconds,
    rs.elevation_gain_m,
    rs.elevation_loss_m,
    rs.calories_burned,
    rs.average_pace,
    rs.completed_at,
    (SELECT COUNT(*) FROM location_point WHERE session_id = rs.id) as total_location_points,
    (SELECT COUNT(*) FROM location_point WHERE session_id = rs.id) as total_location_points
FROM ruck_session rs
WHERE rs.id = 2525  -- Replace with your session ID;

-- Option 4: Get location points with session metadata
WITH session_data AS (
    SELECT 
        id,
        distance_km,
        duration_seconds,
        elevation_gain_m,
        elevation_loss_m
    FROM ruck_session 
    WHERE id = 2525  -- Replace with your session ID
)
SELECT 
    lp.session_id,
    lp.latitude,
    lp.longitude,
    lp.altitude,
    lp."timestamp",
    lp.accuracy,
    lp.speed,
    lp.heading,
    -- Calculate cumulative distance using Haversine formula
    SUM(
        CASE 
            WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                -- Haversine formula for distance in meters
                6371000 * 2 * ASIN(
                    SQRT(
                        POWER(SIN(RADIANS(lp.latitude - prev_lat) / 2), 2) +
                        COS(RADIANS(prev_lat)) * COS(RADIANS(lp.latitude)) *
                        POWER(SIN(RADIANS(lp.longitude - prev_lng) / 2), 2)
                    )
                )
            ELSE 0
        END
    ) OVER (ORDER BY lp."timestamp") as cumulative_distance_meters,
    -- Session metadata
    sd.distance_km as session_distance_km,
    sd.duration_seconds as session_duration_seconds,
    sd.elevation_gain_m as session_elevation_gain_m,
    sd.elevation_loss_m as session_elevation_loss_m
FROM location_point lp
CROSS JOIN session_data sd
LEFT JOIN LATERAL (
    SELECT 
        LAG(latitude) OVER (ORDER BY "timestamp") as prev_lat,
        LAG(longitude) OVER (ORDER BY "timestamp") as prev_lng
    FROM location_point 
    WHERE session_id = lp.session_id
) prev ON true
WHERE lp.session_id = 2525  -- Replace with your session ID
ORDER BY lp."timestamp";

-- Option 5: Get location points with elevation analysis
SELECT 
    lp.session_id,
    lp.latitude,
    lp.longitude,
    lp.altitude,
    lp."timestamp",
    -- Calculate elevation change from previous point
    CASE 
        WHEN prev_alt IS NOT NULL THEN lp.altitude - prev_alt
        ELSE 0
    END as elevation_change_m,
    -- Calculate cumulative elevation gain
    SUM(
        CASE 
            WHEN prev_alt IS NOT NULL AND lp.altitude > prev_alt THEN lp.altitude - prev_alt
            ELSE 0
        END
    ) OVER (ORDER BY lp."timestamp") as cumulative_elevation_gain_m,
    -- Calculate cumulative elevation loss
    SUM(
        CASE 
            WHEN prev_alt IS NOT NULL AND lp.altitude < prev_alt THEN prev_alt - lp.altitude
            ELSE 0
        END
    ) OVER (ORDER BY lp."timestamp") as cumulative_elevation_loss_m,
    -- Calculate grade percentage
    CASE 
        WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL AND prev_alt IS NOT NULL THEN
            -- Calculate horizontal distance
            (6371000 * 2 * ASIN(
                SQRT(
                    POWER(SIN(RADIANS(lp.latitude - prev_lat) / 2), 2) +
                    COS(RADIANS(prev_lat)) * COS(RADIANS(lp.latitude)) *
                    POWER(SIN(RADIANS(lp.longitude - prev_lng) / 2), 2)
                )
            )) as horizontal_distance_m
        ELSE NULL
    END as horizontal_distance_m,
    -- Calculate grade percentage
    CASE 
        WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL AND prev_alt IS NOT NULL THEN
            (lp.altitude - prev_alt) / 
            (6371000 * 2 * ASIN(
                SQRT(
                    POWER(SIN(RADIANS(lp.latitude - prev_lat) / 2), 2) +
                    COS(RADIANS(prev_lat)) * COS(RADIANS(lp.latitude)) *
                    POWER(SIN(RADIANS(lp.longitude - prev_lng) / 2), 2)
                )
            )) * 100
        ELSE NULL
    END as grade_percentage
FROM location_point lp
LEFT JOIN LATERAL (
    SELECT 
        LAG(latitude) OVER (ORDER BY "timestamp") as prev_lat,
        LAG(longitude) OVER (ORDER BY "timestamp") as prev_lng,
        LAG(altitude) OVER (ORDER BY "timestamp") as prev_alt
    FROM location_point 
    WHERE session_id = lp.session_id
) prev ON true
WHERE lp.session_id = 2525  -- Replace with your session ID
ORDER BY lp."timestamp";
