-- Migration: Add steps to ruck_session
-- Date: 2025-08-22

ALTER TABLE ruck_session
  ADD COLUMN IF NOT EXISTS steps INTEGER;

COMMENT ON COLUMN ruck_session.steps IS 'Total step count recorded for the session (optional)';


