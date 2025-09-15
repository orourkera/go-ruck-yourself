-- Check what achievements this user already has and what they're missing

-- Show all achievements this user currently has
SELECT
    'CURRENT ACHIEVEMENTS' as status,
    a.id,
    a.achievement_key,
    a.name,
    a.unit_preference,
    ua.session_id,
    ua.earned_at
FROM user_achievements ua
JOIN achievements a ON a.id = ua.achievement_id
WHERE ua.user_id = (SELECT user_id FROM ruck_session WHERE id = 3287)
ORDER BY ua.earned_at;

-- Check specifically for Mile Marker and One Mile Club
SELECT
    'CHECKING MILE ACHIEVEMENTS' as status,
    a.id,
    a.achievement_key,
    a.name,
    a.unit_preference,
    a.is_active,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM user_achievements ua
            WHERE ua.user_id = (SELECT user_id FROM ruck_session WHERE id = 3287)
            AND ua.achievement_id = a.id
        ) THEN 'USER HAS THIS'
        ELSE 'USER MISSING THIS'
    END as user_status
FROM achievements a
WHERE a.id IN (2, 11) -- One Mile Club, Mile Marker
ORDER BY a.id;