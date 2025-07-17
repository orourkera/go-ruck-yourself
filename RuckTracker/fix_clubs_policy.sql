-- Fix for infinite recursion in clubs RLS policy
-- The original policy was causing circular dependency by referencing club_memberships within clubs policy

-- Drop the problematic policy
DROP POLICY IF EXISTS "Public clubs viewable by everyone" ON clubs;

-- Create a simplified policy that avoids circular reference
-- This policy allows users to:
-- 1. View all public clubs (no circular reference)
-- 2. View clubs they are admins of (direct reference)
CREATE POLICY "Public clubs viewable by everyone" ON clubs
FOR SELECT USING (
    is_public = true OR admin_user_id = auth.uid()
);

-- Note: If you need members to see clubs they belong to, you would need to handle this
-- at the application level or use a different approach that doesn't create circular references
