-- CRITICAL: Cleanup orphaned ruck sessions stuck in 'in_progress' status
-- These sessions are from crashed apps, dead batteries, or force-closed apps

-- 1. First, let's see what orphaned sessions we have (older than 24 hours)
SELECT 
    id,
    user_id,
    status,
    created_at,
    started_at,
    duration_seconds,
    distance_km,
    -- How long ago this session was created
    EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600 AS hours_ago
FROM ruck_session 
WHERE status = 'in_progress' 
    AND created_at < NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- 2. Check if any of these have location points recorded recently
-- (This will help us identify truly dead sessions vs active ones)
SELECT 
    rs.id as session_id,
    rs.user_id,
    rs.created_at,
    COUNT(lp.id) as location_points_count,
    MAX(lp.timestamp) as last_location_point
FROM ruck_session rs
LEFT JOIN location_point lp ON rs.id = lp.session_id
WHERE rs.status = 'in_progress' 
    AND rs.created_at < NOW() - INTERVAL '6 hours'
GROUP BY rs.id, rs.user_id, rs.created_at
ORDER BY rs.created_at DESC;

-- 3. SAFE CLEANUP: Mark very old orphaned sessions as 'cancelled'
-- Only sessions older than 12 hours with no recent location points
UPDATE ruck_session 
SET 
    status = 'cancelled',
    completed_at = NOW(),
    notes = COALESCE(notes, '') || ' [AUTO-CANCELLED: Orphaned session cleanup]'
WHERE id IN (
    SELECT rs.id 
    FROM ruck_session rs
    LEFT JOIN (
        SELECT session_id, MAX(timestamp) as last_point
        FROM location_point 
        WHERE timestamp > NOW() - INTERVAL '6 hours'
        GROUP BY session_id
    ) recent_points ON rs.id = recent_points.session_id
    WHERE rs.status = 'in_progress'
        AND rs.created_at < NOW() - INTERVAL '12 hours'
        AND recent_points.session_id IS NULL  -- No recent location points
);

-- 4. For sessions that might be legitimately active but old (6-12 hours)
-- Let's see what these look like before taking action
SELECT 
    rs.id,
    rs.user_id,
    rs.status,
    rs.created_at,
    EXTRACT(EPOCH FROM (NOW() - rs.created_at)) / 3600 AS hours_ago,
    COUNT(lp.id) as total_points,
    MAX(lp.timestamp) as last_location,
    EXTRACT(EPOCH FROM (NOW() - MAX(lp.timestamp))) / 3600 AS hours_since_last_location
FROM ruck_session rs
LEFT JOIN location_point lp ON rs.id = lp.session_id
WHERE rs.status = 'in_progress' 
    AND rs.created_at < NOW() - INTERVAL '6 hours'
    AND rs.created_at > NOW() - INTERVAL '12 hours'
GROUP BY rs.id, rs.user_id, rs.status, rs.created_at
ORDER BY rs.created_at DESC;

-- 5. Check what we cleaned up
SELECT COUNT(*) as cancelled_sessions 
FROM ruck_session 
WHERE status = 'cancelled' 
    AND notes LIKE '%AUTO-CANCELLED: Orphaned session cleanup%';
