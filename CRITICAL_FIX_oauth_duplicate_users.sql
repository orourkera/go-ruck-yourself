-- CRITICAL FIX: OAuth Duplicate User Email Bug
-- This script handles the duplicate email issue and prevents future occurrences

-- Step 1: Identify the current orphaned user
SELECT 
    u.id,
    u.username,
    u.email,
    u.created_at,
    'ORPHANED - No auth.users record' as status
FROM public.user u
LEFT JOIN auth.users au ON u.id = au.id
WHERE au.id IS NULL
AND u.email = 'wcutsinc@yahoo.com';

-- Step 2: Check if there are any auth.users records for this email
SELECT 
    id,
    email,
    created_at,
    email_confirmed_at,
    'AUTH RECORD' as status
FROM auth.users
WHERE email = 'wcutsinc@yahoo.com';

-- Step 3: Check for any session data or important user data
SELECT 
    'ruck_sessions' as table_name,
    COUNT(*) as count
FROM ruck_session 
WHERE user_id = 'ef6462f4-a6fb-440c-bd82-2db7384776d1'
UNION ALL
SELECT 
    'user_duel_stats' as table_name,
    COUNT(*) as count
FROM user_duel_stats 
WHERE user_id = 'ef6462f4-a6fb-440c-bd82-2db7384776d1'
UNION ALL
SELECT 
    'user_achievements' as table_name,
    COUNT(*) as count
FROM user_achievements 
WHERE user_id = 'ef6462f4-a6fb-440c-bd82-2db7384776d1';

-- Step 4: Clean up orphaned user (only if no important data)
-- CAUTION: Only run this if the user has no sessions/achievements/important data
/*
DELETE FROM public.user 
WHERE id = 'ef6462f4-a6fb-440c-bd82-2db7384776d1'
AND email = 'wcutsinc@yahoo.com';
*/

-- Step 5: Add database constraint to prevent duplicate emails in future
-- This will ensure email uniqueness at the database level
ALTER TABLE public.user 
ADD CONSTRAINT unique_user_email 
UNIQUE (email);

-- Step 6: Verification queries
-- After cleanup, these should show no orphaned users
SELECT 
    COUNT(*) as auth_users_count
FROM auth.users;

SELECT 
    COUNT(*) as public_users_count  
FROM public.user;

SELECT 
    COUNT(*) as orphaned_users_count
FROM public.user u
LEFT JOIN auth.users au ON u.id = au.id
WHERE au.id IS NULL;

-- Step 7: Check for any remaining duplicate emails
SELECT 
    email,
    COUNT(*) as count,
    array_agg(id) as user_ids
FROM public.user
GROUP BY email
HAVING COUNT(*) > 1;

-- USAGE INSTRUCTIONS:
-- 1. Run the diagnostic SELECT queries first to understand the current state
-- 2. Review the user data to ensure it's safe to delete
-- 3. Uncomment and run the DELETE statement if appropriate
-- 4. Run the ALTER TABLE to add the unique constraint
-- 5. Verify with the final verification queries
-- 6. Deploy the fixed OAuth code to prevent future issues

-- PREVENTION:
-- The code fix in auth.py now checks for both ID and email conflicts
-- The unique constraint prevents database-level duplicates
-- Future OAuth sign-ins will detect email conflicts and prevent duplicates
