-- Final debug script for get_user_recent_sessions

-- 1. First, check if you have any completed sessions
SELECT COUNT(*) as total_sessions, 
       COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_sessions
FROM ruck_session 
WHERE user_id = auth.uid();

-- 2. Get a sample session ID to test with
SELECT id, user_id, status, distance_km, completed_at
FROM ruck_session 
WHERE user_id = auth.uid() 
  AND status = 'completed'
ORDER BY completed_at DESC
LIMIT 5;

-- 3. Test the get_sampled_route_points function with a real session ID
-- Replace 669 with an actual session_id from step 2
SELECT COUNT(*) as point_count 
FROM get_sampled_route_points(669, 5, 200);

-- 4. Test the route JSON aggregation
SELECT json_agg(
    json_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'timestamp', "timestamp"
    )
) as route_json
FROM get_sampled_route_points(669, 5, 200);

-- 5. Now test the actual function
SELECT get_user_recent_sessions(5);

-- 6. If still returning null, test with explicit user ID
-- Replace with your actual UUID
SELECT get_user_recent_sessions(5, 'YOUR_USER_UUID'::UUID);

-- 7. Check if the issue is with auth.uid()
SELECT 
    auth.uid() as auth_user_id,
    current_user as db_user,
    session_user as session_user;

-- 8. Test a minimal version inline
WITH user_sessions AS (
    SELECT 
        rs.id,
        rs.user_id,
        rs.distance_km,
        rs.status
    FROM ruck_session rs
    WHERE rs.user_id = auth.uid()
      AND rs.status = 'completed'
    LIMIT 5
)
SELECT json_agg(row_to_json(user_sessions)) FROM user_sessions; 