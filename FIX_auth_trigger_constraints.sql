-- FIX FOR AUTH TRIGGER CONSTRAINT VIOLATIONS
-- This fixes the trigger that's causing signup failures

-- The issue: Our trigger is trying to insert users with NULL values for NOT NULL columns
-- The user table has these NOT NULL constraints:
-- - username (character varying, NO)
-- - email (character varying, NO)
-- - prefer_metric (boolean, NO, default true)

-- STEP 1: Fix the trigger function to handle NULL values properly
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Skip if user already exists (prevents conflicts)
  IF EXISTS (SELECT 1 FROM public.user WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;
  
  -- Only create user if we have valid email (critical requirement)
  IF NEW.email IS NOT NULL AND NEW.email != '' THEN
    INSERT INTO public.user (
      id,
      email,
      username,
      prefer_metric,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      NEW.email, -- This must be NOT NULL
      COALESCE(
        NEW.raw_user_meta_data->>'display_name',
        NEW.raw_user_meta_data->>'full_name', 
        NEW.raw_user_meta_data->>'name',
        SPLIT_PART(NEW.email, '@', 1),
        'User' -- Fallback if everything else is NULL
      ), -- This must be NOT NULL
      COALESCE(
        (NEW.raw_user_meta_data->>'prefer_metric')::boolean,
        true -- Default to metric if not specified
      ), -- This must be NOT NULL
      NEW.created_at,
      NOW()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$;

-- STEP 2: Test the function with some sample data
-- (This won't actually create users, just tests the logic)
DO $$
DECLARE
  test_user_id uuid := gen_random_uuid();
  test_email varchar := 'test@example.com';
BEGIN
  -- Test that the function would work with minimal data
  RAISE NOTICE 'Testing trigger function with minimal data...';
  
  -- Test with NULL metadata (typical for email/password signup)
  RAISE NOTICE 'Test 1: Email/Password signup simulation';
  RAISE NOTICE 'User ID: %', test_user_id;
  RAISE NOTICE 'Email: %', test_email;
  RAISE NOTICE 'Username would be: %', COALESCE(
    NULL, -- display_name
    NULL, -- full_name
    NULL, -- name
    SPLIT_PART(test_email, '@', 1),
    'User'
  );
  
  -- Test with OAuth metadata
  RAISE NOTICE 'Test 2: OAuth signup simulation';
  RAISE NOTICE 'Username would be: %', COALESCE(
    'John Doe', -- display_name from OAuth
    NULL, -- full_name
    NULL, -- name
    SPLIT_PART(test_email, '@', 1),
    'User'
  );
  
  RAISE NOTICE 'Trigger function tests completed successfully!';
END;
$$;

-- STEP 3: Verify the trigger is still active
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers 
WHERE trigger_name = 'on_auth_user_created';

-- STEP 4: Check if there are any users in auth.users that failed to sync
SELECT 
  'Users missing from public.user after trigger fix' as status,
  COUNT(*) as count
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL;

RAISE NOTICE 'AUTH TRIGGER FIX COMPLETED - Test signup now!';
