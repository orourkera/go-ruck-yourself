-- ========================================
-- Backfill Script: Associate Ruck Session 917 with Duel
-- ========================================
-- Description: Adds ruck session 917 to the duel_sessions table
-- Date: 2025-06-18
-- Author: System

-- STEP 1: First, let's verify the ruck session exists and get details
DO $$
DECLARE
    session_exists BOOLEAN;
    session_user_id UUID;
    session_distance DECIMAL;
    session_duration INTEGER;
    session_date TIMESTAMP;
BEGIN
    -- Check if ruck session 917 exists
    SELECT EXISTS(SELECT 1 FROM ruck_sessions WHERE id = 917) INTO session_exists;
    
    IF NOT session_exists THEN
        RAISE EXCEPTION 'Ruck session 917 does not exist!';
    END IF;
    
    -- Get session details for verification
    SELECT user_id, distance_km, duration_seconds, start_time 
    INTO session_user_id, session_distance, session_duration, session_date
    FROM ruck_sessions 
    WHERE id = 917;
    
    RAISE NOTICE 'Ruck Session 917 Details:';
    RAISE NOTICE '  User ID: %', session_user_id;
    RAISE NOTICE '  Distance: % km', session_distance;
    RAISE NOTICE '  Duration: % seconds', session_duration;
    RAISE NOTICE '  Date: %', session_date;
END $$;

-- ========================================
-- STEP 2: Find Active Duels for Session Owner
-- ========================================

-- Query to find potential duels for the session owner
-- (Run this to determine which duel_id and participant_id to use)
SELECT 
    d.id as duel_id,
    d.title,
    d.metric_type,
    d.start_date,
    d.end_date,
    d.status,
    dp.id as participant_id,
    dp.user_id,
    u.email as participant_email
FROM duels d
JOIN duel_participants dp ON d.id = dp.duel_id
JOIN auth.users u ON dp.user_id = u.id
WHERE dp.user_id = (SELECT user_id FROM ruck_sessions WHERE id = 917)
  AND d.status IN ('active', 'pending')
  AND (SELECT start_time FROM ruck_sessions WHERE id = 917) 
      BETWEEN d.start_date AND d.end_date
ORDER BY d.created_at DESC;

-- ========================================
-- STEP 3: Insert into duel_sessions
-- ========================================
-- NOTE: Replace these placeholder values with actual IDs from STEP 2 results

-- TEMPLATE - UNCOMMENT AND MODIFY THE VALUES BELOW:
/*
INSERT INTO duel_sessions (
    duel_id,
    participant_id, 
    session_id,
    contribution_value
) VALUES (
    'YOUR_DUEL_ID_HERE',    -- Replace with actual duel UUID from query above
    'YOUR_PARTICIPANT_ID_HERE', -- Replace with actual participant UUID from query above
    917,                     -- Ruck session ID
    (                        -- Calculate contribution value based on duel metric
        CASE 
            WHEN (SELECT metric_type FROM duels WHERE id = 'YOUR_DUEL_ID_HERE') = 'distance' 
            THEN (SELECT distance_km FROM ruck_sessions WHERE id = 917)
            
            WHEN (SELECT metric_type FROM duels WHERE id = 'YOUR_DUEL_ID_HERE') = 'duration'
            THEN (SELECT duration_seconds::DECIMAL / 3600 FROM ruck_sessions WHERE id = 917) -- Convert to hours
            
            WHEN (SELECT metric_type FROM duels WHERE id = 'YOUR_DUEL_ID_HERE') = 'sessions'
            THEN 1.0  -- Each session counts as 1
            
            ELSE (SELECT distance_km FROM ruck_sessions WHERE id = 917) -- Default to distance
        END
    )
)
ON CONFLICT (duel_id, session_id) DO NOTHING; -- Prevent duplicates
*/

-- ========================================
-- STEP 4: Verification Query
-- ========================================
-- Run this after the insert to verify the operation

SELECT 
    ds.id as duel_session_id,
    d.title as duel_title,
    d.metric_type,
    rs.id as session_id,
    rs.distance_km,
    rs.duration_seconds,
    rs.start_time,
    ds.contribution_value,
    u.email as participant_email
FROM duel_sessions ds
JOIN duels d ON ds.duel_id = d.id
JOIN duel_participants dp ON ds.participant_id = dp.id
JOIN auth.users u ON dp.user_id = u.id
JOIN ruck_sessions rs ON ds.session_id = rs.id
WHERE ds.session_id = 917;

-- ========================================
-- STEP 5: Update Duel Statistics (if needed)
-- ========================================
-- This will recalculate totals for the affected duel

-- TEMPLATE - UNCOMMENT AND MODIFY:
/*
UPDATE duel_participants 
SET total_value = (
    SELECT COALESCE(SUM(contribution_value), 0)
    FROM duel_sessions 
    WHERE participant_id = 'YOUR_PARTICIPANT_ID_HERE'
)
WHERE id = 'YOUR_PARTICIPANT_ID_HERE';
*/

-- ========================================
-- INSTRUCTIONS:
-- ========================================
-- 1. Run STEP 1 to verify ruck session 917 exists
-- 2. Run STEP 2 query to find the correct duel_id and participant_id
-- 3. Uncomment STEP 3 and replace placeholder values with real IDs
-- 4. Run STEP 3 to insert the duel session record
-- 5. Run STEP 4 to verify the insert was successful  
-- 6. Uncomment and run STEP 5 to update participant totals
-- ========================================
