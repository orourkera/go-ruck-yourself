-- Fix Apple Auth User Creation - RLS Policy Issue
-- The problem: auto_create_user_duel_stats trigger runs as authenticated user, 
-- but RLS policies only allow service_role to insert into user_duel_stats

-- Solution: Update the trigger function to use SECURITY DEFINER
-- This makes it run with the privileges of the function owner (service role)

CREATE OR REPLACE FUNCTION initialize_user_duel_stats()
RETURNS TRIGGER 
SECURITY DEFINER  -- This is the key fix - run with definer's privileges
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO user_duel_stats (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION initialize_user_duel_stats() TO authenticated;

-- Verify the fix by checking the function definition
SELECT 
    proname as function_name,
    prosecdef as security_definer,
    proowner::regrole as owner
FROM pg_proc 
WHERE proname = 'initialize_user_duel_stats';

-- Test query to verify current state
SELECT 'Fix applied - Apple Auth should now work!' as status;
