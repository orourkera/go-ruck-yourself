-- Delete all achievements where session_id is null
-- These are orphaned achievements where the triggering session was deleted

-- Step 1: Check how many achievements will be deleted (optional safety check)
SELECT 
    COUNT(*) as total_null_session_achievements,
    COUNT(DISTINCT user_id) as affected_users
FROM user_achievements 
WHERE session_id IS NULL;

-- Step 2: Show sample of achievements that will be deleted
SELECT 
    ua.id,
    ua.user_id,
    ua.achievement_id,
    a.name as achievement_name,
    ua.earned_at,
    ua.metadata
FROM user_achievements ua
LEFT JOIN achievements a ON ua.achievement_id = a.id
WHERE ua.session_id IS NULL
ORDER BY ua.earned_at DESC
LIMIT 10;

-- Step 3: Delete all achievements where session_id is null
DELETE FROM user_achievements 
WHERE session_id IS NULL;

-- Step 4: Verify deletion
SELECT 
    COUNT(*) as remaining_null_session_achievements
FROM user_achievements 
WHERE session_id IS NULL;
