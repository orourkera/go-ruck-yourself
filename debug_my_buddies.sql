-- Debug script for My Buddies filter issue

-- 1. Check your current user ID
SELECT auth.uid() as your_user_id;

-- 2. Check if you're following anyone
SELECT 
    COUNT(*) as total_follows,
    array_agg(followed_id) as following_user_ids
FROM user_follows 
WHERE follower_id = auth.uid();

-- 3. If no follows found with auth.uid(), check with your explicit UUID
SELECT 
    COUNT(*) as total_follows,
    array_agg(followed_id) as following_user_ids
FROM user_follows 
WHERE follower_id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid;

-- 4. Check if those users have any public completed sessions
WITH your_follows AS (
    SELECT followed_id 
    FROM user_follows 
    WHERE follower_id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid
)
SELECT 
    u.username,
    u.id as user_id,
    COUNT(rs.id) as session_count,
    COUNT(CASE WHEN rs.status = 'completed' THEN 1 END) as completed_sessions,
    COUNT(CASE WHEN rs.is_public = true THEN 1 END) as public_sessions
FROM your_follows yf
JOIN "user" u ON yf.followed_id = u.id
LEFT JOIN ruck_session rs ON rs.user_id = u.id
GROUP BY u.id, u.username
ORDER BY session_count DESC;

-- 5. Test the RPC function directly with following_only = true
SELECT get_public_sessions_optimized(
    p_page => 1,
    p_per_page => 10,
    p_sort_by => 'proximity_asc',
    p_following_only => true,
    p_user_id => '11683829-2373-46fc-82f1-f905d5316c30'::uuid
);

-- 6. Check if you have any follows at all in the system
SELECT COUNT(*) as total_follows_in_system FROM user_follows;

-- 7. See who you might want to follow (users with public sessions)
SELECT 
    u.username,
    u.id,
    COUNT(rs.id) as public_session_count
FROM "user" u
JOIN ruck_session rs ON rs.user_id = u.id
WHERE rs.is_public = true 
  AND rs.status = 'completed'
  AND u.id != '11683829-2373-46fc-82f1-f905d5316c30'::uuid
GROUP BY u.id, u.username
HAVING COUNT(rs.id) > 0
ORDER BY public_session_count DESC
LIMIT 10; 