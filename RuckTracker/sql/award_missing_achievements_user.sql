-- Award missing achievements for user with sessions 3287 and 3209
-- Based on session data: 3287 (4.25km, 42min, 30lbs), 3209 (5.42km, 55min, 28lbs)

-- 1. First Steps (any completed ruck) - use earliest session
WITH user_session AS (
    SELECT user_id FROM ruck_session WHERE id = 3287
)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    us.user_id,
    1, -- First Steps achievement ID
    3287, -- Earlier session
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    NULL,
    jsonb_build_object(
        'triggered_by_session', 3287,
        'manual_award', true,
        'reason', 'Missing achievement backfill'
    ),
    NOW()
FROM user_session us
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = us.user_id AND achievement_id = 1
);

-- 2. Mile Marker (1.6km+) - session 3287 has 4.25km
WITH user_session AS (
    SELECT user_id FROM ruck_session WHERE id = 3287
)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    us.user_id,
    11, -- Mile Marker achievement ID (based on mass backfill pattern)
    3287,
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    4.25,
    jsonb_build_object(
        'triggered_by_session', 3287,
        'manual_award', true,
        'distance_km', 4.25
    ),
    NOW()
FROM user_session us
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = us.user_id AND achievement_id = 11
);

-- 3. 5K Finisher (5km+) - session 3209 has 5.42km
WITH user_session AS (
    SELECT user_id FROM ruck_session WHERE id = 3287
)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    us.user_id,
    12, -- 5K Finisher achievement ID
    3209,
    (SELECT completed_at FROM ruck_session WHERE id = 3209),
    5.42,
    jsonb_build_object(
        'triggered_by_session', 3209,
        'manual_award', true,
        'distance_km', 5.42
    ),
    NOW()
FROM user_session us
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = us.user_id AND achievement_id = 12
);

-- Verify the achievements were awarded
SELECT
    a.name,
    a.achievement_key,
    ua.earned_at,
    ua.session_id,
    rs.distance_km,
    rs.duration_seconds
FROM user_achievements ua
JOIN achievements a ON a.id = ua.achievement_id
JOIN ruck_session rs ON rs.id = ua.session_id
WHERE ua.user_id = (SELECT user_id FROM ruck_session WHERE id = 3287)
AND (a.unit_preference IS NULL OR a.unit_preference = 'imperial')
ORDER BY ua.earned_at;