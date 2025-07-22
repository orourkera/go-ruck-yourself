-- Additional indexes for profile endpoint performance optimization
-- These queries are also causing slowness in profile loading

-- 1. Index for ruck_session queries (user stats and recent rucks)
-- Optimizes: "Get all completed sessions for user X" and "Get recent rucks for user X"
CREATE INDEX IF NOT EXISTS idx_ruck_session_user_status_completed 
ON ruck_session (user_id, status, completed_at DESC);

-- 2. Alternative index for ruck_session user queries (if completed_at is nullable)
CREATE INDEX IF NOT EXISTS idx_ruck_session_user_status 
ON ruck_session (user_id, status);

-- 3. Index for user_duel_stats lookup
-- Optimizes: "Get duel stats for user X"
CREATE INDEX IF NOT EXISTS idx_user_duel_stats_user_id 
ON user_duel_stats (user_id);

-- 4. Index for club_memberships lookup  
-- Optimizes: "Get clubs for user X"
CREATE INDEX IF NOT EXISTS idx_club_memberships_user_id 
ON club_memberships (user_id);

-- Note: These indexes will significantly improve profile load times by making 
-- all user-specific queries use indexed lookups instead of table scans
