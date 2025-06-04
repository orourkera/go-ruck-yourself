-- Backfill User Achievements SQL Script
-- This script awards achievements to users based on their existing ruck session data

WITH 
-- Get all active achievements
active_achievements AS (
    SELECT * FROM achievements WHERE is_active = true
),

-- Get all completed sessions with user data
completed_sessions AS (
    SELECT 
        rs.*,
        u.prefer_metric,
        ROW_NUMBER() OVER (PARTITION BY rs.user_id ORDER BY rs.started_at) AS session_number
    FROM ruck_session rs
    LEFT JOIN "user" u ON rs.user_id = u.id
    WHERE rs.status = 'completed'
),

-- Calculate cumulative distances for each user up to each session
user_cumulative_distance AS (
    SELECT 
        user_id,
        id AS session_id,
        SUM(distance_km) OVER (
            PARTITION BY user_id 
            ORDER BY started_at 
            ROWS UNBOUNDED PRECEDING
        ) AS cumulative_distance_km
    FROM completed_sessions
),

-- Get session counts by time of day for each user
early_bird_counts AS (
    SELECT 
        user_id,
        id AS session_id,
        COUNT(*) OVER (
            PARTITION BY user_id 
            ORDER BY started_at 
            ROWS UNBOUNDED PRECEDING
        ) AS sessions_before_6am
    FROM completed_sessions
    WHERE EXTRACT(HOUR FROM started_at) < 6
),

night_owl_counts AS (
    SELECT 
        user_id,
        id AS session_id,
        COUNT(*) OVER (
            PARTITION BY user_id 
            ORDER BY started_at 
            ROWS UNBOUNDED PRECEDING
        ) AS sessions_after_9pm
    FROM completed_sessions
    WHERE EXTRACT(HOUR FROM started_at) >= 21
),

-- Generate achievement awards
achievement_awards AS (
    SELECT DISTINCT ON (cs.user_id, aa.id)
        cs.user_id,
        aa.id AS achievement_id,
        cs.id AS session_id,
        cs.started_at AS earned_at,
        jsonb_build_object('triggered_by_session', cs.id) AS metadata
    FROM completed_sessions cs
    CROSS JOIN active_achievements aa
    LEFT JOIN user_cumulative_distance ucd ON cs.id = ucd.session_id
    LEFT JOIN early_bird_counts ebc ON cs.id = ebc.session_id
    LEFT JOIN night_owl_counts noc ON cs.id = noc.session_id
    WHERE 
        -- Ensure user doesn't already have this achievement
        NOT EXISTS (
            SELECT 1 FROM user_achievements ua 
            WHERE ua.user_id = cs.user_id 
            AND ua.achievement_id = aa.id
        )
        AND
        -- Check achievement criteria
        (
            -- First ruck achievement
            (aa.criteria->>'type' = 'first_ruck' AND cs.session_number = 1)
            
            OR
            
            -- Single session distance achievements
            (aa.criteria->>'type' = 'single_session_distance' 
             AND cs.distance_km >= (aa.criteria->>'target')::decimal
             AND (aa.unit_preference IS NULL OR aa.unit_preference = CASE WHEN cs.prefer_metric THEN 'metric' ELSE 'standard' END))
            
            OR
            
            -- Session weight achievements
            (aa.criteria->>'type' = 'session_weight' 
             AND cs.ruck_weight_kg >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Power points achievements
            (aa.criteria->>'type' = 'power_points' 
             AND cs.power_points >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Elevation gain achievements
            (aa.criteria->>'type' = 'elevation_gain' 
             AND cs.elevation_gain_m >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Session duration achievements
            (aa.criteria->>'type' = 'session_duration' 
             AND cs.duration_seconds >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Pace faster than achievements
            (aa.criteria->>'type' = 'pace_faster_than' 
             AND cs.average_pace <= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Pace slower than achievements
            (aa.criteria->>'type' = 'pace_slower_than' 
             AND cs.average_pace >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Cumulative distance achievements
            (aa.criteria->>'type' = 'cumulative_distance' 
             AND ucd.cumulative_distance_km >= (aa.criteria->>'target')::decimal
             AND (aa.unit_preference IS NULL OR aa.unit_preference = CASE WHEN cs.prefer_metric THEN 'metric' ELSE 'standard' END))
            
            OR
            
            -- Early bird achievements (before 6 AM)
            (aa.criteria->>'type' = 'time_of_day' 
             AND aa.criteria ? 'before_hour'
             AND (aa.criteria->>'before_hour')::integer = 6
             AND ebc.sessions_before_6am >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Night owl achievements (after 9 PM)
            (aa.criteria->>'type' = 'time_of_day' 
             AND aa.criteria ? 'after_hour'
             AND (aa.criteria->>'after_hour')::integer = 21
             AND noc.sessions_after_9pm >= (aa.criteria->>'target')::integer)
        )
    ORDER BY cs.user_id, aa.id, cs.started_at
)

-- Insert the achievement awards
INSERT INTO user_achievements (user_id, achievement_id, session_id, earned_at, metadata)
SELECT 
    user_id,
    achievement_id,
    session_id,
    earned_at,
    metadata
FROM achievement_awards
ORDER BY user_id, earned_at;

-- Show summary of what was backfilled
SELECT 
    u.username,
    aa.user_id,
    COUNT(*) AS achievements_awarded
FROM achievement_awards aa
LEFT JOIN "user" u ON aa.user_id = u.id
GROUP BY u.username, aa.user_id
ORDER BY achievements_awarded DESC;

-- Show total count
SELECT COUNT(*) AS total_achievements_backfilled FROM achievement_awards;
