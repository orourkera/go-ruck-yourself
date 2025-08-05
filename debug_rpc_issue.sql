-- Debug why get_user_recent_sessions returns empty array

-- 1. Check your current auth user ID
SELECT auth.uid() as your_user_id;

-- 2. Check if you have ANY sessions at all
SELECT COUNT(*) as total_sessions,
       COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_sessions,
       COUNT(CASE WHEN user_id = auth.uid() THEN 1 END) as your_sessions
FROM ruck_session;

-- 3. Check your specific sessions
SELECT id, user_id, status, distance_km, duration_seconds, completed_at
FROM ruck_session 
WHERE user_id = auth.uid()
ORDER BY completed_at DESC NULLS LAST
LIMIT 10;

-- 4. If no sessions found with auth.uid(), let's check with your actual UUID
-- Based on your JWT token, your user ID is: 11683829-2373-46fc-82f1-f905d5316c30
SELECT id, status, distance_km, duration_seconds, completed_at
FROM ruck_session 
WHERE user_id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid
ORDER BY completed_at DESC NULLS LAST
LIMIT 10;

-- 5. Test the function with explicit user ID
SELECT get_user_recent_sessions(20, '11683829-2373-46fc-82f1-f905d5316c30'::uuid);

-- 6. Check if there's a mismatch between auth.uid() and your actual user_id
SELECT 
    auth.uid() as auth_uid,
    '11683829-2373-46fc-82f1-f905d5316c30'::uuid as jwt_user_id,
    auth.uid() = '11683829-2373-46fc-82f1-f905d5316c30'::uuid as ids_match;

-- 7. Let's also check the users table
SELECT id, email, created_at 
FROM users 
WHERE id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid; 