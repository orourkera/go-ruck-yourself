-- Comprehensive SQL script to optimize achievements performance
-- Run this in Supabase SQL Editor

-- 1. Create indexes for better query performance
-- Index for user_achievements by user_id (for fast user achievement lookups)
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id ON user_achievements(user_id);

-- Index for user_achievements by user_id and earned_at (for fast recent achievements)
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_earned ON user_achievements(user_id, earned_at DESC);

-- Index for achievement_progress by user_id
CREATE INDEX IF NOT EXISTS idx_achievement_progress_user_id ON achievement_progress(user_id);

-- Index for ruck_session by user_id and status (for power points calculation)
CREATE INDEX IF NOT EXISTS idx_ruck_session_user_status ON ruck_session(user_id, status);

-- Partial index for ruck_session power_points calculation specifically (completed sessions only)
CREATE INDEX IF NOT EXISTS idx_ruck_session_user_completed_power ON ruck_session(user_id, power_points) WHERE status = 'completed';

-- Index for achievements by is_active and unit_preference
CREATE INDEX IF NOT EXISTS idx_achievements_active_unit ON achievements(is_active, unit_preference);

-- Index for achievements category and tier for stats (active achievements only)
CREATE INDEX IF NOT EXISTS idx_achievements_category_tier ON achievements(category, tier) WHERE is_active = true;

-- Index for recent achievements (earned_at desc for last 7 days)
CREATE INDEX IF NOT EXISTS idx_user_achievements_recent ON user_achievements(earned_at DESC);

-- 2. Create SQL function to efficiently calculate total power points for a user
-- This function runs directly in the database for better performance
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
         AND power_points IS NOT NULL
         AND power_points != ''), 
        0
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION calculate_user_power_points(UUID) TO authenticated;

-- 3. Optional: Create a view for efficient achievement stats (if needed)
CREATE OR REPLACE VIEW user_achievement_stats AS
SELECT 
    ua.user_id,
    COUNT(*) as total_earned,
    COUNT(CASE WHEN a.category = 'distance' THEN 1 END) as distance_achievements,
    COUNT(CASE WHEN a.category = 'time' THEN 1 END) as time_achievements,
    COUNT(CASE WHEN a.category = 'frequency' THEN 1 END) as frequency_achievements,
    COUNT(CASE WHEN a.category = 'special' THEN 1 END) as special_achievements,
    COUNT(CASE WHEN a.tier = 'bronze' THEN 1 END) as bronze_achievements,
    COUNT(CASE WHEN a.tier = 'silver' THEN 1 END) as silver_achievements,
    COUNT(CASE WHEN a.tier = 'gold' THEN 1 END) as gold_achievements,
    COUNT(CASE WHEN a.tier = 'platinum' THEN 1 END) as platinum_achievements
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
GROUP BY ua.user_id;

-- Grant select permission on the view
GRANT SELECT ON user_achievement_stats TO authenticated;
