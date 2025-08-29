-- Analyze sessions in "created" state and check for other sessions from same user on same day
-- This helps identify orphaned sessions, duplicates, or session creation issues

WITH created_sessions AS (
    -- Get all sessions currently in "created" state
    SELECT 
        id,
        user_id,
        status,
        created_at,
        DATE(created_at) as created_date,
        ruck_weight_kg,
        weight_kg,
        is_manual,
        is_guided_session
    FROM ruck_session 
    WHERE status = 'created'
),
same_day_sessions AS (
    -- Find all sessions from the same user on the same day as each created session
    SELECT 
        cs.id as created_session_id,
        cs.user_id,
        cs.created_date,
        cs.ruck_weight_kg as created_ruck_weight,
        cs.weight_kg as created_weight,
        cs.is_manual as created_is_manual,
        cs.is_guided_session as created_is_guided,
        -- Other sessions from same user on same day
        rs.id as other_session_id,
        rs.status as other_session_status,
        rs.created_at as other_created_at,
        rs.started_at as other_started_at,
        rs.completed_at as other_completed_at,
        rs.distance_km as other_distance_km,
        rs.duration_seconds as other_duration_seconds,
        rs.ruck_weight_kg as other_ruck_weight,
        rs.weight_kg as other_weight,
        rs.is_manual as other_is_manual,
        rs.is_guided_session as other_is_guided,
        -- Calculate time difference between sessions
        EXTRACT(EPOCH FROM (rs.created_at - cs.created_at)) as seconds_between_sessions
    FROM created_sessions cs
    LEFT JOIN ruck_session rs ON 
        cs.user_id = rs.user_id 
        AND DATE(cs.created_at) = DATE(rs.created_at)
        AND cs.id != rs.id  -- Exclude the created session itself
),
session_summary AS (
    -- Summarize the findings for each created session
    SELECT 
        created_session_id,
        user_id,
        created_date,
        created_ruck_weight,
        created_weight,
        created_is_manual,
        created_is_guided,
        -- Count other sessions by status
        COUNT(*) as total_other_sessions,
        COUNT(CASE WHEN other_session_status = 'created' THEN 1 END) as other_created_sessions,
        COUNT(CASE WHEN other_session_status = 'in_progress' THEN 1 END) as other_in_progress_sessions,
        COUNT(CASE WHEN other_session_status = 'completed' THEN 1 END) as other_completed_sessions,
        COUNT(CASE WHEN other_session_status = 'paused' THEN 1 END) as other_paused_sessions,
        -- Get details of the most recent other session
        MAX(other_session_id) as most_recent_other_session_id,
        MAX(other_session_status) as most_recent_other_status,
        MAX(other_created_at) as most_recent_other_created_at,
        MAX(other_started_at) as most_recent_other_started_at,
        MAX(other_completed_at) as most_recent_other_completed_at,
        MAX(other_distance_km) as most_recent_other_distance_km,
        MAX(other_duration_seconds) as most_recent_other_duration_seconds,
        -- Time analysis
        MIN(seconds_between_sessions) as min_seconds_between_sessions,
        MAX(seconds_between_sessions) as max_seconds_between_sessions,
        AVG(seconds_between_sessions) as avg_seconds_between_sessions
    FROM same_day_sessions
    GROUP BY 
        created_session_id,
        user_id,
        created_date,
        created_ruck_weight,
        created_weight,
        created_is_manual,
        created_is_guided
)
-- Final analysis with categorization
SELECT 
    created_session_id,
    user_id,
    created_date,
    created_ruck_weight,
    created_weight,
    created_is_manual,
    created_is_guided,
    total_other_sessions,
    other_created_sessions,
    other_in_progress_sessions,
    other_completed_sessions,
    other_paused_sessions,
    most_recent_other_session_id,
    most_recent_other_status,
    most_recent_other_created_at,
    most_recent_other_started_at,
    most_recent_other_completed_at,
    most_recent_other_distance_km,
    most_recent_other_duration_seconds,
    -- Format time differences for readability
    CASE 
        WHEN min_seconds_between_sessions IS NOT NULL THEN 
            CONCAT(
                FLOOR(min_seconds_between_sessions / 3600), 'h ',
                FLOOR((min_seconds_between_sessions % 3600) / 60), 'm'
            )
        ELSE NULL 
    END as min_time_between_sessions,
    CASE 
        WHEN max_seconds_between_sessions IS NOT NULL THEN 
            CONCAT(
                FLOOR(max_seconds_between_sessions / 3600), 'h ',
                FLOOR((max_seconds_between_sessions % 3600) / 60), 'm'
            )
        ELSE NULL 
    END as max_time_between_sessions,
    -- Categorize the situation
    CASE 
        WHEN total_other_sessions = 0 THEN 'ORPHANED - No other sessions same day'
        WHEN other_completed_sessions > 0 THEN 'DUPLICATE - User completed another session'
        WHEN other_in_progress_sessions > 0 THEN 'CONFLICT - User has active session'
        WHEN other_created_sessions > 0 THEN 'MULTIPLE_CREATED - Multiple created sessions'
        WHEN other_paused_sessions > 0 THEN 'PAUSED_EXISTS - User has paused session'
        ELSE 'UNKNOWN'
    END as situation_category,
    -- Recommendations
    CASE 
        WHEN total_other_sessions = 0 THEN 'Safe to delete - no conflicts'
        WHEN other_completed_sessions > 0 THEN 'Delete created session - user completed another'
        WHEN other_in_progress_sessions > 0 THEN 'Investigate - user has active session'
        WHEN other_created_sessions > 0 THEN 'Clean up duplicates - keep most recent'
        WHEN other_paused_sessions > 0 THEN 'Check if user wants to resume paused session'
        ELSE 'Manual review needed'
    END as recommendation
