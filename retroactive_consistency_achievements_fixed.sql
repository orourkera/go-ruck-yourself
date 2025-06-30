-- Retroactive script to award missing consistency achievements
-- Simplified version with working PostgreSQL syntax

-- Daily Streak achievements (7, 14, 30 days)
-- Simple approach: Find max consecutive days with sessions
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
-- Award Daily Streak 7 days
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mds.user_id,
    'daily-streak-7' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM max_daily_streaks mds
WHERE mds.max_streak >= 7
    AND mds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-7'
    );

-- Award Daily Streak 14 days
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mds.user_id,
    'daily-streak-14' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM max_daily_streaks mds
WHERE mds.max_streak >= 14
    AND mds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-14'
    );

-- Award Daily Streak 30 days
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    mds.user_id,
    'daily-streak-30' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM max_daily_streaks mds
WHERE mds.max_streak >= 30
    AND mds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-30'
    );

-- Weekly Streak achievements (4 weeks)
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
    'weekly-streak-4' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM max_weekly_streaks mws
WHERE mws.max_streak >= 4
    AND mws.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'weekly-streak-4'
    );

-- Monthly Consistency (3+ sessions per month for 3+ months)
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
    'monthly-consistency-3' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM monthly_consistency mc
WHERE mc.consistent_months >= 3
    AND mc.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'monthly-consistency-3'
    );

-- Weekend Warrior (weekend sessions for 4+ consecutive weekends)
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
    'weekend-warrior-4' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM max_weekend_streaks mws
WHERE mws.max_streak >= 4
    AND mws.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'weekend-warrior-4'
    );

-- Pace Consistency (coefficient of variation < 0.15 for users with 10+ sessions)
WITH pace_consistency AS (
    SELECT 
        user_id,
        STDDEV(pace_per_km) / NULLIF(AVG(pace_per_km), 0) as pace_cv,
        COUNT(*) as total_sessions
    FROM ruck_session 
    WHERE status = 'completed'
        AND pace_per_km IS NOT NULL 
        AND pace_per_km > 0
        AND distance_km > 0
    GROUP BY user_id
    HAVING COUNT(*) >= 10
)
INSERT INTO user_achievements (user_id, achievement_id, earned_at, session_id)
SELECT DISTINCT 
    pc.user_id,
    'pace-consistency-10' as achievement_id,
    NOW() as earned_at,
    NULL as session_id
FROM pace_consistency pc
WHERE pc.pace_cv <= 0.15
    AND pc.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'pace-consistency-10'
    );

-- Show results
SELECT 'Consistency achievements awarded' as result, 
       achievement_id,
       COUNT(*) as count 
FROM user_achievements 
WHERE achievement_id IN (
    'daily-streak-7', 'daily-streak-14', 'daily-streak-30',
    'weekly-streak-4', 'monthly-consistency-3', 
    'weekend-warrior-4', 'pace-consistency-10'
)
AND earned_at >= NOW() - INTERVAL '1 minute'
GROUP BY achievement_id
ORDER BY achievement_id;
