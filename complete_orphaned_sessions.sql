-- Complete orphaned ruck sessions using proper distance calculation
-- If last location point was saved more than 1 hour ago, mark session as completed

-- Step 1: Identify orphaned sessions (sessions with location data but inactive for 1+ hours)
SELECT 
    rs.id,
    rs.status,
    rs.started_at,
    rs.distance_km,
    rs.duration_seconds,
    rs.completed_at,
    MAX(lp.timestamp) as last_location_timestamp,
    EXTRACT(EPOCH FROM (NOW() - MAX(lp.timestamp)))/3600 as hours_since_last_location,
    COUNT(lp.id) as total_location_points
FROM ruck_session rs
LEFT JOIN location_point lp ON rs.id = lp.session_id
WHERE rs.status = 'in_progress'
GROUP BY rs.id, rs.status, rs.started_at, rs.distance_km, rs.duration_seconds, rs.completed_at
HAVING MAX(lp.timestamp) < NOW() - INTERVAL '1 hour'
   AND COUNT(lp.id) > 0  -- Must have location data
ORDER BY hours_since_last_location DESC;

-- Step 2: Complete orphaned sessions with proper distance/elevation calculations
WITH orphaned_session_ids AS (
    -- Get list of sessions to complete
    SELECT rs.id
    FROM ruck_session rs
    LEFT JOIN location_point lp ON rs.id = lp.session_id
    WHERE rs.status = 'in_progress'
    GROUP BY rs.id
    HAVING MAX(lp.timestamp) < NOW() - INTERVAL '1 hour'
       AND COUNT(lp.id) > 0
),
location_distances AS (
    SELECT 
        lp.session_id,
        lp.latitude,
        lp.longitude,
        lp.altitude,
        lp.timestamp,
        LAG(lp.latitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_lat,
        LAG(lp.longitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_lng,
        LAG(lp.altitude) OVER (PARTITION BY lp.session_id ORDER BY lp.timestamp) as prev_alt
    FROM location_point lp
    INNER JOIN orphaned_session_ids osi ON lp.session_id = osi.id
),
session_stats AS (
    SELECT 
        rs.id,
        -- Get last location point timestamp
        (SELECT lp.timestamp FROM location_point lp
         WHERE lp.session_id = rs.id 
         ORDER BY lp.timestamp DESC LIMIT 1) as last_location_time,
        
        -- Calculate total distance using proper lat/lng calculation
        COALESCE((
            SELECT 
                SUM(
                    SQRT(
                        POWER(latitude - prev_lat, 2) +
                        POWER(longitude - prev_lng, 2)
                    ) * 111  -- Rough km per degree
                )
            FROM location_distances 
            WHERE session_id = rs.id 
            AND prev_lat IS NOT NULL
        ), 0) as calculated_distance_km,
        
        -- Calculate elevation gain
        COALESCE((
            SELECT 
                SUM(CASE 
                    WHEN altitude > prev_alt 
                    THEN altitude - prev_alt 
                    ELSE 0 
                END)
            FROM location_distances 
            WHERE session_id = rs.id 
            AND prev_alt IS NOT NULL
        ), 0) as elevation_gain_m
        
    FROM ruck_session rs
    INNER JOIN orphaned_session_ids osi ON rs.id = osi.id
)
UPDATE ruck_session 
SET 
    status = 'completed',
    completed_at = ss.last_location_time,
    distance_km = ss.calculated_distance_km,
    duration_seconds = EXTRACT(EPOCH FROM (ss.last_location_time - started_at))::INTEGER,
    elevation_gain_m = ss.elevation_gain_m,
    calories_burned = (EXTRACT(EPOCH FROM (ss.last_location_time - started_at)) / 60.0) * 75 * 0.5
FROM session_stats ss
WHERE ruck_session.id = ss.id;

-- Step 3: Cancel sessions with NO location data at all
WITH sessions_without_location_data AS (
    SELECT rs.id
    FROM ruck_session rs
    LEFT JOIN location_point lp ON rs.id = lp.session_id
    WHERE rs.status = 'in_progress'
      AND rs.started_at < NOW() - INTERVAL '1 hour'  -- Started more than 1 hour ago
      AND lp.id IS NULL  -- No location points at all
)
UPDATE ruck_session
SET 
    status = 'cancelled',
    completed_at = started_at,  -- End immediately since no progress
    notes = COALESCE(notes || ' | ', '') || 'Auto-cancelled: No location data recorded'
FROM sessions_without_location_data
WHERE ruck_session.id = sessions_without_location_data.id;

-- Step 4: Report final session counts and stats
SELECT 
    'SUMMARY: All Sessions Status' as report_type,
    status,
    COUNT(*) as session_count,
    AVG(COALESCE(distance_km, 0)) as avg_distance_km,
    AVG(COALESCE(duration_seconds, 0)/60.0) as avg_duration_minutes,
    AVG(COALESCE(elevation_gain_m, 0)) as avg_elevation_gain_m,
    COUNT(CASE WHEN completed_at IS NOT NULL THEN 1 END) as sessions_with_completion_time
FROM ruck_session 
GROUP BY status
ORDER BY session_count DESC;

-- Show the specific sessions that should have been completed
SELECT 
    'COMPLETED SESSIONS' as report_type,
    id,
    status,
    distance_km,
    duration_seconds/60.0 as duration_minutes,
    elevation_gain_m,
    started_at,
    completed_at
FROM ruck_session 
WHERE id IN (1279, 1280, 1289, 1287)  -- The orphaned sessions we identified
ORDER BY id;
