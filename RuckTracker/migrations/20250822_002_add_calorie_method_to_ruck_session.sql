-- Migration: Add calorie_method to ruck_session
-- Date: 2025-08-22

ALTER TABLE ruck_session
  ADD COLUMN IF NOT EXISTS calorie_method TEXT CHECK (calorie_method IN ('fusion','mechanical','hr'));

COMMENT ON COLUMN ruck_session.calorie_method IS 'Method used to compute calories for this session: fusion, mechanical, or hr';

