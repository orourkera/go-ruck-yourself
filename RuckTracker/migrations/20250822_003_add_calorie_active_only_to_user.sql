-- Migration: Add calorie_active_only preference to user
-- Date: 2025-08-22

ALTER TABLE "user"
  ADD COLUMN IF NOT EXISTS calorie_active_only BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "user".calorie_active_only IS 'If true, report active calories only (subtract resting).';

