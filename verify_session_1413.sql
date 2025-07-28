-- Verify session 1413 (your ruck) was properly restored
SELECT 
    id as session_id,
    user_id,
    status,
    duration_seconds,
    ROUND((duration_seconds / 60.0)::numeric, 1) as duration_minutes,
    distance_km,
    ROUND((distance_km * 0.621371)::numeric, 2) as distance_miles,
    average_pace as pace_min_per_km,
    calories_burned,
    elevation_gain_m,
    ruck_weight_kg,
    ROUND((ruck_weight_kg * 2.20462)::numeric, 1) as ruck_weight_lbs,
    started_at,
    completed_at,
    is_public
FROM ruck_session 
WHERE id = 1413;
