-- Check what's in user_coaching_plans
SELECT
    id,
    user_id,
    coaching_plan_id,
    coaching_personality,
    start_date,
    current_status,
    created_at
FROM user_coaching_plans
WHERE current_status = 'active';

-- To delete old/test coaching plans for a specific user:
-- UPDATE user_coaching_plans
-- SET current_status = 'archived'
-- WHERE user_id = 'YOUR_USER_ID_HERE'
-- AND current_status = 'active';

-- Or to completely remove them:
-- DELETE FROM user_coaching_plans
-- WHERE user_id = 'YOUR_USER_ID_HERE';