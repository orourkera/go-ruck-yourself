-- Retroactive script to award missing consistency achievements
-- Using proper achievement IDs from achievements table

-- First, let's see what achievements exist
-- SELECT id, name, achievement_key FROM achievements WHERE achievement_key LIKE '%streak%' OR achievement_key LIKE '%consistency%' OR achievement_key LIKE '%warrior%';

-- Daily Streak achievements using actual achievement IDs
WITH daily_sessions AS (
    SELECT DISTINCT 
        user_id,
        DATE(started_at) as session_date
    FROM ruck_session 
    WHERE status = 'completed'
    ORDER BY user_id, session_date
),
daily_streaks AS (
    SELECT 
        user_id,
        session_date,
        session_date - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY session_date))::int as streak_group
    FROM daily_sessions
),
max_daily_streaks AS (
    SELECT 
        user_id,
        MAX(streak_count) as max_streak
    FROM (
        SELECT 
            user_id, 
            streak_group,
            COUNT(*) as streak_count
        FROM daily_streaks
        GROUP BY user_id, streak_group
    ) grouped_streaks
    GROUP BY user_id
)
-- Award Daily Streak achievements (using achievement IDs from achievements table)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mds.user_id,
    a.id as achievement_id,
    NOW() as earned_at,
    NULL::integer as session_id
FROM max_daily_streaks mds
CROSS JOIN achievements a
WHERE a.achievement_key IN ('daily-streak-7', 'daily-streak-14', 'daily-streak-30')
    AND a.is_active = true
    AND (
        (a.achievement_key = 'daily-streak-7' AND mds.max_streak >= 7) OR
        (a.achievement_key = 'daily-streak-14' AND mds.max_streak >= 14) OR
        (a.achievement_key = 'daily-streak-30' AND mds.max_streak >= 30)
    )
    AND NOT EXISTS (
        SELECT 1 FROM user_achievements ua 
        WHERE ua.user_id = mds.user_id AND ua.achievement_id = a.id
    );

