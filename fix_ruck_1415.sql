-- Fix missing data for ruck session 1415
-- Check current status
SELECT 
    id,
    status,
    distance_km,
    average_pace,
    calories_burned,
    elevation_gain,
    created_at,
    start_time,
    end_time
FROM ruck_session 
WHERE id = 1415;

-- Check if it has location points
SELECT COUNT(*) as location_count
FROM location_point 
WHERE session_id = 1415;

-- Calculate missing metrics from GPS data
WITH route_calculations AS (
    SELECT 
        session_id,
        COUNT(*) as point_count,
        
        -- Calculate total distance using haversine formula
        SUM(
            CASE 
                WHEN LAG(latitude) OVER (ORDER BY timestamp) IS NOT NULL THEN
                    6371000 * 2 * ASIN(SQRT(
                        SIN(RADIANS(latitude - LAG(latitude) OVER (ORDER BY timestamp)) / 2) ^ 2 +
                        COS(RADIANS(LAG(latitude) OVER (ORDER BY timestamp))) * 
                        COS(RADIANS(latitude)) * 
                        SIN(RADIANS(longitude - LAG(longitude) OVER (ORDER BY timestamp)) / 2) ^ 2
                    ))
                ELSE 0 
            END
        ) as calculated_distance,
        
        -- Calculate elevation gain
        SUM(
            CASE 
                WHEN LAG(altitude) OVER (ORDER BY timestamp) IS NOT NULL 
                AND altitude > LAG(altitude) OVER (ORDER BY timestamp) THEN
                    altitude - LAG(altitude) OVER (ORDER BY timestamp)
                ELSE 0 
            END
        ) as elevation_gain_calc,
        
        MIN(timestamp) as route_start,
        MAX(timestamp) as route_end
    FROM location_point 
    WHERE session_id = 1415
    GROUP BY session_id
),
session_info AS (
    SELECT 
        id,
        start_time,
        end_time,
        EXTRACT(EPOCH FROM (end_time - start_time)) as duration_seconds
    FROM ruck_session 
    WHERE id = 1415
)
SELECT 
    rc.session_id,
    rc.point_count,
    ROUND(rc.calculated_distance, 2) as distance_meters,
    ROUND(rc.calculated_distance / 1000, 2) as distance_km,
    ROUND(rc.elevation_gain_calc, 2) as elevation_gain_meters,
    ROUND(rc.elevation_gain_calc * 3.28084, 2) as elevation_gain_feet,
    si.duration_seconds,
    
    -- Calculate average pace (seconds per km)
    CASE 
        WHEN rc.calculated_distance > 0 THEN
            ROUND((si.duration_seconds / (rc.calculated_distance / 1000)), 2)
        ELSE NULL 
    END as average_pace_seconds_per_km,
    
    -- Estimate calories (rough calculation: 100 cal per mile + 50 cal per 100ft elevation)
    CASE 
        WHEN rc.calculated_distance > 0 THEN
            ROUND(
                100 * (rc.calculated_distance / 1609.34) + 
                50 * (rc.elevation_gain_calc * 3.28084 / 100), 
                0
            )
        ELSE NULL 
    END as estimated_calories
FROM route_calculations rc
JOIN session_info si ON rc.session_id = si.id;

