-- Check rucks completed today to verify distance is being saved
-- July 28, 2025

-- Query 1: Sessions completed today with completed_at timestamp
SELECT 
    id,
    user_id,
    status,
    distance_km,
    duration_seconds,
    average_pace,
    calories_burned,
    elevation_gain_m,
    ruck_weight_kg,
    started_at,
    completed_at,
    is_public,
    created_at,
    updated_at
FROM ruck_session 
WHERE status = 'completed'
  AND DATE(completed_at) = '2025-07-28'
ORDER BY completed_at DESC;

-- Query 2: Sessions with status completed but check by updated_at in case completed_at is missing
SELECT 
    id,
    user_id,
    status,
    distance_km,
    duration_seconds,
    average_pace,
    calories_burned,
    elevation_gain_m,
    ruck_weight_kg,
    started_at,
    completed_at,
    is_public,
    created_at,
    updated_at
FROM ruck_session 
WHERE status = 'completed'
  AND DATE(updated_at) = '2025-07-28'
ORDER BY updated_at DESC;

-- Query 3: Specific check for sessions with missing distance but completed status today
SELECT 
    id,
    user_id,
    status,
    distance_km,
    duration_seconds,
    average_pace,
    started_at,
    completed_at,
    CASE 
        WHEN distance_km IS NULL THEN 'MISSING DISTANCE' 
        WHEN distance_km = 0 THEN 'ZERO DISTANCE'
        ELSE 'HAS DISTANCE'
    END as distance_status
FROM ruck_session 
WHERE status = 'completed'
  AND (DATE(completed_at) = '2025-07-28' OR DATE(updated_at) = '2025-07-28')
ORDER BY COALESCE(completed_at, updated_at) DESC;
