-- Award missing imperial achievements for user with sessions 3287 and 3209
-- Session 3287: 4.25km (2.64 miles), 42min, 30lbs (13.61kg)
-- Session 3209: 5.42km (3.37 miles), 55min, 28lbs (12.70kg)

-- 1. First Steps (ID: 1) - any completed ruck
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    (SELECT user_id FROM ruck_session WHERE id = 3287),
    1,
    3287,
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    NULL,
    jsonb_build_object('triggered_by_session', 3287, 'manual_award', true),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = (SELECT user_id FROM ruck_session WHERE id = 3287) AND achievement_id = 1
);

-- 2. One Mile Club (ID: 2) - imperial cumulative distance achievement
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    (SELECT user_id FROM ruck_session WHERE id = 3287),
    2,
    3287,
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    4.25,
    jsonb_build_object('triggered_by_session', 3287, 'manual_award', true, 'distance_km', 4.25),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = (SELECT user_id FROM ruck_session WHERE id = 3287) AND achievement_id = 2
);

-- 3. Mile Marker (ID: 11) - single session 1+ mile (1.6km)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    rs.user_id,
    11,
    rs.id,
    rs.completed_at,
    rs.distance_km,
    jsonb_build_object('triggered_by_session', rs.id, 'manual_award', true, 'distance_km', rs.distance_km),
    NOW()
FROM ruck_session rs
WHERE rs.id = 3287
AND rs.distance_km >= 1.6
AND NOT EXISTS (
    SELECT 1 FROM user_achievements ua
    WHERE ua.user_id = rs.user_id AND ua.achievement_id = 11
);

-- 4. Ten Mile Warrior (ID: 4) - 10 miles total (both sessions = 6.01 miles total)
-- Skip this one - user only has 6.01 miles total, needs 10 miles

-- 5. Weight 30lbs (ID: 72) - session 3287 has exactly 30 lbs
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    (SELECT user_id FROM ruck_session WHERE id = 3287),
    72,
    3287,
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    13.61,
    jsonb_build_object('triggered_by_session', 3287, 'manual_award', true, 'weight_kg', 13.61, 'weight_lbs', 30),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = (SELECT user_id FROM ruck_session WHERE id = 3287) AND achievement_id = 72
);

-- 6. Half Hour Hero (ID: 49) - 30+ minute ruck (both sessions qualify)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT
    (SELECT user_id FROM ruck_session WHERE id = 3287),
    49,
    3287,
    (SELECT completed_at FROM ruck_session WHERE id = 3287),
    2540,
    jsonb_build_object('triggered_by_session', 3287, 'manual_award', true, 'duration_seconds', 2540),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements
    WHERE user_id = (SELECT user_id FROM ruck_session WHERE id = 3287) AND achievement_id = 49
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