-- Update the session with calculated metrics
UPDATE ruck_session 
SET 
    distance_km = (
        SELECT ROUND(
            SUM(
                CASE 
                    WHEN LAG(latitude) OVER (ORDER BY timestamp) IS NOT NULL THEN
                        6371000 * 2 * ASIN(SQRT(
                            SIN(RADIANS(latitude - LAG(latitude) OVER (ORDER BY timestamp)) / 2) ^ 2 +
                            COS(RADIANS(LAG(latitude) OVER (ORDER BY timestamp))) * 
                            COS(RADIANS(latitude)) * 
                            SIN(RADIANS(longitude - LAG(longitude) OVER (ORDER BY timestamp)) / 2) ^ 2
                        ))
                    ELSE 0 
                END
            ) / 1000, 2
        )
        FROM location_point 
        WHERE session_id = 1415
    ),
    average_pace = (
        SELECT 
            CASE 
                WHEN SUM(
                    CASE 
                        WHEN LAG(latitude) OVER (ORDER BY timestamp) IS NOT NULL THEN
                            6371000 * 2 * ASIN(SQRT(
                                SIN(RADIANS(latitude - LAG(latitude) OVER (ORDER BY timestamp)) / 2) ^ 2 +
                                COS(RADIANS(LAG(latitude) OVER (ORDER BY timestamp))) * 
                                COS(RADIANS(latitude)) * 
                                SIN(RADIANS(longitude - LAG(longitude) OVER (ORDER BY timestamp)) / 2) ^ 2
                            ))
                        ELSE 0 
                    END
                ) > 0 THEN
                    ROUND(
                        (EXTRACT(EPOCH FROM (end_time - start_time)) / 
                         (SUM(
                            CASE 
                                WHEN LAG(latitude) OVER (ORDER BY timestamp) IS NOT NULL THEN
                                    6371000 * 2 * ASIN(SQRT(
                                        SIN(RADIANS(latitude - LAG(latitude) OVER (ORDER BY timestamp)) / 2) ^ 2 +
                                        COS(RADIANS(LAG(latitude) OVER (ORDER BY timestamp))) * 
                                        COS(RADIANS(latitude)) * 
                                        SIN(RADIANS(longitude - LAG(longitude) OVER (ORDER BY timestamp)) / 2) ^ 2
                                    ))
                                ELSE 0 
                            END
                         ) / 1000)), 2
                    )
                ELSE NULL 
            END
        FROM location_point 
        WHERE session_id = 1415
    ),
    calories_burned = (
        SELECT 
            ROUND(
                100 * (SUM(
                    CASE 
                        WHEN LAG(latitude) OVER (ORDER BY timestamp) IS NOT NULL THEN
                            6371000 * 2 * ASIN(SQRT(
                                SIN(RADIANS(latitude - LAG(latitude) OVER (ORDER BY timestamp)) / 2) ^ 2 +
                                COS(RADIANS(LAG(latitude) OVER (ORDER BY timestamp))) * 
                                COS(RADIANS(latitude)) * 
                                SIN(RADIANS(longitude - LAG(longitude) OVER (ORDER BY timestamp)) / 2) ^ 2
                            ))
                        ELSE 0 
                    END
                ) / 1609.34) + 
                50 * (SUM(
                    CASE 
                        WHEN LAG(altitude) OVER (ORDER BY timestamp) IS NOT NULL 
                        AND altitude > LAG(altitude) OVER (ORDER BY timestamp) THEN
                            altitude - LAG(altitude) OVER (ORDER BY timestamp)
                        ELSE 0 
                    END
                ) * 3.28084 / 100), 
                0
            )
        FROM location_point 
        WHERE session_id = 1415
    ),
    elevation_gain = (
        SELECT ROUND(
            SUM(
                CASE 
                    WHEN LAG(altitude) OVER (ORDER BY timestamp) IS NOT NULL 
                    AND altitude > LAG(altitude) OVER (ORDER BY timestamp) THEN
                        altitude - LAG(altitude) OVER (ORDER BY timestamp)
                    ELSE 0 
                END
            ), 2
        )
        FROM location_point 
        WHERE session_id = 1415
    )
WHERE id = 1415;

-- Verify the update
SELECT 
    id,
    status,
    ROUND(distance_km, 2) as distance_km,
    ROUND(distance_km * 0.621371, 2) as distance_miles,
    average_pace as pace_sec_per_km,
    calories_burned,
    ROUND(elevation_gain, 2) as elevation_gain_meters,
    ROUND(elevation_gain * 3.28084, 2) as elevation_gain_feet,
    created_at,
    start_time,
    end_time
FROM ruck_session 
WHERE id = 1415;
