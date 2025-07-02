-- PREVIEW SCRIPT: Shows what achievements would be backfilled
-- Run this first to see what would be awarded WITHOUT making changes
-- Backfill Achievements for Sessions Completed After June 30th 2025 15:05:45

-- First, let's see what sessions were completed after the retroactive process
WITH sessions_after_retroactive AS (
    SELECT 
        rs.*,
        u.username,
        u.prefer_metric,
        ROW_NUMBER() OVER (PARTITION BY rs.user_id ORDER BY rs.started_at) AS session_number
    FROM ruck_session rs
    LEFT JOIN "user" u ON rs.user_id = u.id
    WHERE rs.status = 'completed'
      AND rs.completed_at > '2025-06-30 15:05:45+00'::timestamptz
),

-- Get all active achievements
active_achievements AS (
    SELECT * FROM achievements WHERE is_active = true
),

-- Calculate user totals up to each session (for cumulative achievements)
user_session_totals AS (
    SELECT 
        sar.user_id,
        sar.id AS session_id,
        sar.started_at,
        -- Total sessions completed by this user up to this point
        (SELECT COUNT(*) 
         FROM ruck_session rs2 
         WHERE rs2.user_id = sar.user_id 
           AND rs2.status = 'completed' 
           AND rs2.started_at <= sar.started_at) AS total_sessions,
        -- Total distance by this user up to this point
        (SELECT COALESCE(SUM(rs2.distance_km), 0) 
         FROM ruck_session rs2 
         WHERE rs2.user_id = sar.user_id 
           AND rs2.status = 'completed' 
           AND rs2.started_at <= sar.started_at) AS total_distance_km,
        -- Total power points by this user up to this point
        (SELECT COALESCE(SUM(rs2.power_points), 0) 
         FROM ruck_session rs2 
         WHERE rs2.user_id = sar.user_id 
           AND rs2.status = 'completed' 
           AND rs2.started_at <= sar.started_at) AS total_power_points,
        -- Sessions before 6 AM count
        (SELECT COUNT(*) 
         FROM ruck_session rs2 
         WHERE rs2.user_id = sar.user_id 
           AND rs2.status = 'completed' 
           AND rs2.started_at <= sar.started_at
           AND EXTRACT(HOUR FROM rs2.started_at) < 6) AS sessions_before_6am,
        -- Sessions after 9 PM count  
        (SELECT COUNT(*) 
         FROM ruck_session rs2 
         WHERE rs2.user_id = sar.user_id 
           AND rs2.status = 'completed' 
           AND rs2.started_at <= sar.started_at
           AND EXTRACT(HOUR FROM rs2.started_at) >= 21) AS sessions_after_9pm
    FROM sessions_after_retroactive sar
),

-- Generate achievement awards for post-June 30th sessions
achievement_awards AS (
    SELECT DISTINCT ON (sar.user_id, aa.id)
        sar.user_id,
        sar.username,
        aa.id AS achievement_id,
        aa.name AS achievement_name,
        aa.description AS achievement_description,
        sar.id AS session_id,
        sar.completed_at AS earned_at,
        jsonb_build_object(
            'triggered_by_session', sar.id,
            'backfill_reason', 'post_june30_sessions',
            'session_completed_at', sar.completed_at
        ) AS metadata
    FROM sessions_after_retroactive sar
    CROSS JOIN active_achievements aa
    LEFT JOIN user_session_totals ust ON sar.id = ust.session_id
    WHERE 
        -- Ensure user doesn't already have this achievement
        NOT EXISTS (
            SELECT 1 FROM user_achievements ua 
            WHERE ua.user_id = sar.user_id 
            AND ua.achievement_id = aa.id
        )
        AND
        -- Check achievement criteria based on the session or user totals at time of session
        (
            -- First ruck achievement (if this was their first completed session ever)
            (aa.criteria->>'type' = 'first_ruck' AND ust.total_sessions = 1)
            
            OR
            
            -- Single session distance achievements
            (aa.criteria->>'type' = 'single_session_distance' 
             AND sar.distance_km >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Session weight achievements
            (aa.criteria->>'type' = 'session_weight' 
             AND sar.ruck_weight_kg >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Elevation gain achievements
            (aa.criteria->>'type' = 'elevation_gain' 
             AND sar.elevation_gain_m >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Session duration achievements
            (aa.criteria->>'type' = 'session_duration' 
             AND sar.duration_seconds >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Pace faster than achievements
            (aa.criteria->>'type' = 'pace_faster_than' 
             AND sar.average_pace <= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Pace slower than achievements
            (aa.criteria->>'type' = 'pace_slower_than' 
             AND sar.average_pace >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Cumulative distance achievements (total distance at time of this session)
            (aa.criteria->>'type' = 'cumulative_distance' 
             AND ust.total_distance_km >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Power points achievements (total power points at time of this session)
            (aa.criteria->>'type' = 'power_points' 
             AND ust.total_power_points >= (aa.criteria->>'target')::decimal)
            
            OR
            
            -- Early bird achievements (before 6 AM)
            (aa.criteria->>'type' = 'time_of_day' 
             AND aa.criteria ? 'before_hour'
             AND (aa.criteria->>'before_hour')::integer = 6
             AND ust.sessions_before_6am >= (aa.criteria->>'target')::integer)
            
            OR
            
            -- Night owl achievements (after 9 PM)
            (aa.criteria->>'type' = 'time_of_day' 
             AND aa.criteria ? 'after_hour'
             AND (aa.criteria->>'after_hour')::integer = 21
             AND ust.sessions_after_9pm >= (aa.criteria->>'target')::integer)
        )
    ORDER BY sar.user_id, aa.id, sar.started_at
)

-- Preview what would be awarded (combined results)
SELECT * FROM (
    SELECT 
        'PREVIEW: Achievements that would be awarded:' AS notice,
        username,
        user_id,
        achievement_name,
        achievement_description,
        session_id,
        earned_at,
        NULL::bigint AS achievements_to_award,
        NULL::bigint AS total_count
    FROM achievement_awards
    
    UNION ALL
    
    -- Show count by user
    SELECT 
        'COUNT BY USER:' AS notice,
        username,
        user_id,
        NULL AS achievement_name,
        NULL AS achievement_description,
        NULL AS session_id,
        NULL AS earned_at,
        COUNT(*) AS achievements_to_award,
        NULL::bigint AS total_count
    FROM achievement_awards
    GROUP BY username, user_id
    
    UNION ALL
    
    -- Show total count
    SELECT 
        'TOTAL COUNT:' AS notice,
        NULL AS username,
        NULL AS user_id,
        NULL AS achievement_name,
        NULL AS achievement_description,
        NULL AS session_id,
        NULL AS earned_at,
        NULL::bigint AS achievements_to_award,
        COUNT(*) AS total_count
    FROM achievement_awards
) results
ORDER BY 
    CASE notice 
        WHEN 'PREVIEW: Achievements that would be awarded:' THEN 1
        WHEN 'COUNT BY USER:' THEN 2
        WHEN 'TOTAL COUNT:' THEN 3
    END,
    username, 
    earned_at;

-- TO ACTUALLY INSERT THE ACHIEVEMENTS:
-- Run the separate file: backfill_insert_achievements.sql
-- That file contains the complete INSERT script with sequence fix.
