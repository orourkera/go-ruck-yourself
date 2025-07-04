-- CRITICAL ACHIEVEMENT CLEANUP SCRIPT
-- This script removes all incorrectly awarded achievements
-- Run this IMMEDIATELY to clean up the achievement system

-- Step 1: Show what we're about to delete (REVIEW FIRST)
SELECT 'SESSIONS TOO SHORT' as issue_type, COUNT(*) as count
FROM user_achievements ua
JOIN ruck_session rs ON ua.session_id = rs.id
WHERE rs.duration_seconds < 300 OR rs.distance_km < 0.5

UNION ALL

SELECT 'PACE ACHIEVEMENTS WITH INSUFFICIENT DISTANCE' as issue_type, COUNT(*) as count
FROM user_achievements ua
JOIN ruck_session rs ON ua.session_id = rs.id
JOIN achievements a ON ua.achievement_id = a.id
WHERE a.criteria->>'type' = 'pace_faster_than'
AND (
    (a.name ILIKE '%80%km%' AND rs.distance_km < 80) OR
    (a.name ILIKE '%50%km%' AND rs.distance_km < 50) OR
    (a.name ILIKE '%42%km%' AND rs.distance_km < 42) OR
    (a.name ILIKE '%20%km%' AND rs.distance_km < 20) OR
    (a.name ILIKE '%10%km%' AND rs.distance_km < 10) OR
    (a.name ILIKE '%5%km%' AND rs.distance_km < 5) OR
    (a.name ILIKE '%26%mile%' AND rs.distance_km < 42.2) OR
    (a.name ILIKE '%13%mile%' AND rs.distance_km < 21.1) OR
    (a.name ILIKE '%10%mile%' AND rs.distance_km < 16.1) OR
    (a.name ILIKE '%6%mile%' AND rs.distance_km < 9.7) OR
    (a.name ILIKE '%3%mile%' AND rs.distance_km < 4.8)
)

UNION ALL

SELECT 'EXCESS ACHIEVEMENTS PER SESSION' as issue_type, COUNT(*) as count
FROM (
    SELECT ua.session_id
    FROM user_achievements ua
    GROUP BY ua.session_id
    HAVING COUNT(*) > 5
) excess_sessions
JOIN user_achievements ua ON ua.session_id = excess_sessions.session_id;

-- Step 2: DETAILED VIEW of problematic achievements
SELECT 
    'SHORT_SESSION' as issue,
    ua.id,
    ua.user_id,
    u.username,
    a.name as achievement_name,
    ua.session_id,
    rs.duration_seconds,
    rs.distance_km,
    ua.earned_at
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
WHERE rs.duration_seconds < 300 OR rs.distance_km < 0.5

UNION ALL

SELECT 
    'PACE_INSUFFICIENT_DISTANCE' as issue,
    ua.id,
    ua.user_id,
    u.username,
    a.name as achievement_name,
    ua.session_id,
    rs.duration_seconds,
    rs.distance_km,
    ua.earned_at
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
WHERE a.criteria->>'type' = 'pace_faster_than'
AND (
    (a.name ILIKE '%80%km%' AND rs.distance_km < 80) OR
    (a.name ILIKE '%50%km%' AND rs.distance_km < 50) OR
    (a.name ILIKE '%42%km%' AND rs.distance_km < 42) OR
    (a.name ILIKE '%20%km%' AND rs.distance_km < 20) OR
    (a.name ILIKE '%10%km%' AND rs.distance_km < 10) OR
    (a.name ILIKE '%5%km%' AND rs.distance_km < 5) OR
    (a.name ILIKE '%26%mile%' AND rs.distance_km < 42.2) OR
    (a.name ILIKE '%13%mile%' AND rs.distance_km < 21.1) OR
    (a.name ILIKE '%10%mile%' AND rs.distance_km < 16.1) OR
    (a.name ILIKE '%6%mile%' AND rs.distance_km < 9.7) OR
    (a.name ILIKE '%3%mile%' AND rs.distance_km < 4.8)
)
ORDER BY earned_at DESC;

-- Step 3: DELETE achievements for sessions that are too short
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN ruck_session rs ON ua.session_id = rs.id
    WHERE rs.duration_seconds < 300 OR rs.distance_km < 0.5
);

-- Step 4: DELETE pace achievements with insufficient distance
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN achievements a ON ua.achievement_id = a.id
    JOIN ruck_session rs ON ua.session_id = rs.id
    WHERE a.criteria->>'type' = 'pace_faster_than'
    AND (
        (a.name ILIKE '%80%km%' AND rs.distance_km < 80) OR
        (a.name ILIKE '%50%km%' AND rs.distance_km < 50) OR
        (a.name ILIKE '%42%km%' AND rs.distance_km < 42) OR
        (a.name ILIKE '%20%km%' AND rs.distance_km < 20) OR
        (a.name ILIKE '%10%km%' AND rs.distance_km < 10) OR
        (a.name ILIKE '%5%km%' AND rs.distance_km < 5) OR
        (a.name ILIKE '%26%mile%' AND rs.distance_km < 42.2) OR
        (a.name ILIKE '%13%mile%' AND rs.distance_km < 21.1) OR
        (a.name ILIKE '%10%mile%' AND rs.distance_km < 16.1) OR
        (a.name ILIKE '%6%mile%' AND rs.distance_km < 9.7) OR
        (a.name ILIKE '%3%mile%' AND rs.distance_km < 4.8)
    )
);

-- Step 5: Clean up excess achievements (keep only first 3 per session)
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
    WHERE rank > 3
);

-- Step 6: Delete unit preference mismatches (from previous fix)
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN public.user u ON ua.user_id = u.id
    JOIN achievements a ON ua.achievement_id = a.id
    WHERE 
        (u.prefer_metric = true AND a.unit_preference = 'standard') OR
        (u.prefer_metric = false AND a.unit_preference = 'metric')
);

-- Step 7: Verification - Check remaining problematic cases
SELECT 
    'REMAINING_ISSUES' as check_type,
    ua.user_id,
    u.username,
    ua.session_id,
    COUNT(*) as achievement_count,
    MIN(rs.duration_seconds) as min_duration,
    MIN(rs.distance_km) as min_distance,
    STRING_AGG(a.name, '; ') as achievement_names
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
GROUP BY ua.user_id, u.username, ua.session_id
HAVING 
    COUNT(*) > 3 OR  -- More than 3 achievements per session
    MIN(rs.duration_seconds) < 300 OR  -- Session too short
    MIN(rs.distance_km) < 0.5  -- Distance too short
ORDER BY achievement_count DESC, min_duration ASC;

-- Step 8: Final count check
SELECT 'FINAL_STATS' as summary, COUNT(*) as total_achievements
FROM user_achievements;

-- Step 9: Check user '27264fea-0b23-4e16-93d3-31bed3871b5c' specifically
SELECT 
    ua.id,
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
