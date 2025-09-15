-- ROLLBACK: Restore original get_user_recent_sessions function
-- Run this if the optimized version causes issues

CREATE OR REPLACE FUNCTION get_user_recent_sessions(
    p_limit INTEGER DEFAULT 20,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    session_record RECORD;
    sessions_json JSON[];
    route_points JSON;
    current_user_id UUID;
BEGIN
    -- Use the provided user ID (defaults to auth.uid() from function signature)
    current_user_id := p_user_id;

    -- Return empty result if no user ID available
    IF current_user_id IS NULL THEN
        RETURN '[]'::JSON;
    END IF;

    -- Initialize the array
    sessions_json := ARRAY[]::JSON[];

    FOR session_record IN
        SELECT
            rs.id,
            rs.user_id,
            rs.distance_km,
            rs.duration_seconds,
            rs.calories_burned,
            rs.elevation_gain_m,
            rs.elevation_loss_m,
            rs.average_pace,
            rs.started_at,
            rs.completed_at,
            rs.is_public,
            rs.status,
            rs.is_manual,
            -- ORIGINAL: Social counts for user's own sessions
            (SELECT COUNT(*) FROM ruck_likes WHERE ruck_id = rs.id) as like_count,
            (SELECT COUNT(*) FROM ruck_comments WHERE ruck_id = rs.id) as comment_count
        FROM ruck_session rs
        WHERE
            rs.user_id = current_user_id
            AND rs.status = 'completed'
        ORDER BY rs.completed_at DESC
        LIMIT p_limit
    LOOP
        -- ORIGINAL: Full route data with original sampling
        SELECT json_agg(
            json_build_object(
                'latitude', latitude,
                'longitude', longitude,
                'timestamp', "timestamp"
            )
        ) INTO route_points
        FROM get_sampled_route_points(
            session_record.id,
            -- ORIGINAL: Less aggressive sampling intervals
            CASE
                WHEN session_record.distance_km <= 3 THEN 4
                WHEN session_record.distance_km <= 5 THEN 6
                WHEN session_record.distance_km <= 10 THEN 8
                WHEN session_record.distance_km <= 15 THEN 10
                ELSE 12
            END,
            -- ORIGINAL: Higher max points
            CASE
                WHEN session_record.distance_km IS NULL OR session_record.distance_km < 1 THEN 60
                WHEN session_record.distance_km <= 3 THEN 100
                WHEN session_record.distance_km <= 5 THEN 150
                WHEN session_record.distance_km <= 10 THEN 250
                WHEN session_record.distance_km <= 15 THEN 350
                ELSE 450  -- Original 20km+ routes
            END
        );

        -- Build session JSON object with all fields expected by homepage
        sessions_json := array_append(sessions_json, json_build_object(
            'id', session_record.id,
            'user_id', session_record.user_id,
            'distance_km', session_record.distance_km,
            'duration_seconds', session_record.duration_seconds,
            'calories_burned', session_record.calories_burned,
            'elevation_gain_m', session_record.elevation_gain_m,
            'elevation_loss_m', session_record.elevation_loss_m,
            'average_pace', session_record.average_pace,
            'started_at', session_record.started_at,
            'completed_at', session_record.completed_at,
            'is_public', session_record.is_public,
            'status', session_record.status,
            'is_manual', session_record.is_manual,
            'like_count', session_record.like_count,
            'comment_count', session_record.comment_count,
            -- Route data with multiple key formats for compatibility
            'route', COALESCE(route_points, '[]'::json),
            'location_points', COALESCE(route_points, '[]'::json),
            'locationPoints', COALESCE(route_points, '[]'::json)
        ));
    END LOOP;

    -- Return array of sessions (matching existing REST API response format)
    IF array_length(sessions_json, 1) IS NULL THEN
        RETURN '[]'::JSON;
    END IF;

    RETURN array_to_json(sessions_json);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_user_recent_sessions TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_recent_sessions TO service_role;