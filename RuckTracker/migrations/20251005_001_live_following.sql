-- Add live following privacy control to ruck sessions
ALTER TABLE ruck_session ADD COLUMN IF NOT EXISTS allow_live_following BOOLEAN DEFAULT true;

-- Create index for finding active rucks with live following enabled
CREATE INDEX IF NOT EXISTS idx_ruck_session_live_following
  ON ruck_session(user_id, status, allow_live_following)
  WHERE status = 'active' AND allow_live_following = true;

-- Comment
COMMENT ON COLUMN ruck_session.allow_live_following IS 'Whether followers can view this ruck live and send messages';
