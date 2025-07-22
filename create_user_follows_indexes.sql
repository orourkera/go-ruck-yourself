-- Create indexes for user_follows table to improve performance
-- These queries are causing 600-1100ms response times on profile endpoints
-- Expected improvement: ~800ms -> ~50-100ms

-- 1. Composite index for exact lookups (follower_id, followed_id)
-- Optimizes: "Check if user A follows user B" queries
CREATE INDEX IF NOT EXISTS idx_user_follows_follower_followed 
ON user_follows (follower_id, followed_id);

-- 2. Index on followed_id for follower counts  
-- Optimizes: "How many people follow user X" queries
CREATE INDEX IF NOT EXISTS idx_user_follows_followed_id 
ON user_follows (followed_id);

-- 3. Index on follower_id for following counts
-- Optimizes: "How many people does user X follow" queries  
CREATE INDEX IF NOT EXISTS idx_user_follows_follower_id 
ON user_follows (follower_id);

-- 4. Composite index with timestamp for pagination
-- Optimizes: Follower/following lists with created_at ordering
CREATE INDEX IF NOT EXISTS idx_user_follows_followed_created 
ON user_follows (followed_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower_created 
ON user_follows (follower_id, created_at DESC);
