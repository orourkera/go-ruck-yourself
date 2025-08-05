-- Debug version to identify why get_user_recent_sessions returns null
-- Test each component separately

-- 1. Test if auth.uid() is working
SELECT auth.uid() as current_user_id;

-- 2. Test if we have any sessions for the user
SELECT COUNT(*) as session_count
FROM ruck_session 
WHERE user_id = auth.uid() 
  AND status = 'completed';

-- 3. Test if we can get sessions without the route data
SELECT 
    rs.id,
    rs.user_id,
    rs.distance_km,
    rs.duration_seconds,
    rs.status,
    rs.completed_at
FROM ruck_session rs
WHERE 
    rs.user_id = auth.uid()
    AND rs.status = 'completed'
ORDER BY rs.completed_at DESC
LIMIT 5;

-- 4. Test if location_point data exists for a session
SELECT 
    rs.id as session_id,
    COUNT(lp.id) as point_count
FROM ruck_session rs
LEFT JOIN location_point lp ON lp.session_id = rs.id
WHERE 
    rs.user_id = auth.uid()
    AND rs.status = 'completed'
GROUP BY rs.id
ORDER BY rs.completed_at DESC
LIMIT 5;

-- 5. Test the get_sampled_route_points function directly
-- Replace 669 with an actual session_id from the results above
SELECT * FROM get_sampled_route_points(669, 5, 10);

-- 6. Test building the JSON for route points
SELECT json_agg(
    json_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'timestamp', "timestamp"
    )
) as route_json
FROM get_sampled_route_points(669, 5, 10);

-- 7. Test the full function with explicit user_id
-- Replace with your actual user UUID
SELECT get_user_recent_sessions(5, 'YOUR_USER_UUID_HERE'::UUID);

-- 8. Test with default parameters
SELECT get_user_recent_sessions(); 