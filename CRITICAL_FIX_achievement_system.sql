-- CRITICAL FIX: Achievement System Unit Preference Bug
-- This script cleans up incorrectly awarded achievements and prevents future issues

-- Step 1: Identify incorrectly awarded achievements (metric users with standard achievements)
-- First, let's see what we're dealing with
SELECT 
    ua.id,
    ua.user_id,
    u.username,
    u.prefer_metric,
    a.id as achievement_id,
    a.name as achievement_name,
    a.unit_preference as achievement_unit,
    ua.earned_at,
    ua.session_id
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
WHERE 
    -- Find metric users who got standard achievements OR standard users who got metric achievements
    (u.prefer_metric = true AND a.unit_preference = 'standard') OR
    (u.prefer_metric = false AND a.unit_preference = 'metric')
ORDER BY ua.earned_at DESC;

-- Step 2: Delete incorrectly awarded achievements
-- WARNING: This will delete achievements that don't match the user's unit preference
DELETE FROM user_achievements
WHERE id IN (
    SELECT ua.id
    FROM user_achievements ua
    JOIN public.user u ON ua.user_id = u.id
    JOIN achievements a ON ua.achievement_id = a.id
    WHERE 
        -- Delete achievements where unit preference doesn't match
        (u.prefer_metric = true AND a.unit_preference = 'standard') OR
        (u.prefer_metric = false AND a.unit_preference = 'metric')
);

-- Step 3: Find and delete mass-awarded achievements (more than 5 per session)
-- This identifies sessions where a user got an excessive number of achievements
WITH session_achievement_counts AS (
    SELECT 
        session_id,
        user_id,
        COUNT(*) as achievement_count,
        array_agg(achievement_id ORDER BY earned_at) as achievement_ids,
        array_agg(earned_at ORDER BY earned_at) as earned_times
    FROM user_achievements
    WHERE session_id IS NOT NULL
    GROUP BY session_id, user_id
    HAVING COUNT(*) > 5
)
SELECT 
    sac.*,
    rs.distance_km,
    rs.duration_seconds,
    u.username
FROM session_achievement_counts sac
JOIN ruck_session rs ON sac.session_id = rs.id
JOIN public.user u ON sac.user_id = u.id
ORDER BY achievement_count DESC;

-- Step 4: For safety, let's review the specific user mentioned in the bug report
SELECT 
    ua.id,
    ua.achievement_id,
    a.name,
    a.unit_preference,
    ua.earned_at,
    ua.session_id,
    ua.metadata
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
WHERE ua.user_id = '27264fea-0b23-4e16-93d3-31bed3871b5c'
ORDER BY ua.earned_at;

-- Step 5: Clean up the specific problematic achievements for this user
-- Only delete if you confirm these are wrong achievements
/*
DELETE FROM user_achievements 
WHERE user_id = '27264fea-0b23-4e16-93d3-31bed3871b5c'
AND achievement_id IN (89, 90, 91, 92, 93); -- These were likely the standard unit achievements
*/

-- Step 6: Add validation to prevent future issues
-- This ensures the achievement system respects unit preferences
-- (This is already implemented in the code changes)

-- Step 7: Verification queries
-- After cleanup, verify the fixes work:

-- Count achievements by unit preference to ensure balance
SELECT 
    u.prefer_metric,
    a.unit_preference,
    COUNT(*) as count
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
GROUP BY u.prefer_metric, a.unit_preference
ORDER BY u.prefer_metric, a.unit_preference;

-- Check for any remaining unit mismatches
SELECT COUNT(*) as remaining_mismatches
FROM user_achievements ua
JOIN public.user u ON ua.user_id = u.id
JOIN achievements a ON ua.achievement_id = a.id
WHERE 
    (u.prefer_metric = true AND a.unit_preference = 'standard') OR
    (u.prefer_metric = false AND a.unit_preference = 'metric');

-- USAGE INSTRUCTIONS:
-- 1. Run the SELECT queries first to see what will be affected
-- 2. Review the data carefully 
-- 3. Uncomment and run the DELETE statements only if you're confident
-- 4. Re-deploy the backend with the fixed achievement checking code
-- 5. Test with a new session to ensure achievements work correctly
