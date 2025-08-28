-- Update sessions 2525 and 2523 with recalculated distances and adjusted metrics
-- This script recalculates distance from GPS points and adjusts pace/calories proportionally

WITH session_data AS (
    -- Get current session data
    SELECT 
        id,
        distance_km as stored_distance_km,
        average_pace as stored_pace,
        calories_burned as stored_calories,
        duration_seconds
    FROM ruck_session 
    WHERE id IN (2525, 2523)
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
        WHERE session_id IN (2525, 2523)
        ORDER BY session_id, timestamp
    ) lp
    WHERE lp.session_id IN (2525, 2523)
    GROUP BY lp.session_id
),
update_data AS (
    -- Calculate the adjustment factors and new values
    SELECT 
        sd.id,
        sd.stored_distance_km,
        sd.stored_pace,
        sd.stored_calories,
        ROUND((cd.calculated_distance_meters / 1000.0)::numeric, 3) as new_distance_km,
        -- Calculate adjustment factor (new_distance / stored_distance)
        CASE 
            WHEN sd.stored_distance_km > 0 THEN (cd.calculated_distance_meters / 1000.0) / sd.stored_distance_km
            ELSE 1.0
        END as distance_adjustment_factor,
        -- Adjust pace proportionally (pace should decrease if distance increases)
        CASE 
            WHEN sd.stored_pace IS NOT NULL AND sd.stored_distance_km > 0 THEN 
                ROUND((sd.stored_pace / ((cd.calculated_distance_meters / 1000.0) / sd.stored_distance_km))::numeric, 0)
            ELSE sd.stored_pace
        END as new_pace,
        -- Keep original calories (don't adjust - calories are based on actual work done)
        sd.stored_calories as new_calories,
        -- Calculate percentage change
        CASE 
            WHEN sd.stored_distance_km > 0 THEN 
                ROUND(((cd.calculated_distance_meters / 1000.0 - sd.stored_distance_km) / sd.stored_distance_km * 100)::numeric, 1)
            ELSE NULL
        END as percent_change
    FROM session_data sd
    LEFT JOIN calculated_distances cd ON sd.id = cd.session_id
)
-- Show what will be updated
SELECT 
    id as session_id,
    stored_distance_km,
    new_distance_km,
    percent_change,
    stored_pace,
    new_pace,
    stored_calories,
    new_calories,
    distance_adjustment_factor
FROM update_data
ORDER BY id;

-- Uncomment the UPDATE statement below to actually perform the updates
/*
UPDATE ruck_session 
SET 
    distance_km = (
        SELECT ROUND((SUM(
            CASE 
                WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                    6371000 * 2 * ASIN(
                        SQRT(
                            POWER(SIN(RADIANS(lp.latitude - prev_lat) / 2), 2) +
                            COS(RADIANS(prev_lat)) * COS(RADIANS(lp.latitude)) *
                            POWER(SIN(RADIANS(lp.longitude - prev_lng) / 2), 2)
                        )
                    )
                ELSE 0
            END
        ) / 1000.0)::numeric, 3)
        FROM (
            SELECT 
                latitude,
                longitude,
                LAG(latitude) OVER (ORDER BY timestamp) as prev_lat,
                LAG(longitude) OVER (ORDER BY timestamp) as prev_lng
            FROM location_point 
            WHERE session_id = ruck_session.id
            ORDER BY timestamp
        ) lp
    ),
    average_pace = (
        SELECT CASE 
            WHEN ruck_session.average_pace IS NOT NULL AND ruck_session.distance_km > 0 THEN 
                ROUND((ruck_session.average_pace / (
                    (SUM(
                        CASE 
                            WHEN prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
                                6371000 * 2 * ASIN(
                                    SQRT(
                                        POWER(SIN(RADIANS(lp.latitude - prev_lat) / 2), 2) +
                                        COS(RADIANS(prev_lat)) * COS(RADIANS(lp.latitude)) *
                                        POWER(SIN(RADIANS(lp.longitude - prev_lng) / 2), 2)
                                    )
                                )
                            ELSE 0
                        END
                    ) / 1000.0) / ruck_session.distance_km
                ))::numeric, 0)
            ELSE ruck_session.average_pace
        END
        FROM (
            SELECT 
                latitude,
                longitude,
                LAG(latitude) OVER (ORDER BY timestamp) as prev_lat,
                LAG(longitude) OVER (ORDER BY timestamp) as prev_lng
            FROM location_point 
            WHERE session_id = ruck_session.id
            ORDER BY timestamp
        ) lp
    )
WHERE id IN (2525, 2523);
*/
