-- Migration: Add heart rate zone snapshot and time_in_zones to ruck_session
-- Date: 2025-08-22

ALTER TABLE ruck_session
  ADD COLUMN IF NOT EXISTS hr_zone_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS time_in_zones JSONB;

COMMENT ON COLUMN ruck_session.hr_zone_snapshot IS 'Session-level snapshot of HR zone thresholds used (to keep history consistent)';
COMMENT ON COLUMN ruck_session.time_in_zones IS 'JSON map of zone label to seconds spent in zone for this session';


