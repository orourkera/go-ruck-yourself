-- ========================================================================
-- ADVANCED PERFORMANCE OPTIMIZATIONS (Beyond Indexes)
-- ========================================================================
-- Additional optimizations to push performance from <100ms to <50ms
-- ========================================================================

-- 1. QUERY OPTIMIZATION TECHNIQUES
-- ========================================================================

-- A. Use COUNT(*) with EXISTS instead of fetching all data
-- Instead of: SELECT COUNT(*) FROM location_point WHERE session_id = X
-- Use: SELECT EXISTS(SELECT 1 FROM location_point WHERE session_id = X LIMIT 1)

-- B. Add LIMIT to all queries to prevent accidental full table scans
-- Example: SELECT * FROM ruck_session ORDER BY completed_at DESC LIMIT 50;

-- C. Use specific column selection instead of SELECT *
-- Instead of: SELECT * FROM achievements
-- Use: SELECT id, name, description, category, tier FROM achievements

-- 2. DATABASE FUNCTION OPTIMIZATIONS  
-- ========================================================================

-- Create a fast session point count function
CREATE OR REPLACE FUNCTION get_session_point_count(session_id_param INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- Use EXISTS for better performance when count > 0
    IF EXISTS(SELECT 1 FROM location_point WHERE session_id = session_id_param LIMIT 1) THEN
        -- Only do expensive COUNT if points exist
        RETURN (SELECT COUNT(*) FROM location_point WHERE session_id = session_id_param);
    ELSE
        RETURN 0;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create achievement stats function (reduce round trips)
CREATE OR REPLACE FUNCTION get_user_achievement_stats(user_id_param UUID, unit_pref TEXT DEFAULT 'metric')
RETURNS TABLE(
    total_earned BIGINT,
    total_available BIGINT,
    power_points NUMERIC,
    category_counts JSONB,
    tier_counts JSONB
) AS $$
DECLARE
    earned_data JSONB;
    available_count BIGINT;
    total_power NUMERIC := 0;
BEGIN
    -- Get earned achievements in one query
    SELECT jsonb_agg(jsonb_build_object('category', a.category, 'tier', a.tier, 'power_points', a.power_points))
    INTO earned_data
    FROM user_achievements ua 
    JOIN achievements a ON ua.achievement_id = a.id 
    WHERE ua.user_id = user_id_param;
    
    -- Get total available (with unit preference filter)
    SELECT COUNT(*)
    INTO available_count
    FROM achievements 
    WHERE is_active = true 
    AND (unit_preference IS NULL OR unit_preference = unit_pref);
    
    -- Calculate aggregates
    SELECT 
        COALESCE(jsonb_array_length(earned_data), 0),
        available_count,
        COALESCE((SELECT SUM((elem->>'power_points')::numeric) FROM jsonb_array_elements(earned_data) elem), 0),
        COALESCE((SELECT jsonb_object_agg(category, cnt) FROM (
            SELECT elem->>'category' as category, COUNT(*) as cnt 
            FROM jsonb_array_elements(earned_data) elem 
            GROUP BY elem->>'category'
        ) t), '{}'::jsonb),
        COALESCE((SELECT jsonb_object_agg(tier, cnt) FROM (
            SELECT elem->>'tier' as tier, COUNT(*) as cnt 
            FROM jsonb_array_elements(earned_data) elem 
            GROUP BY elem->>'tier'  
        ) t), '{}'::jsonb)
    INTO total_earned, total_available, power_points, category_counts, tier_counts;
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- 3. PRECOMPUTED COLUMNS (Add to existing tables)
-- ========================================================================

-- Add denormalized columns to ruck_session for faster queries
ALTER TABLE ruck_session ADD COLUMN IF NOT EXISTS location_point_count INTEGER DEFAULT 0;
ALTER TABLE ruck_session ADD COLUMN IF NOT EXISTS has_route BOOLEAN DEFAULT FALSE;

-- Create trigger to maintain precomputed values
CREATE OR REPLACE FUNCTION update_session_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Update session when location points are added
        UPDATE ruck_session 
        SET location_point_count = location_point_count + 1,
            has_route = TRUE
        WHERE id = NEW.session_id;
    ELSIF TG_OP = 'DELETE' THEN
        -- Update session when location points are removed
        UPDATE ruck_session 
        SET location_point_count = GREATEST(location_point_count - 1, 0)
        WHERE id = OLD.session_id;
        
        -- Check if session still has route
        UPDATE ruck_session 
        SET has_route = EXISTS(SELECT 1 FROM location_point WHERE session_id = OLD.session_id LIMIT 1)
        WHERE id = OLD.session_id AND location_point_count = 0;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Apply trigger
DROP TRIGGER IF EXISTS location_point_stats_trigger ON location_point;
CREATE TRIGGER location_point_stats_trigger
    AFTER INSERT OR DELETE ON location_point
    FOR EACH ROW EXECUTE FUNCTION update_session_stats();

-- 4. MATERIALIZED VIEWS FOR COMPLEX QUERIES
-- ========================================================================

-- Create materialized view for user achievement stats
CREATE MATERIALIZED VIEW IF NOT EXISTS user_achievement_summary AS
SELECT 
    ua.user_id,
    COUNT(*) as total_earned,
    SUM(a.power_points) as total_power_points,
    jsonb_object_agg(a.category, category_stats.count) as category_counts,
    jsonb_object_agg(a.tier, tier_stats.count) as tier_counts,
    MAX(ua.earned_at) as last_earned_at
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
LEFT JOIN (
    SELECT ua2.user_id, a2.category, COUNT(*) as count
    FROM user_achievements ua2
    JOIN achievements a2 ON ua2.achievement_id = a2.id  
    GROUP BY ua2.user_id, a2.category
) category_stats ON ua.user_id = category_stats.user_id AND a.category = category_stats.category
LEFT JOIN (
    SELECT ua3.user_id, a3.tier, COUNT(*) as count
    FROM user_achievements ua3
    JOIN achievements a3 ON ua3.achievement_id = a3.id
    GROUP BY ua3.user_id, a3.tier  
) tier_stats ON ua.user_id = tier_stats.user_id AND a.tier = tier_stats.tier
GROUP BY ua.user_id;

-- Create unique index on materialized view
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_achievement_summary_user_id 
ON user_achievement_summary(user_id);

-- 5. QUERY HINTS AND OPTIMIZATIONS
-- ========================================================================

-- Enable parallel queries for large tables
SET max_parallel_workers_per_gather = 4;
SET work_mem = '64MB';

-- Optimize random page cost for SSD storage
SET random_page_cost = 1.1;

-- ========================================================================
-- USAGE EXAMPLES
-- ========================================================================

-- Fast session point count:
-- SELECT get_session_point_count(1181);

-- Fast user achievement stats:
-- SELECT * FROM get_user_achievement_stats('user-uuid', 'metric');

-- Fast session queries using precomputed columns:
-- SELECT * FROM ruck_session WHERE has_route = true AND location_point_count > 100;

-- Fast achievement stats using materialized view:
-- SELECT * FROM user_achievement_summary WHERE user_id = 'user-uuid';

-- Refresh materialized view (run periodically):
-- REFRESH MATERIALIZED VIEW user_achievement_summary;

-- ========================================================================
