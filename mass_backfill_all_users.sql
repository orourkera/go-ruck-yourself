-- EMERGENCY: Mass backfill achievements for ALL affected users
-- This will award missing achievements to every user who qualifies

-- WARNING: This is a large-scale data operation. Test on a subset first!

-- 1. Backfill "First Steps" achievement for ALL users with completed sessions
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    first_sessions.user_id,
    1, -- First Steps achievement ID
    first_sessions.session_id,
    first_sessions.completed_at,
    NULL,
    jsonb_build_object(
        'triggered_by_session', first_sessions.session_id, 
        'backfilled', true, 
        'mass_backfill', true,
        'reason', 'System-wide achievement bug fix'
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id) 
        user_id,
        id as session_id,
        completed_at
    FROM ruck_session 
    WHERE status = 'completed'
        AND duration_seconds >= 300
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) first_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = first_sessions.user_id AND achievement_id = 1
);

-- 2. Backfill "Mile Marker" achievement (1.6km single session)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    qualifying_sessions.user_id,
    11, -- Mile Marker achievement ID
    qualifying_sessions.session_id,
    qualifying_sessions.completed_at,
    qualifying_sessions.distance_km,
    jsonb_build_object(
        'triggered_by_session', qualifying_sessions.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'distance_km', qualifying_sessions.distance_km
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id)
        user_id,
        id as session_id,
        completed_at,
        distance_km
    FROM ruck_session 
    WHERE status = 'completed' 
        AND distance_km >= 1.6
        AND duration_seconds >= 300
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) qualifying_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = qualifying_sessions.user_id AND achievement_id = 11
);

-- 3. Backfill "5K Finisher" achievement
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    qualifying_sessions.user_id,
    12, -- 5K Finisher achievement ID
    qualifying_sessions.session_id,
    qualifying_sessions.completed_at,
    qualifying_sessions.distance_km,
    jsonb_build_object(
        'triggered_by_session', qualifying_sessions.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'distance_km', qualifying_sessions.distance_km
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id)
        user_id,
        id as session_id,
        completed_at,
        distance_km
    FROM ruck_session 
    WHERE status = 'completed' 
        AND distance_km >= 5.0
        AND duration_seconds >= 300
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) qualifying_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = qualifying_sessions.user_id AND achievement_id = 12
);

-- 4. Backfill "Quick Start" achievement (15+ minutes)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    qualifying_sessions.user_id,
    48, -- Quick Start achievement ID
    qualifying_sessions.session_id,
    qualifying_sessions.completed_at,
    qualifying_sessions.duration_seconds,
    jsonb_build_object(
        'triggered_by_session', qualifying_sessions.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'duration_seconds', qualifying_sessions.duration_seconds
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id)
        user_id,
        id as session_id,
        completed_at,
        duration_seconds
    FROM ruck_session 
    WHERE status = 'completed' 
        AND duration_seconds >= 900
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) qualifying_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = qualifying_sessions.user_id AND achievement_id = 48
);

-- 5. Backfill "Half Hour Hero" achievement (30+ minutes)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    qualifying_sessions.user_id,
    49, -- Half Hour Hero achievement ID
    qualifying_sessions.session_id,
    qualifying_sessions.completed_at,
    qualifying_sessions.duration_seconds,
    jsonb_build_object(
        'triggered_by_session', qualifying_sessions.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'duration_seconds', qualifying_sessions.duration_seconds
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id)
        user_id,
        id as session_id,
        completed_at,
        duration_seconds
    FROM ruck_session 
    WHERE status = 'completed' 
        AND duration_seconds >= 1800
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) qualifying_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = qualifying_sessions.user_id AND achievement_id = 49
);

-- 6. Backfill "Getting Started" achievement (5km cumulative)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
WITH user_cumulative AS (
    SELECT 
        user_id,
        id as session_id,
        completed_at,
        SUM(distance_km) OVER (
            PARTITION BY user_id 
            ORDER BY created_at ASC 
            ROWS UNBOUNDED PRECEDING
        ) as cumulative_distance_km,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at ASC) as session_number
    FROM ruck_session 
    WHERE status = 'completed'
        AND duration_seconds >= 300
        AND distance_km >= 0.5
),
first_qualifying AS (
    SELECT DISTINCT ON (user_id)
        user_id,
        session_id,
        completed_at,
        cumulative_distance_km
    FROM user_cumulative
    WHERE cumulative_distance_km >= 5.0
    ORDER BY user_id, session_number ASC
)
SELECT 
    fq.user_id,
    3, -- Getting Started achievement ID
    fq.session_id,
    fq.completed_at,
    fq.cumulative_distance_km,
    jsonb_build_object(
        'triggered_by_session', fq.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'cumulative_distance_km', fq.cumulative_distance_km
    ),
    NOW()
FROM first_qualifying fq
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = fq.user_id AND achievement_id = 3
);

-- 7. Backfill "Featherweight" achievement (4.5kg+ weight)
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, progress_value, metadata, created_at)
SELECT 
    qualifying_sessions.user_id,
    61, -- Featherweight achievement ID
    qualifying_sessions.session_id,
    qualifying_sessions.completed_at,
    qualifying_sessions.ruck_weight_kg,
    jsonb_build_object(
        'triggered_by_session', qualifying_sessions.session_id,
        'backfilled', true,
        'mass_backfill', true,
        'ruck_weight_kg', qualifying_sessions.ruck_weight_kg
    ),
    NOW()
FROM (
    SELECT DISTINCT ON (user_id)
        user_id,
        id as session_id,
        completed_at,
        ruck_weight_kg
    FROM ruck_session 
    WHERE status = 'completed' 
        AND ruck_weight_kg >= 4.5
        AND duration_seconds >= 300
        AND distance_km >= 0.5
    ORDER BY user_id, created_at ASC
) qualifying_sessions
WHERE NOT EXISTS (
    SELECT 1 FROM user_achievements 
    WHERE user_id = qualifying_sessions.user_id AND achievement_id = 61
);

-- Final verification: Show the impact
SELECT 
    'MASS BACKFILL RESULTS' as result_type,
    COUNT(*) as total_achievements_awarded,
    COUNT(DISTINCT user_id) as users_affected,
    achievement_id,
    a.name as achievement_name
FROM user_achievements ua
JOIN achievements a ON a.id = ua.achievement_id
WHERE ua.metadata ? 'mass_backfill'
    AND ua.created_at >= NOW() - INTERVAL '1 hour'
GROUP BY achievement_id, a.name
ORDER BY total_achievements_awarded DESC;