-- Weekly Streak achievements
WITH weekly_sessions AS (
    SELECT DISTINCT 
        user_id,
        DATE_TRUNC('week', started_at) as week_start
    FROM ruck_session 
    WHERE status = 'completed'
    ORDER BY user_id, week_start
),
weekly_streaks AS (
    SELECT 
        user_id,
        week_start,
        week_start - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY week_start) * INTERVAL '1 week') as streak_group
    FROM weekly_sessions
),
max_weekly_streaks AS (
    SELECT 
        user_id,
        MAX(streak_count) as max_streak
    FROM (
        SELECT 
            user_id, 
            streak_group,
            COUNT(*) as streak_count
        FROM weekly_streaks
        GROUP BY user_id, streak_group
    ) grouped_streaks
    GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mws.user_id,
    a.id as achievement_id,
    NOW() as earned_at,
    NULL::integer as session_id
FROM max_weekly_streaks mws
CROSS JOIN achievements a
WHERE a.achievement_key IN ('weekly-streak-4', 'weekly-streak-8', 'weekly-streak-12')
    AND a.is_active = true
    AND (
        (a.achievement_key = 'weekly-streak-4' AND mws.max_streak >= 4) OR
        (a.achievement_key = 'weekly-streak-8' AND mws.max_streak >= 8) OR
        (a.achievement_key = 'weekly-streak-12' AND mws.max_streak >= 12)
    )
    AND NOT EXISTS (
        SELECT 1 FROM user_achievements ua 
        WHERE ua.user_id = mws.user_id AND ua.achievement_id = a.id
    );

-- Monthly Consistency
WITH monthly_consistency AS (
    SELECT 
        user_id,
        COUNT(*) as consistent_months
    FROM (
        SELECT 
            user_id,
            DATE_TRUNC('month', started_at) as month_start,
            COUNT(*) as sessions_in_month
        FROM ruck_session 
        WHERE status = 'completed'
        GROUP BY user_id, DATE_TRUNC('month', started_at)
        HAVING COUNT(*) >= 3
    ) monthly_sessions
    GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mc.user_id,
    a.id as achievement_id,
    NOW() as earned_at,
    NULL::integer as session_id
FROM monthly_consistency mc
CROSS JOIN achievements a
WHERE a.achievement_key IN ('monthly-consistency-3', 'monthly-consistency-6', 'monthly-consistency-12')
    AND a.is_active = true
    AND (
        (a.achievement_key = 'monthly-consistency-3' AND mc.consistent_months >= 3) OR
        (a.achievement_key = 'monthly-consistency-6' AND mc.consistent_months >= 6) OR
        (a.achievement_key = 'monthly-consistency-12' AND mc.consistent_months >= 12)
    )
    AND NOT EXISTS (
        SELECT 1 FROM user_achievements ua 
        WHERE ua.user_id = mc.user_id AND ua.achievement_id = a.id
    );

-- Weekend Warrior
WITH weekend_sessions AS (
    SELECT DISTINCT 
        user_id,
        DATE_TRUNC('week', started_at) as week_start
    FROM ruck_session 
    WHERE status = 'completed'
        AND EXTRACT(DOW FROM started_at) IN (0, 6) -- Sunday = 0, Saturday = 6
    ORDER BY user_id, week_start
),
weekend_streaks AS (
    SELECT 
        user_id,
        week_start,
        week_start - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY week_start) * INTERVAL '1 week') as streak_group
    FROM weekend_sessions
),
max_weekend_streaks AS (
    SELECT 
        user_id,
        MAX(streak_count) as max_streak
    FROM (
        SELECT 
            user_id, 
            streak_group,
            COUNT(*) as streak_count
        FROM weekend_streaks
        GROUP BY user_id, streak_group
    ) grouped_streaks
    GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mws.user_id,
    a.id as achievement_id,
    NOW() as earned_at,
    NULL::integer as session_id
FROM max_weekend_streaks mws
CROSS JOIN achievements a
WHERE a.achievement_key IN ('weekend-warrior-4', 'weekend-warrior-8', 'weekend-warrior-12')
    AND a.is_active = true
    AND (
        (a.achievement_key = 'weekend-warrior-4' AND mws.max_streak >= 4) OR
        (a.achievement_key = 'weekend-warrior-8' AND mws.max_streak >= 8) OR
        (a.achievement_key = 'weekend-warrior-12' AND mws.max_streak >= 12)
    )
    AND NOT EXISTS (
        SELECT 1 FROM user_achievements ua 
        WHERE ua.user_id = mws.user_id AND ua.achievement_id = a.id
    );

-- Pace Consistency
WITH pace_consistency AS (
    SELECT 
        user_id,
        STDDEV(average_pace) / NULLIF(AVG(average_pace), 0) as pace_cv,
        COUNT(*) as total_sessions
    FROM ruck_session 
    WHERE status = 'completed'
        AND average_pace IS NOT NULL 
        AND average_pace > 0
        AND distance_km > 0
    GROUP BY user_id
    HAVING COUNT(*) >= 10
)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    pc.user_id,
    a.id as achievement_id,
    NOW() as earned_at,
    NULL::integer as session_id
FROM pace_consistency pc
CROSS JOIN achievements a
WHERE a.achievement_key IN ('pace-consistency-10', 'pace-consistency-20', 'pace-consistency-50')
    AND a.is_active = true
    AND (
        (a.achievement_key = 'pace-consistency-10' AND pc.pace_cv <= 0.15 AND pc.total_sessions >= 10) OR
        (a.achievement_key = 'pace-consistency-20' AND pc.pace_cv <= 0.12 AND pc.total_sessions >= 20) OR
        (a.achievement_key = 'pace-consistency-50' AND pc.pace_cv <= 0.10 AND pc.total_sessions >= 50)
    )
    AND NOT EXISTS (
        SELECT 1 FROM user_achievements ua 
        WHERE ua.user_id = pc.user_id AND ua.achievement_id = a.id
    );

-- Show results
SELECT 'Consistency achievements awarded' as result, 
       a.name as achievement_name,
       a.achievement_key as achievement_achievement_key,
       COUNT(*) as count 
FROM user_achievements ua
JOIN achievements a ON ua.achievement_id = a.id
WHERE a.achievement_key IN (
    'daily-streak-7', 'daily-streak-14', 'daily-streak-30',
    'weekly-streak-4', 'weekly-streak-8', 'weekly-streak-12',
    'monthly-consistency-3', 'monthly-consistency-6', 'monthly-consistency-12', 
    'weekend-warrior-4', 'weekend-warrior-8', 'weekend-warrior-12',
    'pace-consistency-10', 'pace-consistency-20', 'pace-consistency-50'
)
AND ua.earned_at >= NOW() - INTERVAL '1 minute'
GROUP BY a.id, a.name, a.achievement_key
ORDER BY a.achievement_key;
