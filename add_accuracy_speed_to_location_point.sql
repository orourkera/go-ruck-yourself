-- Add accuracy and speed-related nullable columns to location_point
-- This is an additive, backward-compatible migration. No indexes added.
-- Apply safely in production; existing rows will have NULLs.

ALTER TABLE location_point
  ADD COLUMN IF NOT EXISTS horizontal_accuracy_m DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS vertical_accuracy_m DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS speed_mps DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS speed_accuracy_mps DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS course_deg DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS course_accuracy_deg DOUBLE PRECISION;
