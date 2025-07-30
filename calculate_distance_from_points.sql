-- Calculate distance from location points for sessions with missing distance_km
-- Uses haversine formula to calculate distance between GPS coordinates

-- First, let's see if we have location points for the problematic sessions
SELECT 
    session_id,
    COUNT(*) as point_count,
    MIN(timestamp) as first_point,
    MAX(timestamp) as last_point,
    ROUND(AVG(latitude)::numeric, 6) as avg_lat,
    ROUND(AVG(longitude)::numeric, 6) as avg_lng
FROM location_point 
WHERE session_id IN (1413, 1411, 1410, 1409, 1407)
GROUP BY session_id
ORDER BY session_id;

-- Calculate distance for session 1413 specifically (your 2.18 mi session)
WITH session_points AS (
    SELECT 
        session_id,
        latitude,
        longitude,
        timestamp,
        LAG(latitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lat,
        LAG(longitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lng
    FROM location_point 
    WHERE session_id = 1413
    ORDER BY timestamp
),
distances AS (
    SELECT 
        session_id,
        CASE 
            WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                -- Haversine formula in SQL (returns distance in meters)
                6371000 * 2 * ASIN(
                    SQRT(
                        POWER(SIN(RADIANS(latitude - prev_lat) / 2), 2) +
                        COS(RADIANS(prev_lat)) * COS(RADIANS(latitude)) *
                        POWER(SIN(RADIANS(longitude - prev_lng) / 2), 2)
                    )
                )
            ELSE 0
        END as segment_distance_m
    FROM session_points
    WHERE prev_lat IS NOT NULL
)
SELECT 
    session_id,
    ROUND(SUM(segment_distance_m)::numeric, 2) as total_distance_meters,
    ROUND((SUM(segment_distance_m) / 1000)::numeric, 3) as total_distance_km,
    ROUND((SUM(segment_distance_m) * 0.000621371)::numeric, 3) as total_distance_miles
FROM distances
GROUP BY session_id;

-- Calculate distances for all problematic sessions
WITH all_session_points AS (
    SELECT 
        session_id,
        latitude,
        longitude,
        timestamp,
        LAG(latitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lat,
        LAG(longitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lng
    FROM location_point 
    WHERE session_id IN (1413, 1411, 1410, 1409, 1407)
    ORDER BY session_id, timestamp
),
all_distances AS (
    SELECT 
        session_id,
        CASE 
            WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                6371000 * 2 * ASIN(
                    SQRT(
                        POWER(SIN(RADIANS(latitude - prev_lat) / 2), 2) +
                        COS(RADIANS(prev_lat)) * COS(RADIANS(latitude)) *
                        POWER(SIN(RADIANS(longitude - prev_lng) / 2), 2)
                    )
                )
            ELSE 0
        END as segment_distance_m
    FROM all_session_points
    WHERE prev_lat IS NOT NULL
)
SELECT 
    rs.id as session_id,
    rs.user_id,
    rs.duration_seconds,
    rs.distance_km as stored_distance_km,
    ROUND(SUM(ad.segment_distance_m)::numeric, 2) as calculated_distance_meters,
    ROUND((SUM(ad.segment_distance_m) / 1000)::numeric, 3) as calculated_distance_km,
    ROUND((SUM(ad.segment_distance_m) * 0.000621371)::numeric, 3) as calculated_distance_miles,
    COUNT(lp.id) as location_point_count
FROM ruck_session rs
LEFT JOIN all_distances ad ON rs.id = ad.session_id
LEFT JOIN location_point lp ON rs.id = lp.session_id
WHERE rs.id IN (1413, 1411, 1410, 1409, 1407)
GROUP BY rs.id, rs.user_id, rs.duration_seconds, rs.distance_km
ORDER BY rs.id;
