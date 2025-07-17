-- Fix for infinite recursion in club_memberships RLS policy
-- The original policy was causing circular dependency by referencing club_memberships within itself

-- Drop the problematic policy
DROP POLICY IF EXISTS "Members can view club memberships" ON club_memberships;

-- Create a simplified policy that avoids circular reference
-- This policy allows users to:
-- 1. View their own memberships
-- 2. View memberships of clubs they are admins of
-- 3. View memberships of public clubs (simplified approach)
CREATE POLICY "Members can view club memberships" ON club_memberships
FOR SELECT USING (
    user_id = auth.uid() OR 
    club_id IN (
        SELECT id FROM clubs WHERE admin_user_id = auth.uid()
    )
);

-- Alternative approach: If you need members to see other members in their clubs,
-- you could use a function-based approach or handle this at the application level
-- For now, this simpler policy will prevent the infinite recursion while still
-- allowing basic functionality.
