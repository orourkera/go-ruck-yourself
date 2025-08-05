-- Debug test functions to find the issue

-- Test 1: Check if get_sampled_route_points exists
SELECT proname FROM pg_proc WHERE proname = 'get_sampled_route_points';

-- Test 2: Count basic ruck sessions
SELECT COUNT(*) as total_sessions FROM ruck_session;

-- Test 3: Count public sessions
SELECT COUNT(*) as public_sessions FROM ruck_session WHERE is_public = true;

-- Test 4: Count completed sessions
SELECT COUNT(*) as completed_sessions FROM ruck_session WHERE status = 'completed';

-- Test 5: Check user sharing settings
SELECT COUNT(*) as sharing_enabled FROM "user" WHERE allow_ruck_sharing = true;

-- Test 6: Count sessions that meet all criteria (except route sampling)
SELECT COUNT(*) as filtered_sessions
FROM ruck_session rs
JOIN "user" u ON rs.user_id = u.id
WHERE 
    rs.is_public = true
    AND u.allow_ruck_sharing = true
    AND rs.status = 'completed'
    AND rs.duration_seconds > 180
    AND rs.distance_km >= 0.5;

-- Test 7: Simple RPC test without route sampling
CREATE OR REPLACE FUNCTION test_simple_public_sessions()
RETURNS JSON
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    RETURN (
        SELECT json_agg(
            json_build_object(
                'id', rs.id,
                'user_id', rs.user_id,
                'username', u.username,
                'distance_km', rs.distance_km,
                'duration_seconds', rs.duration_seconds,
                'is_public', rs.is_public,
                'allow_sharing', u.allow_ruck_sharing
            )
        )
        FROM ruck_session rs
        JOIN "user" u ON rs.user_id = u.id
        WHERE 
            rs.is_public = true
            AND u.allow_ruck_sharing = true
            AND rs.status = 'completed'
        LIMIT 5
    );
END;
$$;
