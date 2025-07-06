-- Update missing created_at timestamps in public.user table
-- from auth.users table by matching user IDs

UPDATE public.user 
SET 
  created_at = auth.users.created_at,
  updated_at = COALESCE(public.user.updated_at, auth.users.updated_at)
FROM auth.users 
WHERE 
  public.user.id = auth.users.id 
  AND public.user.created_at IS NULL
  AND auth.users.created_at IS NOT NULL;

-- Optional: Check how many records will be updated before running
-- SELECT COUNT(*) as records_to_update
-- FROM public.user 
-- JOIN auth.users ON public.user.id = auth.users.id
-- WHERE public.user.created_at IS NULL 
--   AND auth.users.created_at IS NOT NULL;

-- Optional: Preview the data before updating
-- SELECT 
--   p.id,
--   p.username,
--   p.email,
--   p.created_at as current_created_at,
--   a.created_at as auth_created_at,
--   p.updated_at as current_updated_at,
--   a.updated_at as auth_updated_at
-- FROM public.user p
-- JOIN auth.users a ON p.id = a.id
-- WHERE p.created_at IS NULL 
--   AND a.created_at IS NOT NULL
-- ORDER BY a.created_at DESC
-- LIMIT 10;
