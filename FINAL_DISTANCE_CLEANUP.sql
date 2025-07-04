-- FINAL DISTANCE-SPECIFIC ACHIEVEMENT CLEANUP
-- Remove achievements that have distance requirements not met by the session

-- Step 1: DELETE distance-specific achievements where session distance is insufficient
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN achievements a ON ua.achievement_id = a.id
    JOIN ruck_session rs ON ua.session_id = rs.id
    WHERE 
        -- Mile-based achievements (convert to km for comparison)
        (a.name ILIKE '%50-Mile%' AND rs.distance_km < 80.5) OR  -- 50 miles = 80.5km
        (a.name ILIKE '%26-Mile%' AND rs.distance_km < 42.2) OR  -- 26 miles = 42.2km
        (a.name ILIKE '%20-Mile%' AND rs.distance_km < 32.2) OR  -- 20 miles = 32.2km
        (a.name ILIKE '%13-Mile%' AND rs.distance_km < 21.0) OR  -- 13 miles = 21km
        (a.name ILIKE '%12-Mile%' AND rs.distance_km < 19.3) OR  -- 12 miles = 19.3km
        (a.name ILIKE '%10-Mile%' AND rs.distance_km < 16.1) OR  -- 10 miles = 16.1km
        (a.name ILIKE '%6-Mile%' AND rs.distance_km < 9.7) OR    -- 6 miles = 9.7km
        (a.name ILIKE '%5-Mile%' AND rs.distance_km < 8.0) OR    -- 5 miles = 8km
        (a.name ILIKE '%3-Mile%' AND rs.distance_km < 4.8) OR    -- 3 miles = 4.8km
        
        -- KM-based achievements
        (a.name ILIKE '%80%km%' AND rs.distance_km < 80) OR
        (a.name ILIKE '%50%km%' AND rs.distance_km < 50) OR
        (a.name ILIKE '%42%km%' AND rs.distance_km < 42) OR
        (a.name ILIKE '%30%km%' AND rs.distance_km < 30) OR
        (a.name ILIKE '%20%km%' AND rs.distance_km < 20) OR
        (a.name ILIKE '%15%km%' AND rs.distance_km < 15) OR
        (a.name ILIKE '%10%km%' AND rs.distance_km < 10) OR
        (a.name ILIKE '%5%km%' AND rs.distance_km < 5) OR
        
        -- Warriors that suggest specific distances
        (a.name ILIKE '%Ten Mile Warrior%' AND rs.distance_km < 16.1) OR
        (a.name ILIKE '%Five Mile Warrior%' AND rs.distance_km < 8.0) OR
        (a.name ILIKE '%Marathon%' AND rs.distance_km < 42.0) OR
        (a.name ILIKE '%Half Marathon%' AND rs.distance_km < 21.0)
);

-- Step 2: DELETE any remaining achievements that exceed 2 per session
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

-- Step 3: Show what problematic achievements remain
SELECT 
    'DISTANCE_PROBLEMS_REMAINING' as issue_type,
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
WHERE 
    -- Check for remaining distance mismatches
    (a.name ILIKE '%50-Mile%' AND rs.distance_km < 80.5) OR
    (a.name ILIKE '%26-Mile%' AND rs.distance_km < 42.2) OR
    (a.name ILIKE '%20-Mile%' AND rs.distance_km < 32.2) OR
    (a.name ILIKE '%13-Mile%' AND rs.distance_km < 21.0) OR
    (a.name ILIKE '%12-Mile%' AND rs.distance_km < 19.3) OR
    (a.name ILIKE '%10-Mile%' AND rs.distance_km < 16.1) OR
    (a.name ILIKE '%6-Mile%' AND rs.distance_km < 9.7) OR
    (a.name ILIKE '%5-Mile%' AND rs.distance_km < 8.0) OR
    (a.name ILIKE '%3-Mile%' AND rs.distance_km < 4.8) OR
    (a.name ILIKE '%80%km%' AND rs.distance_km < 80) OR
    (a.name ILIKE '%50%km%' AND rs.distance_km < 50) OR
    (a.name ILIKE '%42%km%' AND rs.distance_km < 42) OR
    (a.name ILIKE '%30%km%' AND rs.distance_km < 30) OR
    (a.name ILIKE '%20%km%' AND rs.distance_km < 20) OR
    (a.name ILIKE '%15%km%' AND rs.distance_km < 15) OR
    (a.name ILIKE '%10%km%' AND rs.distance_km < 10) OR
    (a.name ILIKE '%5%km%' AND rs.distance_km < 5) OR
    (a.name ILIKE '%Ten Mile Warrior%' AND rs.distance_km < 16.1) OR
    (a.name ILIKE '%Five Mile Warrior%' AND rs.distance_km < 8.0) OR
    (a.name ILIKE '%Marathon%' AND rs.distance_km < 42.0) OR
    (a.name ILIKE '%Half Marathon%' AND rs.distance_km < 21.0)
ORDER BY rs.distance_km ASC;

-- Step 4: Final verification - check sessions with 3+ achievements still
SELECT 
    'FINAL_REMAINING_ISSUES' as check_type,
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
HAVING COUNT(*) > 2
ORDER BY achievement_count DESC, rs.duration_seconds ASC
LIMIT 20;

-- Step 5: Check specific users mentioned
SELECT 
    'SPECIFIC_USERS_CHECK' as check_type,
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
WHERE u.username IN ('Ruck Founder ', 'kstrassel', 'Scott', 'Chuck')
GROUP BY u.username, ua.session_id, rs.duration_seconds, rs.distance_km
ORDER BY achievement_count DESC;
