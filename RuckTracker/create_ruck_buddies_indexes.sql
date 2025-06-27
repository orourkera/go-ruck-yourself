-- Performance indexes for ruck_buddies queries
-- Run this against your Supabase database to improve query performance

-- Index for public ruck sessions ordered by completed_at (most common sort)
CREATE INDEX IF NOT EXISTS idx_ruck_session_public_completed 
ON ruck_session(is_public, completed_at DESC) 
WHERE is_public = true;

-- Index for user's allow_ruck_sharing flag
CREATE INDEX IF NOT EXISTS idx_user_allow_ruck_sharing 
ON "user"(allow_ruck_sharing) 
WHERE allow_ruck_sharing = true;

-- Index for location points to speed up joins
CREATE INDEX IF NOT EXISTS idx_location_point_session_id 
ON location_point(session_id);

-- Index for social data joins
CREATE INDEX IF NOT EXISTS idx_ruck_likes_ruck_id 
ON ruck_likes(ruck_id);

CREATE INDEX IF NOT EXISTS idx_ruck_comments_ruck_id 
ON ruck_comments(ruck_id);

-- Composite index for proximity queries (if you add PostGIS later)
-- CREATE INDEX idx_ruck_session_location 
-- ON ruck_session USING GIST (
--   ST_SetSRID(ST_MakePoint(start_longitude, start_latitude), 4326)
-- );
