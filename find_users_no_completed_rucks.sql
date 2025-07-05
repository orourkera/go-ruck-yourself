-- Script to find email addresses of users who have created accounts but never completed a ruck
-- This query finds users who either:
-- 1. Have no ruck sessions at all, OR
-- 2. Have ruck sessions but none are completed

-- Method 1: Using auth.users table (most comprehensive - includes all registered users)
SELECT DISTINCT
  au.email,
  au.created_at as registration_date,
  pu.display_name,
  COUNT(r.id) as total_sessions,
  COUNT(CASE WHEN r.status = 'completed' THEN 1 END) as completed_sessions,
  MAX(r.created_at) as last_session_attempt
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
LEFT JOIN public.rucks r ON au.id = r.user_id
GROUP BY au.id, au.email, au.created_at, pu.display_name
HAVING COUNT(CASE WHEN r.status = 'completed' THEN 1 END) = 0  -- No completed sessions
ORDER BY au.created_at DESC;

-- Method 2: Alternative query using public.user table (if you prefer to exclude auth-only users)
-- This excludes users who only exist in auth.users but not in public.user
/*
SELECT DISTINCT
  pu.email,
  pu.created_at as registration_date,
  pu.display_name,
  COUNT(r.id) as total_sessions,
  COUNT(CASE WHEN r.status = 'completed' THEN 1 END) as completed_sessions,
  MAX(r.created_at) as last_session_attempt
FROM public.user pu
LEFT JOIN public.rucks r ON pu.id = r.user_id
GROUP BY pu.id, pu.email, pu.created_at, pu.display_name
HAVING COUNT(CASE WHEN r.status = 'completed' THEN 1 END) = 0  -- No completed sessions
ORDER BY pu.created_at DESC;
*/

-- Method 3: Just get the email addresses (simplified output)
-- Uncomment this if you just want a simple list of email addresses
/*
SELECT au.email
FROM auth.users au
LEFT JOIN public.rucks r ON au.id = r.user_id AND r.status = 'completed'
WHERE r.id IS NULL  -- No completed rucks
ORDER BY au.created_at DESC;
*/

-- Method 4: Get users who have never even started a ruck session
-- Uncomment this to find users who have ZERO ruck sessions (not even attempted)
/*
SELECT 
  au.email,
  au.created_at as registration_date,
  pu.display_name
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
LEFT JOIN public.rucks r ON au.id = r.user_id
WHERE r.id IS NULL  -- No ruck sessions at all
ORDER BY au.created_at DESC;
*/

-- Method 5: Export for email marketing (CSV-friendly format)
-- Uncomment this to get data ready for email marketing tools
/*
SELECT 
  au.email as "Email Address",
  COALESCE(pu.display_name, 'User') as "First Name",
  au.created_at::date as "Registration Date",
  CASE 
    WHEN COUNT(r.id) = 0 THEN 'Never started'
    ELSE 'Started but never completed'
  END as "Status"
FROM auth.users au
LEFT JOIN public.user pu ON au.id = pu.id
LEFT JOIN public.rucks r ON au.id = r.user_id
GROUP BY au.id, au.email, au.created_at, pu.display_name
HAVING COUNT(CASE WHEN r.status = 'completed' THEN 1 END) = 0
ORDER BY au.created_at DESC;
*/
