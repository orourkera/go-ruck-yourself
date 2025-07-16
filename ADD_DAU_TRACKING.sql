-- Add DAU tracking column to users table
-- This enables tracking of Daily Active Users via last_active_at timestamp

ALTER TABLE users 
ADD COLUMN last_active_at TIMESTAMPTZ DEFAULT NOW();

-- Create index for efficient DAU queries
CREATE INDEX idx_users_last_active_at ON users(last_active_at);

-- Optional: Update existing users to have a last_active_at value
-- (set to their created_at or a reasonable default)
UPDATE users 
SET last_active_at = COALESCE(created_at, NOW()) 
WHERE last_active_at IS NULL;

-- DAU Query Examples:

-- Get today's DAU count
-- SELECT COUNT(*) FROM users WHERE last_active_at >= CURRENT_DATE;

-- Get DAU for a specific date
-- SELECT COUNT(*) FROM users WHERE last_active_at >= '2025-01-15' AND last_active_at < '2025-01-16';

-- Get DAU for last 7 days
-- SELECT 
--   DATE(last_active_at) as date,
--   COUNT(*) as dau
-- FROM users 
-- WHERE last_active_at >= CURRENT_DATE - INTERVAL '7 days'
-- GROUP BY DATE(last_active_at)
-- ORDER BY date DESC;

-- Get DAU trends (last 30 days)
-- SELECT 
--   DATE(last_active_at) as date,
--   COUNT(*) as dau
-- FROM users 
-- WHERE last_active_at >= CURRENT_DATE - INTERVAL '30 days'
-- GROUP BY DATE(last_active_at)
-- ORDER BY date DESC;
