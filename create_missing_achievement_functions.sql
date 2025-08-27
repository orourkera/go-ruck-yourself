-- Create missing RPC functions for achievement system with proper validation rules
-- These functions apply the same validation requirements as the achievement system (300s + 0.5km)

-- Function to calculate total distance for a user (with validation rules)
CREATE OR REPLACE FUNCTION get_user_total_distance(p_user_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(distance_km)
         FROM ruck_session 
         WHERE user_id = p_user_id 
         AND status = 'completed'
         AND duration_seconds >= 300
         AND distance_km >= 0.5
         AND distance_km IS NOT NULL), 
        0
    );
END;
$$;

-- Function to get comprehensive user achievement stats (with validation rules)
-- This replaces the existing get_user_achievement_stats to include total_distance
-- FIXED: Match the parameter name that Python code expects
CREATE OR REPLACE FUNCTION get_user_achievement_stats(user_id UUID, unit_pref TEXT DEFAULT 'metric')
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
    earned_data JSONB;
    available_count BIGINT;
    session_stats JSON;
BEGIN
    -- Get earned achievements in one query
    SELECT jsonb_agg(jsonb_build_object('category', a.category, 'tier', a.tier, 'power_points', a.power_points))
    INTO earned_data
    FROM user_achievements ua 
    JOIN achievements a ON ua.achievement_id = a.id 
    WHERE ua.user_id = get_user_achievement_stats.user_id;
    
    -- Get total available (with unit preference filter)
    SELECT COUNT(*)
    INTO available_count
    FROM achievements 
    WHERE is_active = true 
    AND (unit_preference IS NULL OR unit_preference = unit_pref);
    
    -- Get session stats with validation rules (CRITICAL: This was missing!)
    SELECT json_build_object(
        'total_distance', COALESCE(SUM(distance_km), 0),
        'total_duration_seconds', COALESCE(SUM(duration_seconds), 0),
        'total_sessions', COUNT(*),
        'total_power_points', COALESCE(SUM(CAST(power_points AS NUMERIC)), 0),
        'max_distance', COALESCE(MAX(distance_km), 0),
        'max_duration', COALESCE(MAX(duration_seconds), 0),
        'max_weight', COALESCE(MAX(ruck_weight_kg), 0),
        'total_elevation_gain', COALESCE(SUM(elevation_gain_m), 0)
    ) INTO session_stats
    FROM ruck_session 
    WHERE user_id = get_user_achievement_stats.user_id
    AND status = 'completed'
    AND duration_seconds >= 300
    AND distance_km >= 0.5;
    
    -- Combine all stats into the expected format
    SELECT json_build_object(
        'total_earned', COALESCE(jsonb_array_length(earned_data), 0),
        'total_available', available_count,
        'power_points', COALESCE((SELECT SUM((elem->>'power_points')::numeric) FROM jsonb_array_elements(earned_data) elem), 0),
        'category_counts', COALESCE((SELECT jsonb_object_agg(category, cnt) FROM (
            SELECT elem->>'category' as category, COUNT(*) as cnt 
            FROM jsonb_array_elements(earned_data) elem 
            GROUP BY elem->>'category'
        ) t), '{}'::jsonb),
        'tier_counts', COALESCE((SELECT jsonb_object_agg(tier, cnt) FROM (
            SELECT elem->>'tier' as tier, COUNT(*) as cnt 
            FROM jsonb_array_elements(earned_data) elem 
            GROUP BY elem->>'tier'  
        ) t), '{}'::jsonb),
        -- CRITICAL: Add session stats including total_distance
        'total_distance', (session_stats->>'total_distance')::numeric,
        'total_duration_seconds', (session_stats->>'total_duration_seconds')::numeric,
        'total_sessions', (session_stats->>'total_sessions')::numeric,
        'total_power_points', (session_stats->>'total_power_points')::numeric,
        'max_distance', (session_stats->>'max_distance')::numeric,
        'max_duration', (session_stats->>'max_duration')::numeric,
        'max_weight', (session_stats->>'max_weight')::numeric,
        'total_elevation_gain', (session_stats->>'total_elevation_gain')::numeric
    ) INTO result;
    
    RETURN result;
END;
$$;

-- Update the existing calculate_user_power_points function to include validation rules
CREATE OR REPLACE FUNCTION calculate_user_power_points(user_id_param UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(CAST(power_points AS NUMERIC))
         FROM ruck_session 
         WHERE user_id = user_id_param 
         AND status = 'completed'
         AND duration_seconds >= 300
         AND distance_km >= 0.5
         AND power_points IS NOT NULL
         AND power_points != ''), 
        0
    );
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_user_total_distance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_achievement_stats(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_user_power_points(UUID) TO authenticated;

-- Grant execute permissions to service role for backend operations
GRANT EXECUTE ON FUNCTION get_user_total_distance(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION get_user_achievement_stats(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION calculate_user_power_points(UUID) TO service_role;
