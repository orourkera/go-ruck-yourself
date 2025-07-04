-- NUCLEAR ACHIEVEMENT CLEANUP - AGGRESSIVE FIX
-- This will DELETE ALL problematic achievements with extreme prejudice
-- The current system is completely broken - we need to start fresh

-- Step 1: DELETE ALL achievements for sessions under 10 minutes OR under 1km
DELETE FROM user_achievements
WHERE session_id IN (
    SELECT rs.id
    FROM ruck_session rs
    WHERE rs.duration_seconds < 600 OR rs.distance_km < 1.0
);

-- Step 2: DELETE ALL achievements where more than 2 were awarded per session
-- (Keep only the first 2 achievements per session, ordered by earned_at)
WITH ranked_achievements AS (
    SELECT 
        ua.id,
        ROW_NUMBER() OVER (PARTITION BY ua.session_id ORDER BY ua.earned_at) as rank
    FROM user_achievements ua
)
DELETE FROM user_achievements
WHERE id IN (
    SELECT id 
    FROM ranked_achievements 
    WHERE rank > 2
);

-- Step 3: DELETE ALL pace achievements that don't meet basic distance requirements
DELETE FROM user_achievements
WHERE achievement_id IN (
    SELECT a.id
    FROM achievements a
    WHERE a.criteria->>'type' = 'pace_faster_than'
    AND (
        a.name ILIKE '%80%km%' OR
        a.name ILIKE '%50%km%' OR
        a.name ILIKE '%42%km%' OR
        a.name ILIKE '%marathon%' OR
        a.name ILIKE '%20%km%' OR
        a.name ILIKE '%10%km%' OR
        a.name ILIKE '%26%mile%' OR
        a.name ILIKE '%13%mile%' OR
        a.name ILIKE '%10%mile%'
    )
);

-- Step 4: DELETE achievements for sessions with 0 distance
DELETE FROM user_achievements
WHERE session_id IN (
    SELECT rs.id
    FROM ruck_session rs
    WHERE rs.distance_km = 0 OR rs.distance_km IS NULL
);

-- Step 5: DELETE achievements for sessions under 5 minutes (final safety)
DELETE FROM user_achievements
WHERE session_id IN (
    SELECT rs.id
    FROM ruck_session rs
    WHERE rs.duration_seconds < 300
);

-- Step 6: DELETE duplicate user achievements (same user, same achievement)
WITH duplicate_achievements AS (
    SELECT 
        ua.id,
        ROW_NUMBER() OVER (PARTITION BY ua.user_id, ua.achievement_id ORDER BY ua.earned_at) as rank
    FROM user_achievements ua
)
DELETE FROM user_achievements
WHERE id IN (
    SELECT id 
    FROM duplicate_achievements 
    WHERE rank > 1
);

-- Step 7: Verification - Count remaining achievements
SELECT 
    'TOTAL_REMAINING' as summary,
    COUNT(*) as total_achievements
FROM user_achievements;

-- Step 8: Check for any remaining problematic sessions
SELECT 
    'REMAINING_PROBLEMS' as check_type,
    ua.user_id,
    u.username,
    ua.session_id,
    COUNT(*) as achievement_count,
    rs.duration_seconds,
    rs.distance_km,
    STRING_AGG(a.name, '; ') as achievement_names
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
JOIN ruck_session rs ON ua.session_id = rs.id
GROUP BY ua.user_id, u.username, ua.session_id, rs.duration_seconds, rs.distance_km
HAVING 
    COUNT(*) > 2 OR
    rs.duration_seconds < 600 OR
    rs.distance_km < 1.0
ORDER BY achievement_count DESC, rs.duration_seconds ASC;

-- Step 9: Check specific problematic user
SELECT 
    'RORY_REMAINING' as check_type,
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

-- Step 10: Final statistics
SELECT 
    u.username,
    COUNT(ua.id) as total_achievements
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
GROUP BY u.username
ORDER BY total_achievements DESC
LIMIT 20;
