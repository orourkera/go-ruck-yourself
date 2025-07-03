-- Emergency script to sync auth.users with public.user table
-- Run this in your Supabase SQL editor

-- First, let's see the current state
SELECT 
  'auth.users count' as table_name,
  COUNT(*) as user_count
FROM auth.users
UNION ALL
SELECT 
  'public.user count' as table_name,
  COUNT(*) as user_count
FROM public.user;

-- Show users in auth.users but missing from public.user
SELECT 
  'Missing from public.user' as status,
  au.id,
  au.email,
  au.created_at,
  au.raw_user_meta_data
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL;

-- Show users in public.user but missing from auth.users (should be rare)
SELECT 
  'Missing from auth.users' as status,
  pu.id,
  pu.email,
  pu.created_at
FROM public.user pu
LEFT JOIN auth.users au ON pu.id = au.id
WHERE au.id IS NULL;

-- Insert missing users from auth.users into public.user
INSERT INTO public.user (
  id,
  email,
  display_name,
  profile_image_url,
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
  ) as display_name,
  au.raw_user_meta_data->>'avatar_url' as profile_image_url,
  au.created_at,
  NOW()
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- Verify the sync worked
SELECT 
  'After sync - auth.users count' as table_name,
  COUNT(*) as user_count
FROM auth.users
UNION ALL
SELECT 
  'After sync - public.user count' as table_name,
  COUNT(*) as user_count
FROM public.user;

-- Show any remaining mismatches
SELECT 
  'Still missing from public.user' as status,
  COUNT(*) as count
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL
UNION ALL
SELECT 
  'Still missing from auth.users' as status,
  COUNT(*) as count
FROM public.user pu
LEFT JOIN auth.users au ON pu.id = au.id
WHERE au.id IS NULL;
