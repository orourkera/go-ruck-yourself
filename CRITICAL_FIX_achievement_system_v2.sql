-- CRITICAL FIX v2: Achievement System - Fix Short Session Awards
-- This script removes achievements awarded for extremely short sessions
-- and adds validation to prevent future issues

-- Step 1: Identify achievements awarded for sessions under 5 minutes OR under 500 meters
SELECT 
    ua.id,
    ua.user_id,
    u.username,
    ua.achievement_id,
    a.name as achievement_name,
    ua.session_id,
    rs.duration_seconds,
    rs.distance_km,
    ua.earned_at,
    ua.metadata
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
WHERE 
    -- Find achievements awarded for sessions that are too short
    rs.duration_seconds < 300 OR  -- Less than 5 minutes
    rs.distance_km < 0.5          -- Less than 500 meters
ORDER BY ua.earned_at DESC;

-- Step 2: DELETE achievements for sessions that are too short
-- WARNING: This will delete achievements that were awarded for invalid sessions
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN ruck_session rs ON ua.session_id = rs.id
    WHERE 
        rs.duration_seconds < 300 OR  -- Less than 5 minutes
        rs.distance_km < 0.5          -- Less than 500 meters
);

-- Step 3: Identify users who got more than 5 achievements from a single session
SELECT 
    ua.user_id,
    ua.session_id,
    COUNT(*) as achievement_count,
    STRING_AGG(a.name, ', ') as achievement_names,
    MIN(rs.duration_seconds) as session_duration,
    MIN(rs.distance_km) as session_distance
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
GROUP BY ua.user_id, ua.session_id
HAVING COUNT(*) > 5
ORDER BY achievement_count DESC;

-- Step 4: Remove excess achievements (keep only first 5 per session)
WITH ranked_achievements AS (
    SELECT 
        ua.id,
        ua.user_id,
        ua.session_id,
        ROW_NUMBER() OVER (PARTITION BY ua.user_id, ua.session_id ORDER BY ua.earned_at) as rank
    FROM user_achievements ua
)
DELETE FROM user_achievements
WHERE id IN (
    SELECT id 
    FROM ranked_achievements 
    WHERE rank > 5
);

-- Step 5: Verification queries
-- Check remaining achievements for the problematic user
SELECT 
    ua.id,
    ua.user_id,
    ua.achievement_id,
    a.name as achievement_name,
    ua.session_id,
    rs.duration_seconds,
    rs.distance_km,
    ua.earned_at
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
WHERE ua.user_id = '27264fea-0b23-4e16-93d3-31bed3871b5c'
ORDER BY ua.earned_at DESC;

-- Check for any remaining sessions with multiple achievements
SELECT 
    ua.session_id,
    COUNT(*) as achievement_count
FROM user_achievements ua
GROUP BY ua.session_id
HAVING COUNT(*) > 3
ORDER BY achievement_count DESC
LIMIT 10;
