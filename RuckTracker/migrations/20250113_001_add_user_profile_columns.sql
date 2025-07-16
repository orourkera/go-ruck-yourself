-- Migration: Add missing avatar_url and is_private_profile columns to user table
-- Author: Cascade AI 2025-01-13
-- Purpose: Fix 500 errors when updating user profiles by adding missing database columns

-- Add avatar_url column to user table
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(255);

-- Add is_private_profile column to user table with default value
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS is_private_profile BOOLEAN NOT NULL DEFAULT false;

-- Add comment for documentation
COMMENT ON COLUMN "user".avatar_url IS 'User profile avatar URL';
COMMENT ON COLUMN "user".is_private_profile IS 'User profile privacy setting';
