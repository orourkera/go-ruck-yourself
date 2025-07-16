-- EMERGENCY: DISABLE BROKEN AUTH TRIGGER
-- This will immediately stop the 500 signup errors
-- RUN THIS FIRST to stop the bleeding!

-- Drop the broken trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop the broken function
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Show confirmation
SELECT 'EMERGENCY TRIGGER DISABLED - Signups should work now!' as status;

-- Check if any users are still in auth.users but missing from public.user
SELECT 
  'Users in auth.users but missing from public.user' as status,
  COUNT(*) as count
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL;

-- After signups are working, we can re-enable with a fixed trigger
