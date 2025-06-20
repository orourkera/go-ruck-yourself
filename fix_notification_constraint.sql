-- Remove notification type constraint to allow flexible notification types
-- This resolves the 500 error when creating events and future-proofs for new types

-- Drop the existing constraint entirely - no need to recreate it
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Verify the constraint was dropped successfully
SELECT constraint_name, check_clause 
FROM information_schema.check_constraints 
WHERE constraint_name = 'notifications_type_check';
