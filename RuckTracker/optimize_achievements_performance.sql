-- Achievement Performance Optimization Script
-- Run this in Supabase SQL Editor to improve achievement API performance

-- 1. CREATE INDEXES FOR BETTER QUERY PERFORMANCE

-- Index on user_achievements for user-specific queries
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id 
ON user_achievements(user_id);

-- Index on user_achievements for recent achievements 
CREATE INDEX IF NOT EXISTS idx_user_achievements_earned_at 
ON user_achievements(earned_at DESC);

-- Composite index for user achievements with related data
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_earned 
ON user_achievements(user_id, earned_at DESC);

-- Index on achievement_progress for user queries
CREATE INDEX IF NOT EXISTS idx_achievement_progress_user_id 
ON achievement_progress(user_id);

-- Index on ruck_session for power points calculation
CREATE INDEX IF NOT EXISTS idx_ruck_session_user_status 
ON ruck_session(user_id, status) WHERE status = 'completed';

-- Index on ruck_session specifically for power points queries
CREATE INDEX IF NOT EXISTS idx_ruck_session_power_points 
ON ruck_session(user_id, power_points) WHERE status = 'completed';

-- Index on achievements for active achievements
CREATE INDEX IF NOT EXISTS idx_achievements_active_unit 
ON achievements(is_active, unit_preference) WHERE is_active = true;

-- Index on achievements for category and tier queries  
CREATE INDEX IF NOT EXISTS idx_achievements_category_tier 
ON achievements(category, tier, is_active) WHERE is_active = true;

-- 2. CREATE SQL FUNCTION FOR POWER POINTS CALCULATION

-- Function to calculate user's total power points efficiently
CREATE OR REPLACE FUNCTION calculate_user_power_points(user_id_param UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    total_points NUMERIC := 0;
BEGIN
    -- Calculate sum of power points for completed sessions
    SELECT COALESCE(SUM(CAST(power_points AS NUMERIC)), 0)
    INTO total_points
    FROM ruck_session
    WHERE user_id = user_id_param 
    AND status = 'completed' 
    AND power_points IS NOT NULL 
    AND power_points != 'NaN';
    
    RETURN total_points;
END;
$$;

-- 3. GRANT PERMISSIONS (skipping view creation since it already exists)

-- Grant execute permission on the function to authenticated users
GRANT EXECUTE ON FUNCTION calculate_user_power_points TO authenticated;

-- 4. ANALYZE TABLES FOR BETTER QUERY PLANNING

ANALYZE user_achievements;
ANALYZE achievement_progress; 
ANALYZE ruck_session;
ANALYZE achievements;

-- 6. OPTIONAL: CREATE MATERIALIZED VIEW FOR VERY LARGE DATASETS
-- Uncomment if you have performance issues with large user counts

-- CREATE MATERIALIZED VIEW user_power_points_cache AS
-- SELECT 
--     user_id,
--     calculate_user_power_points(user_id) as total_power_points,
--     NOW() as calculated_at
-- FROM (SELECT DISTINCT user_id FROM ruck_session WHERE status = 'completed') users;

-- CREATE UNIQUE INDEX ON user_power_points_cache(user_id);
-- GRANT SELECT ON user_power_points_cache TO authenticated;

-- To refresh the materialized view (run periodically if using):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY user_power_points_cache;
