-- Migration: Add coaching_tone column to users table
-- Author: Assistant 2025-09-22
-- Purpose: Fix coaching plans API error by adding missing coaching_tone column

-- Add coaching_tone column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS coaching_tone VARCHAR(50) DEFAULT 'supportive_friend';

-- Add comment for documentation
COMMENT ON COLUMN users.coaching_tone IS 'User preferred coaching personality tone (drill_sergeant, supportive_friend, etc.)';
