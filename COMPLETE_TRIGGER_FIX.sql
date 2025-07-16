-- COMPLETE TRIGGER FIX - Run this entire script at once
-- This will disable the broken trigger and install the fixed one

-- STEP 1: Remove the broken trigger (EMERGENCY)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

SELECT 'BROKEN TRIGGER REMOVED - Signups should work now!' as status;

-- STEP 2: Install the FIXED trigger with all required fields
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Skip if user already exists
  IF EXISTS (SELECT 1 FROM public.user WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;
  
  -- Only create user if we have valid email
  IF NEW.email IS NOT NULL AND NEW.email != '' THEN
    INSERT INTO public.user (
      id,
      email,
      username,
      prefer_metric,  -- This was MISSING in the original trigger!
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
        SPLIT_PART(NEW.email, '@', 1),
        'User'
      ),
      true,  -- Default to metric = true (this was missing!)
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.created_at,
      NOW()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$;

-- STEP 3: Recreate the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- STEP 4: Grant permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.user TO authenticated;
GRANT SELECT ON public.user TO anon;

-- STEP 5: Verify the fix
SELECT 'FIXED TRIGGER INSTALLED - Test signup now!' as status;

-- Check if any users are missing
SELECT 
  'Users in auth.users but missing from public.user' as status,
  COUNT(*) as count
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
WHERE pu.id IS NULL;
