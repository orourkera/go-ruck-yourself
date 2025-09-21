-- RPC function to get public ruck sessions with optimized route data
-- This function reduces Redis memory usage by using sampled route points
CREATE OR REPLACE FUNCTION get_public_sessions_optimized(
    p_page INTEGER DEFAULT 1,
    p_per_page INTEGER DEFAULT 20,
    p_sort_by TEXT DEFAULT 'proximity_asc',
    p_following_only BOOLEAN DEFAULT false,
    p_latitude DOUBLE PRECISION DEFAULT NULL,
    p_longitude DOUBLE PRECISION DEFAULT NULL,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    offset_value INTEGER;
    order_clause TEXT;
    result_json JSON;
    session_record RECORD;
    sessions_json JSON[];
    route_points JSON;
    following_user_ids UUID[];
BEGIN
    -- Calculate offset for pagination
    offset_value := (p_page - 1) * p_per_page;
    
    -- Get following user IDs if following_only is true
    IF p_following_only THEN
        SELECT ARRAY(
            SELECT followed_id 
            FROM user_follows 
            WHERE follower_id = p_user_id
        ) INTO following_user_ids;
        
        -- If user isn't following anyone, return empty result
        IF following_user_ids IS NULL OR array_length(following_user_ids, 1) IS NULL THEN
            RETURN json_build_object(
                'ruck_sessions', '[]'::json,
                'meta', json_build_object(
                    'count', 0,
                    'per_page', p_per_page,
                    'page', p_page,
                    'sort_by', p_sort_by
                )
            );
        END IF;
    END IF;
    
    -- Determine order clause based on sort_by parameter
    CASE p_sort_by
        WHEN 'proximity_asc' THEN
            -- Proximity sorting requires client-side calculation with user's location
            -- Backend cannot precompute proximity without knowing user's location
            -- Return sessions sorted by recent, frontend will handle proximity sorting
            order_clause := 'ORDER BY completed_at DESC';
        WHEN 'created_at_desc' THEN
            order_clause := 'ORDER BY completed_at DESC';
        WHEN 'calories_desc' THEN
            order_clause := 'ORDER BY calories_burned DESC NULLS LAST';
        WHEN 'distance_desc' THEN
            order_clause := 'ORDER BY distance_km DESC NULLS LAST';
        WHEN 'duration_desc' THEN
            order_clause := 'ORDER BY duration_seconds DESC NULLS LAST';
        WHEN 'elevation_gain_desc' THEN
            order_clause := 'ORDER BY elevation_gain_m DESC NULLS LAST';
        ELSE
            order_clause := 'ORDER BY completed_at DESC';
    END CASE;
    
    -- Build sessions array
    sessions_json := ARRAY[]::JSON[];
    
    FOR session_record IN
        EXECUTE '
        SELECT 
            rs.id,
            rs.user_id,
            rs.distance_km,
            rs.duration_seconds,
            rs.calories_burned,
            rs.elevation_gain_m,
            rs.elevation_loss_m,
            rs.ruck_weight_kg,
            rs.average_pace,
            rs.started_at,
            rs.completed_at,
            rs.is_public,
            u.username,
            u.avatar_url,
            -- Social counts
            (SELECT COUNT(*) FROM ruck_likes WHERE ruck_id = rs.id) as like_count,
            (SELECT COUNT(*) FROM ruck_comments WHERE ruck_id = rs.id) as comment_count,
            (SELECT EXISTS(SELECT 1 FROM ruck_likes WHERE ruck_id = rs.id AND user_id = $1)) as is_liked_by_current_user
        FROM ruck_session rs
        JOIN "user" u ON rs.user_id = u.id
        WHERE 
            rs.is_public = true
            AND u.allow_ruck_sharing = true
            AND ($1 IS NULL OR rs.user_id != $1)  -- Handle null user_id properly
            AND rs.status = ''completed''
            AND rs.duration_seconds > 180
            AND rs.distance_km >= 0.5
            AND rs.is_manual = false  -- Exclude manual rucks from social feed
            ' || (CASE WHEN p_following_only THEN 'AND rs.user_id = ANY($2)' ELSE '' END) || '
        ' || order_clause || '
        LIMIT $3 OFFSET $4'
        USING p_user_id, following_user_ids, p_per_page, offset_value
    LOOP
        -- Get intelligently sampled route points based on distance
        -- Use your existing get_sampled_route_points function with distance-aware parameters
        SELECT json_agg(
            json_build_object(
                'lat', latitude,
                'lng', longitude,
                'timestamp', "timestamp"
            )
        ) INTO route_points
        FROM get_privacy_clipped_sampled_points(
            session_record.id,
            -- Clip first/last N meters for privacy (server-side)
            250.0,
            -- Sampling interval based on distance
            CASE
                WHEN session_record.distance_km <= 3 THEN 4
                WHEN session_record.distance_km <= 5 THEN 6
                WHEN session_record.distance_km <= 10 THEN 8
                WHEN session_record.distance_km <= 15 THEN 10
                ELSE 12
            END,
            -- Max points based on distance
            CASE
                WHEN session_record.distance_km IS NULL OR session_record.distance_km < 1 THEN 60
                WHEN session_record.distance_km <= 3 THEN 100
                WHEN session_record.distance_km <= 5 THEN 150
                WHEN session_record.distance_km <= 10 THEN 250
                WHEN session_record.distance_km <= 15 THEN 350
                ELSE 450  -- 20km+ routes
            END
        )
        -- Only include rucks that have at least 3 route points after privacy clipping
        -- This filters out rucks with insufficient GPS data for meaningful map display
        WHERE (SELECT COUNT(*) FROM get_privacy_clipped_sampled_points(
            session_record.id,
            250.0,  -- Use same clipping as main query
            CASE
                WHEN session_record.distance_km <= 3 THEN 4
                WHEN session_record.distance_km <= 5 THEN 6
                WHEN session_record.distance_km <= 10 THEN 8
                WHEN session_record.distance_km <= 15 THEN 10
                ELSE 12
            END,
            CASE
                WHEN session_record.distance_km IS NULL OR session_record.distance_km < 1 THEN 60
                WHEN session_record.distance_km <= 3 THEN 100
                WHEN session_record.distance_km <= 5 THEN 150
                WHEN session_record.distance_km <= 10 THEN 250
                WHEN session_record.distance_km <= 15 THEN 350
                ELSE 450
            END
        )) >= 3;
        
        -- Build session JSON object
        sessions_json := sessions_json || json_build_object(
            'id', session_record.id,
            'user_id', session_record.user_id,
            'username', session_record.username,
            'avatar_url', session_record.avatar_url,
            'distance_km', session_record.distance_km,
            'duration_seconds', session_record.duration_seconds,
            'calories_burned', session_record.calories_burned,
            'elevation_gain_m', session_record.elevation_gain_m,
            'elevation_loss_m', session_record.elevation_loss_m,
            'ruck_weight_kg', session_record.ruck_weight_kg,
            'average_pace', session_record.average_pace,
            'started_at', session_record.started_at,
            'completed_at', session_record.completed_at,
            'like_count', session_record.like_count,
            'comment_count', session_record.comment_count,
            'is_liked_by_current_user', session_record.is_liked_by_current_user,
            'location_points', COALESCE(route_points, '[]'::json)
        );
    END LOOP;
    
    -- Build final response
    result_json := json_build_object(
        'ruck_sessions', array_to_json(sessions_json),
        'meta', json_build_object(
            'count', array_length(sessions_json, 1),
            'per_page', p_per_page,
            'page', p_page,
            'sort_by', p_sort_by
        )
    );
    
    RETURN result_json;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_public_sessions_optimized TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_sessions_optimized TO service_role;
