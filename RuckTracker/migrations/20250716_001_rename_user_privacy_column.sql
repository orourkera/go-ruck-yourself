-- Migration: Rename is_private_profile to is_profile_private to match application code
-- Author: Cascade AI 2025-07-16
-- Purpose: Fix 500 errors on profile endpoints due to column name mismatch

-- If the old column exists and the new one does not, rename it
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='user' AND column_name='is_private_profile'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name='user' AND column_name='is_profile_private'
    ) THEN
        ALTER TABLE "user" RENAME COLUMN is_private_profile TO is_profile_private;
    END IF;
END
$$;

-- Ensure default value and not-null constraint
ALTER TABLE "user" ALTER COLUMN is_profile_private SET DEFAULT false;
ALTER TABLE "user" ALTER COLUMN is_profile_private SET NOT NULL;
