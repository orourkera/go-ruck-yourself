-- Simplified test version to debug get_user_recent_sessions
CREATE OR REPLACE FUNCTION test_get_user_recent_sessions(
    p_limit INTEGER DEFAULT 20,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    result_json JSON;
    current_user_id UUID;
BEGIN
    -- Use the provided user ID
    current_user_id := COALESCE(p_user_id, auth.uid());
    
    -- Debug: Log the user ID
    RAISE NOTICE 'Current user ID: %', current_user_id;
    
    -- Return empty result if no user ID available
    IF current_user_id IS NULL THEN
        RAISE NOTICE 'No user ID available';
        RETURN '[]'::JSON;
    END IF;
    
    -- Simple query without the complex route aggregation
    SELECT json_agg(
        json_build_object(
            'id', rs.id,
            'user_id', rs.user_id,
            'distance_km', rs.distance_km,
            'duration_seconds', rs.duration_seconds,
            'calories_burned', rs.calories_burned,
            'elevation_gain_m', rs.elevation_gain_m,
            'elevation_loss_m', rs.elevation_loss_m,
            'average_pace', rs.average_pace,
            'started_at', rs.started_at,
            'completed_at', rs.completed_at,
            'is_public', rs.is_public,
            'status', rs.status,
            'is_manual', rs.is_manual,
            'like_count', (SELECT COUNT(*) FROM ruck_likes WHERE ruck_id = rs.id),
            'comment_count', (SELECT COUNT(*) FROM ruck_comments WHERE ruck_id = rs.id),
            'route', '[]'::json,  -- Empty route for now
            'location_points', '[]'::json,
            'locationPoints', '[]'::json
        )
    ) INTO result_json
    FROM ruck_session rs
    WHERE 
        rs.user_id = current_user_id
        AND rs.status = 'completed'
    ORDER BY rs.completed_at DESC
    LIMIT p_limit;
    
    -- Debug: Check if we got any results
    IF result_json IS NULL THEN
        RAISE NOTICE 'No sessions found for user %', current_user_id;
        RETURN '[]'::JSON;
    END IF;
    
    RETURN result_json;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION test_get_user_recent_sessions TO authenticated;
GRANT EXECUTE ON FUNCTION test_get_user_recent_sessions TO service_role;

-- Test the function
SELECT test_get_user_recent_sessions(); 