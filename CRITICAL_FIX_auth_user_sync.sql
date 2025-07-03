-- CRITICAL BUG FIX: Auth/User Table Sync Issue
-- This script fixes the disconnect between auth.users and public.user tables
-- INSTRUCTIONS: Run this IMMEDIATELY in your Supabase SQL editor

-- =============================================================================
-- STEP 1: SYNC EXISTING USERS (Run this first)
-- =============================================================================

-- Check current state
SELECT 
  'Before Fix - auth.users count' as table_name,
  COUNT(*) as user_count
FROM auth.users
UNION ALL
SELECT 
  'Before Fix - public.user count' as table_name,
  COUNT(*) as user_count
FROM public.user;

-- Show missing users (these are the Google/Apple Auth users)
SELECT 
  'Missing from public.user (Google/Apple Auth users)' as status,
  au.id,
  au.email,
  au.created_at,
  au.raw_user_meta_data->>'provider' as auth_provider,
  au.raw_user_meta_data
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL
ORDER BY au.created_at DESC;

-- EMERGENCY SYNC: Insert missing users
INSERT INTO public.user (
  id,
  email,
  username,
  avatar_url,
  created_at,
  updated_at
)
SELECT 
  au.id,
  au.email,
  COALESCE(
    au.raw_user_meta_data->>'display_name',
    au.raw_user_meta_data->>'full_name',
    au.raw_user_meta_data->>'name',
    SPLIT_PART(au.email, '@', 1)
  ) as username,
  au.raw_user_meta_data->>'avatar_url' as avatar_url,
  au.created_at,
  NOW()
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- STEP 2: CREATE TRIGGER TO PREVENT FUTURE ISSUES
-- =============================================================================

-- SAFE Function to handle automatic user creation in public.user
-- This function is idempotent and works for both normal registration and OAuth flows
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only create user if they don't already exist (handles OAuth users)
  -- Normal registration flow creates users via backend API, so this won't interfere
  INSERT INTO public.user (
    id,
    email,
    username,
    avatar_url,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(
      NEW.raw_user_meta_data->>'display_name',
      NEW.raw_user_meta_data->>'full_name', 
      NEW.raw_user_meta_data->>'name',
      SPLIT_PART(NEW.email, '@', 1)
    ),
    NEW.raw_user_meta_data->>'avatar_url',
    NEW.created_at,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;  -- Critical: This prevents conflicts with normal registration
  
  RETURN NEW;
END;
$$;

-- Create trigger that fires when a new user is created in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.user TO authenticated;
GRANT SELECT ON public.user TO anon;

-- =============================================================================
-- STEP 3: VERIFY THE FIX
-- =============================================================================

-- Check final state
SELECT 
  'After Fix - auth.users count' as table_name,
  COUNT(*) as user_count
FROM auth.users
UNION ALL
SELECT 
  'After Fix - public.user count' as table_name,
  COUNT(*) as user_count
FROM public.user;

-- Verify no users are missing
SELECT 
  'Users still missing from public.user' as status,
  COUNT(*) as count
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL;

-- Show recent users to confirm sync worked
SELECT 
  'Recent users in public.user' as status,
  u.id,
  u.email,
  u.username,
  u.avatar_url,
  u.created_at
FROM public.user u
ORDER BY u.created_at DESC
LIMIT 10;

-- Show OAuth users specifically (these should have been synced)
SELECT 
  'OAuth users in public.user' as status,
  u.id,
  u.email,
  u.username,
  au.raw_user_meta_data->>'provider' as auth_provider,
  u.created_at
FROM public.user u
JOIN auth.users au ON u.id = au.id
WHERE au.raw_user_meta_data->>'provider' IN ('google', 'apple')
ORDER BY u.created_at DESC
LIMIT 10;

-- =============================================================================
-- SUCCESS MESSAGE
-- =============================================================================
SELECT 'CRITICAL FIX COMPLETE: Auth/User sync issue resolved!' as status;
