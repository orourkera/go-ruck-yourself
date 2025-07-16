-- FIXED AUTH TRIGGER (Run after emergency disable)
-- This is the corrected version that includes ALL required fields

-- Create the FIXED trigger function
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
        'User'  -- Better fallback
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

-- Recreate the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Test the fix
SELECT 'FIXED AUTH TRIGGER CREATED - Testing signup now!' as status;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.user TO authenticated;
GRANT SELECT ON public.user TO anon;
