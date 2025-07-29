-- Find all completed sessions with significant duration but missing key data
-- This identifies the scope of the data loss issue

-- Main query: Sessions with significant duration (>= 10 minutes) but missing distance/pace
SELECT 
    id as session_id,
    user_id,
    status,
    duration_seconds,
    ROUND((duration_seconds / 60.0)::numeric, 1) as duration_minutes,
    distance_km,
    average_pace,
    calories_burned,
    elevation_gain_m,
    ruck_weight_kg,
    started_at,
    completed_at,
    is_public,
    created_at,
    updated_at,
    -- Data completeness flags
    CASE WHEN distance_km IS NULL THEN 'MISSING' ELSE 'OK' END as distance_status,
    CASE WHEN average_pace IS NULL THEN 'MISSING' ELSE 'OK' END as pace_status,
    CASE WHEN calories_burned IS NULL THEN 'MISSING' ELSE 'OK' END as calories_status,
    CASE WHEN elevation_gain_m IS NULL THEN 'MISSING' ELSE 'OK' END as elevation_status,
    -- Summary score of missing data
    (CASE WHEN distance_km IS NULL THEN 1 ELSE 0 END +
     CASE WHEN average_pace IS NULL THEN 1 ELSE 0 END +
     CASE WHEN calories_burned IS NULL THEN 1 ELSE 0 END +
     CASE WHEN elevation_gain_m IS NULL THEN 1 ELSE 0 END) as missing_data_count
FROM ruck_session 
WHERE status = 'completed'
  AND duration_seconds >= 600  -- 10+ minutes
  AND (distance_km IS NULL 
       OR average_pace IS NULL 
       OR calories_burned IS NULL 
       OR elevation_gain_m IS NULL)
ORDER BY completed_at DESC NULLS LAST;

-- Summary statistics of the data loss issue
SELECT 
    COUNT(*) as total_affected_sessions,
    COUNT(CASE WHEN distance_km IS NULL THEN 1 END) as missing_distance_count,
    COUNT(CASE WHEN average_pace IS NULL THEN 1 END) as missing_pace_count,
    COUNT(CASE WHEN calories_burned IS NULL THEN 1 END) as missing_calories_count,
    COUNT(CASE WHEN elevation_gain_m IS NULL THEN 1 END) as missing_elevation_count,
    ROUND(AVG(duration_seconds / 60.0)::numeric, 1) as avg_duration_minutes,
    MIN(completed_at) as earliest_affected,
    MAX(completed_at) as latest_affected
FROM ruck_session 
WHERE status = 'completed'
  AND duration_seconds >= 600  -- 10+ minutes
  AND (distance_km IS NULL 
       OR average_pace IS NULL 
       OR calories_burned IS NULL 
       OR elevation_gain_m IS NULL);

-- Break down by date to see when this issue started
SELECT 
    DATE(completed_at) as completion_date,
    COUNT(*) as affected_sessions_count,
    COUNT(CASE WHEN distance_km IS NULL THEN 1 END) as missing_distance,
    COUNT(CASE WHEN average_pace IS NULL THEN 1 END) as missing_pace,
    ROUND(AVG(duration_seconds / 60.0)::numeric, 1) as avg_duration_minutes
FROM ruck_session 
WHERE status = 'completed'
  AND duration_seconds >= 600
  AND (distance_km IS NULL 
       OR average_pace IS NULL 
       OR calories_burned IS NULL 
       OR elevation_gain_m IS NULL)
  AND completed_at IS NOT NULL
GROUP BY DATE(completed_at)
ORDER BY completion_date DESC;

-- Compare with sessions that DO have complete data
SELECT 
    'COMPLETE DATA' as session_type,
    COUNT(*) as session_count,
    ROUND(AVG(duration_seconds / 60.0)::numeric, 1) as avg_duration_minutes,
    ROUND(AVG(distance_km)::numeric, 2) as avg_distance_km,
    MIN(completed_at) as earliest_session,
    MAX(completed_at) as latest_session
FROM ruck_session 
WHERE status = 'completed'
  AND duration_seconds >= 600
  AND distance_km IS NOT NULL 
  AND average_pace IS NOT NULL 
  AND calories_burned IS NOT NULL 
  AND elevation_gain_m IS NOT NULL

UNION ALL

SELECT 
    'INCOMPLETE DATA' as session_type,
    COUNT(*) as session_count,
    ROUND(AVG(duration_seconds / 60.0)::numeric, 1) as avg_duration_minutes,
    NULL as avg_distance_km,
    MIN(completed_at) as earliest_session,
    MAX(completed_at) as latest_session
FROM ruck_session 
WHERE status = 'completed'
  AND duration_seconds >= 600
  AND (distance_km IS NULL 
       OR average_pace IS NULL 
       OR calories_burned IS NULL 
       OR elevation_gain_m IS NULL);