FROM session_summary
ORDER BY 
    created_date DESC,
    total_other_sessions DESC,
    created_session_id DESC;

-- Summary statistics
WITH created_sessions AS (
    -- Get all sessions currently in "created" state
    SELECT 
        id,
        user_id,
        status,
        created_at,
        DATE(created_at) as created_date,
        ruck_weight_kg,
        weight_kg,
        is_manual,
        is_guided_session
    FROM ruck_session 
    WHERE status = 'created'
),
same_day_sessions AS (
    -- Find all sessions from the same user on the same day as each created session
    SELECT 
        cs.id as created_session_id,
        cs.user_id,
        cs.created_date,
        cs.ruck_weight_kg as created_ruck_weight,
        cs.weight_kg as created_weight,
        cs.is_manual as created_is_manual,
        cs.is_guided_session as created_is_guided,
        -- Other sessions from same user on same day
        rs.id as other_session_id,
        rs.status as other_session_status,
        rs.created_at as other_created_at,
        rs.started_at as other_started_at,
        rs.completed_at as other_completed_at,
        rs.distance_km as other_distance_km,
        rs.duration_seconds as other_duration_seconds,
        rs.ruck_weight_kg as other_ruck_weight,
        rs.weight_kg as other_weight,
        rs.is_manual as other_is_manual,
        rs.is_guided_session as other_is_guided,
        -- Calculate time difference between sessions
        EXTRACT(EPOCH FROM (rs.created_at - cs.created_at)) as seconds_between_sessions
    FROM created_sessions cs
    LEFT JOIN ruck_session rs ON 
        cs.user_id = rs.user_id 
        AND DATE(cs.created_at) = DATE(rs.created_at)
        AND cs.id != rs.id  -- Exclude the created session itself
),
session_summary AS (
    -- Summarize the findings for each created session
    SELECT 
        created_session_id,
        user_id,
        created_date,
        created_ruck_weight,
        created_weight,
        created_is_manual,
        created_is_guided,
        -- Count other sessions by status
        COUNT(*) as total_other_sessions,
        COUNT(CASE WHEN other_session_status = 'created' THEN 1 END) as other_created_sessions,
        COUNT(CASE WHEN other_session_status = 'in_progress' THEN 1 END) as other_in_progress_sessions,
        COUNT(CASE WHEN other_session_status = 'completed' THEN 1 END) as other_completed_sessions,
        COUNT(CASE WHEN other_session_status = 'paused' THEN 1 END) as other_paused_sessions,
        -- Get details of the most recent other session
        MAX(other_session_id) as most_recent_other_session_id,
        MAX(other_session_status) as most_recent_other_status,
        MAX(other_created_at) as most_recent_other_created_at,
        MAX(other_started_at) as most_recent_other_started_at,
        MAX(other_completed_at) as most_recent_other_completed_at,
        MAX(other_distance_km) as most_recent_other_distance_km,
        MAX(other_duration_seconds) as most_recent_other_duration_seconds,
        -- Time analysis
        MIN(seconds_between_sessions) as min_seconds_between_sessions,
        MAX(seconds_between_sessions) as max_seconds_between_sessions,
        AVG(seconds_between_sessions) as avg_seconds_between_sessions
    FROM same_day_sessions
    GROUP BY 
        created_session_id,
        user_id,
        created_date,
        created_ruck_weight,
        created_weight,
        created_is_manual,
        created_is_guided
)
SELECT 
    COUNT(*) as total_created_sessions,
    COUNT(CASE WHEN total_other_sessions = 0 THEN 1 END) as orphaned_sessions,
    COUNT(CASE WHEN other_completed_sessions > 0 THEN 1 END) as duplicate_after_completion,
    COUNT(CASE WHEN other_in_progress_sessions > 0 THEN 1 END) as conflicting_with_active,
    COUNT(CASE WHEN other_created_sessions > 0 THEN 1 END) as multiple_created_same_day,
    COUNT(CASE WHEN other_paused_sessions > 0 THEN 1 END) as conflicting_with_paused,
    -- Average time between sessions
    ROUND(AVG(avg_seconds_between_sessions) / 60, 1) as avg_minutes_between_sessions
FROM session_summary;
