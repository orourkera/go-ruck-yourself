-- Analyze GPS data quality for session 2862
-- Check for potential distance calculation discrepancies

-- 1. Basic session info
SELECT 
    id,
    distance_km as app_distance,
    elevation_gain_m,
    elevation_loss_m,
    duration_seconds,
    started_at,
    completed_at
FROM sessions 
WHERE id = 2862;

-- 2. Location points analysis for session 2862
SELECT 
    COUNT(*) as total_points,
    MIN(timestamp) as first_point,
    MAX(timestamp) as last_point,
    AVG(altitude) as avg_altitude,
    MIN(altitude) as min_altitude,
    MAX(altitude) as max_altitude
FROM location_point 
WHERE session_id = 2862
ORDER BY timestamp;

-- 3. Distance between consecutive points analysis
WITH point_distances AS (
    SELECT 
        lp1.timestamp as t1,
        lp2.timestamp as t2,
        lp1.latitude as lat1,
        lp1.longitude as lon1,
        lp2.latitude as lat2, 
        lp2.longitude as lon2,
        lp1.altitude as alt1,
        lp2.altitude as alt2,
        -- Calculate distance using Haversine formula (similar to Geolocator.distanceBetween)
        6371000 * 2 * ASIN(SQRT(
            POWER(SIN(RADIANS(lp2.latitude - lp1.latitude) / 2), 2) +
            COS(RADIANS(lp1.latitude)) * COS(RADIANS(lp2.latitude)) *
            POWER(SIN(RADIANS(lp2.longitude - lp1.longitude) / 2), 2)
        )) as distance_m,
        EXTRACT(EPOCH FROM (lp2.timestamp - lp1.timestamp)) as time_diff_sec
    FROM location_point lp1
    JOIN location_point lp2 ON lp2.session_id = lp1.session_id 
    WHERE lp1.session_id = 2862
    AND lp2.timestamp > lp1.timestamp
    AND NOT EXISTS (
        SELECT 1 FROM location_point lp3 
        WHERE lp3.session_id = lp1.session_id 
        AND lp3.timestamp > lp1.timestamp 
        AND lp3.timestamp < lp2.timestamp
    )
    ORDER BY lp1.timestamp
)
SELECT 
    COUNT(*) as total_segments,
    ROUND(SUM(distance_m)::numeric, 2) as total_distance_m,
    ROUND((SUM(distance_m) / 1000)::numeric, 3) as total_distance_km,
    ROUND(AVG(distance_m)::numeric, 2) as avg_segment_distance_m,
    ROUND(MAX(distance_m)::numeric, 2) as max_segment_distance_m,
    COUNT(CASE WHEN distance_m > 100 THEN 1 END) as segments_over_100m,
    COUNT(CASE WHEN time_diff_sec > 0 AND (distance_m / time_diff_sec) > 4.5 THEN 1 END) as segments_over_4_5_mps,
    COUNT(CASE WHEN time_diff_sec < 1 THEN 1 END) as segments_under_1sec,
    -- App filtering simulation
    COUNT(CASE WHEN distance_m < 100 AND time_diff_sec >= 1 THEN 1 END) as app_accepted_segments,
    ROUND(SUM(CASE WHEN distance_m < 100 AND time_diff_sec >= 1 THEN distance_m ELSE 0 END)::numeric, 2) as app_filtered_distance_m,
    ROUND((SUM(CASE WHEN distance_m < 100 AND time_diff_sec >= 1 THEN distance_m ELSE 0 END) / 1000)::numeric, 3) as app_filtered_distance_km
FROM point_distances;

-- 4. Sample problematic segments (if any)
WITH point_distances AS (
    SELECT 
        lp1.timestamp as t1,
        lp2.timestamp as t2,
        lp1.latitude as lat1,
        lp1.longitude as lon1,
        lp2.latitude as lat2, 
        lp2.longitude as lon2,
        6371000 * 2 * ASIN(SQRT(
            POWER(SIN(RADIANS(lp2.latitude - lp1.latitude) / 2), 2) +
            COS(RADIANS(lp1.latitude)) * COS(RADIANS(lp2.latitude)) *
            POWER(SIN(RADIANS(lp2.longitude - lp1.longitude) / 2), 2)
        )) as distance_m,
        EXTRACT(EPOCH FROM (lp2.timestamp - lp1.timestamp)) as time_diff_sec
    FROM location_point lp1
    JOIN location_point lp2 ON lp2.session_id = lp1.session_id 
    WHERE lp1.session_id = 2862
    AND lp2.timestamp > lp1.timestamp
    AND NOT EXISTS (
        SELECT 1 FROM location_point lp3 
        WHERE lp3.session_id = lp1.session_id 
        AND lp3.timestamp > lp1.timestamp 
        AND lp3.timestamp < lp2.timestamp
    )
    ORDER BY lp1.timestamp
)
SELECT 
    t1,
    t2,
    ROUND(distance_m::numeric, 2) as distance_m,
    time_diff_sec,
    CASE 
        WHEN time_diff_sec > 0 THEN ROUND((distance_m / time_diff_sec)::numeric, 2)
        ELSE NULL
    END as speed_mps,
    CASE 
        WHEN distance_m > 100 THEN 'TOO_LONG'
        WHEN time_diff_sec < 1 THEN 'TOO_FAST_TIME'
        WHEN time_diff_sec > 0 AND (distance_m / time_diff_sec) > 4.5 THEN 'TOO_FAST_SPEED'
        ELSE 'ACCEPTED'
    END as filter_result
FROM point_distances
WHERE distance_m > 100 OR time_diff_sec < 1 OR (time_diff_sec > 0 AND (distance_m / time_diff_sec) > 4.5)
ORDER BY distance_m DESC
LIMIT 10;
