-- Check for distance discrepancies between stored and calculated distances
-- Shows each session with percentage difference

WITH recent_sessions AS (
    -- Get the last 20 completed sessions
    SELECT 
        id,
        user_id,
        distance_km as stored_distance_km,
        duration_seconds,
        completed_at
    FROM ruck_session 
    WHERE status = 'completed'
      AND distance_km IS NOT NULL
    ORDER BY completed_at DESC
    LIMIT 20
),
calculated_distances AS (
    -- Calculate distance from location points for each session
    SELECT 
        lp.session_id,
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
        ) as calculated_distance_meters
    FROM (
        SELECT 
            session_id,
            latitude,
            longitude,
            timestamp,
            LAG(latitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lat,
            LAG(longitude) OVER (PARTITION BY session_id ORDER BY timestamp) as prev_lng
        FROM location_point 
        WHERE session_id IN (SELECT id FROM recent_sessions)
        ORDER BY session_id, timestamp
    ) lp
    WHERE lp.session_id IN (SELECT id FROM recent_sessions)
    GROUP BY lp.session_id
)
SELECT 
    rs.id as session_id,
    rs.user_id,
    rs.stored_distance_km as stored_km,
    ROUND((cd.calculated_distance_meters / 1000.0)::numeric, 3) as calculated_km,
    -- Calculate percentage difference
    CASE 
        WHEN cd.calculated_distance_meters IS NULL THEN NULL
        WHEN rs.stored_distance_km = 0 THEN NULL
        ELSE ROUND(((cd.calculated_distance_meters / 1000.0 - rs.stored_distance_km) / rs.stored_distance_km * 100)::numeric, 1)
    END as percent_difference,
    -- Show the difference in km
    CASE 
        WHEN cd.calculated_distance_meters IS NULL THEN NULL
        ELSE ROUND((cd.calculated_distance_meters / 1000.0 - rs.stored_distance_km)::numeric, 3)
    END as difference_km,
    -- Status based on percentage difference
    CASE 
        WHEN cd.calculated_distance_meters IS NULL THEN 'NO LOCATION DATA'
        WHEN rs.stored_distance_km = 0 THEN 'ZERO STORED DISTANCE'
        WHEN ABS((cd.calculated_distance_meters / 1000.0 - rs.stored_distance_km) / rs.stored_distance_km * 100) > 20 THEN 'MAJOR DISCREPANCY (>20%)'
        WHEN ABS((cd.calculated_distance_meters / 1000.0 - rs.stored_distance_km) / rs.stored_distance_km * 100) > 10 THEN 'SIGNIFICANT DISCREPANCY (>10%)'
        WHEN ABS((cd.calculated_distance_meters / 1000.0 - rs.stored_distance_km) / rs.stored_distance_km * 100) > 5 THEN 'MINOR DISCREPANCY (>5%)'
        ELSE 'MATCH (<5%)'
    END as status,
    rs.duration_seconds,
    rs.completed_at,
    (SELECT COUNT(*) FROM location_point WHERE session_id = rs.id) as location_points
FROM recent_sessions rs
LEFT JOIN calculated_distances cd ON rs.id = cd.session_id
ORDER BY rs.completed_at DESC;


