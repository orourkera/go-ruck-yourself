-- Migration: Add advanced calorie tracking fields to user
-- Date: 2025-08-22

ALTER TABLE "user"
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS resting_hr INTEGER CHECK (resting_hr IS NULL OR (resting_hr >= 30 AND resting_hr <= 120)),
  ADD COLUMN IF NOT EXISTS max_hr INTEGER CHECK (max_hr IS NULL OR (max_hr >= 100 AND max_hr <= 240)),
  ADD COLUMN IF NOT EXISTS calorie_method TEXT CHECK (calorie_method IN ('fusion','mechanical','hr'));

COMMENT ON COLUMN "user".date_of_birth IS 'User birthdate for age-based calorie calculations';
COMMENT ON COLUMN "user".resting_hr IS 'User resting heart rate (bpm)';
COMMENT ON COLUMN "user".max_hr IS 'User max heart rate (bpm)';
COMMENT ON COLUMN "user".calorie_method IS 'Preferred calorie calculation method: fusion (default), mechanical, hr';

