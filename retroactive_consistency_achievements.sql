-- Retroactive script to award missing consistency achievements
-- This script calculates streaks and consistency metrics to award missing achievements

-- Daily Streak achievements (7, 14, 30 days)
WITH daily_streaks AS (
    SELECT 
        user_id,
        MAX(streak_length) as max_daily_streak
    FROM (
        SELECT 
            user_id,
            session_date,
            COUNT(*) as streak_length
        FROM (
            SELECT DISTINCT 
                user_id,
                DATE(session_start_time) as session_date,
                DATE(session_start_time) - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY DATE(session_start_time)) || ' days')::INTERVAL as streak_group
            FROM ruck_session 
            WHERE session_status = 'completed'
        ) dated_sessions
        GROUP BY user_id, streak_group
    ) streak_calc
    GROUP BY user_id
)
-- Award Daily Streak 7 days
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    ds.user_id,
    'daily-streak-7' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM daily_streaks ds
WHERE ds.max_daily_streak >= 7
    AND ds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-7'
    );

-- Award Daily Streak 14 days
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    ds.user_id,
    'daily-streak-14' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM daily_streaks ds
WHERE ds.max_daily_streak >= 14
    AND ds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-14'
    );

-- Award Daily Streak 30 days
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    ds.user_id,
    'daily-streak-30' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM daily_streaks ds
WHERE ds.max_daily_streak >= 30
    AND ds.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'daily-streak-30'
    );

-- Weekly Streak achievements (4, 8, 12 weeks)
WITH weekly_streaks AS (
    SELECT 
        user_id,
        MAX(weekly_streak) as max_weekly_streak
    FROM (
        SELECT 
            user_id,
            week_year,
            COUNT(*) as weekly_streak
        FROM (
            SELECT DISTINCT 
                user_id,
                EXTRACT(YEAR FROM session_start_time)::text || '-' || EXTRACT(WEEK FROM session_start_time)::text as week_year,
                DATE_TRUNC('week', session_start_time) - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('week', session_start_time)) || ' weeks')::INTERVAL as week_group
            FROM ruck_session 
            WHERE session_status = 'completed'
        ) weekly_sessions
        GROUP BY user_id, week_group
    ) week_calc
    GROUP BY user_id
)
-- Award Weekly Streak 4 weeks
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    ws.user_id,
    'weekly-streak-4' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM weekly_streaks ws
WHERE ws.max_weekly_streak >= 4
    AND ws.user_id NOT IN (
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
            EXTRACT(YEAR FROM session_start_time) as year,
            EXTRACT(MONTH FROM session_start_time) as month,
            COUNT(*) as sessions_in_month
        FROM ruck_session 
        WHERE session_status = 'completed'
        GROUP BY user_id, EXTRACT(YEAR FROM session_start_time), EXTRACT(MONTH FROM session_start_time)
        HAVING COUNT(*) >= 3
    ) monthly_sessions
    GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    mc.user_id,
    'monthly-consistency-3' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM monthly_consistency mc
WHERE mc.consistent_months >= 3
    AND mc.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'monthly-consistency-3'
    );

-- Weekend Warrior (weekend sessions for 4+ consecutive weekends)
WITH weekend_streaks AS (
    SELECT 
        user_id,
        MAX(weekend_streak) as max_weekend_streak
    FROM (
        SELECT 
            user_id,
            weekend_date,
            COUNT(*) as weekend_streak
        FROM (
            SELECT DISTINCT 
                user_id,
                DATE_TRUNC('week', session_start_time) as weekend_date,
                DATE_TRUNC('week', session_start_time) - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY DATE_TRUNC('week', session_start_time)) || ' weeks')::INTERVAL as weekend_group
            FROM ruck_session 
            WHERE session_status = 'completed'
                AND EXTRACT(DOW FROM session_start_time) IN (0, 6) -- Sunday = 0, Saturday = 6
        ) weekend_sessions
        GROUP BY user_id, weekend_group
    ) weekend_calc
    GROUP BY user_id
)
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    ws.user_id,
    'weekend-warrior-4' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM weekend_streaks ws
WHERE ws.max_weekend_streak >= 4
    AND ws.user_id NOT IN (
        SELECT user_id FROM user_achievements WHERE achievement_id = 'weekend-warrior-4'
    );

-- Pace Consistency (coefficient of variation < 0.15 for users with 10+ sessions)
WITH pace_consistency AS (
    SELECT 
        user_id,
        STDDEV(pace_per_km) / AVG(pace_per_km) as pace_cv,
        COUNT(*) as total_sessions
    FROM ruck_session 
    WHERE session_status = 'completed'
        AND pace_per_km IS NOT NULL 
        AND pace_per_km > 0
        AND distance_km > 0
    GROUP BY user_id
    HAVING COUNT(*) >= 10
)
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    pc.user_id,
    'pace-consistency-10' as achievement_id,
    NOW() as earned_date,
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
AND earned_date >= NOW() - INTERVAL '1 minute'
GROUP BY achievement_id
ORDER BY achievement_id;
