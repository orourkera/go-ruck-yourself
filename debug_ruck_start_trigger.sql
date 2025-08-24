-- Debug the ruck start notification trigger

-- 1. Check if the trigger function exists
SELECT 
    proname as function_name,
    prosecdef as security_definer,
    proowner
FROM pg_proc 
WHERE proname = 'notify_ruck_started';

-- 2. Check if the trigger exists on the ruck_session table
SELECT 
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing
FROM information_schema.triggers 
WHERE event_object_table = 'ruck_session' 
AND trigger_name LIKE '%ruck%';

-- 3. Check recent ruck sessions that should have triggered notifications
SELECT 
    id,
    user_id,
    status,
    started_at,
    created_at,
    updated_at
FROM ruck_session 
WHERE status = 'in_progress' 
   OR (status = 'completed' AND started_at >= NOW() - INTERVAL '7 days')
ORDER BY started_at DESC 
LIMIT 10;

-- 4. Check if there are any followers to notify
SELECT 
    followed_id,
    COUNT(*) as follower_count
FROM user_follows 
GROUP BY followed_id 
ORDER BY follower_count DESC 
LIMIT 10;

-- 5. Check for any trigger errors in PostgreSQL logs (if accessible)
-- This would need to be run by an admin with log access
