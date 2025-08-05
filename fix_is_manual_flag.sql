-- Fix is_manual flag for existing sessions
-- This script will update sessions that should be marked as is_manual = false

BEGIN;

-- First, let's see what we're working with
SELECT 
    'Before Update' as status,
    is_manual,
    COUNT(*) as session_count
FROM ruck_session 
GROUP BY is_manual
ORDER BY is_manual;

-- Update sessions that should be is_manual = false
-- These are sessions that have location points (indicating they were tracked)
UPDATE ruck_session 
SET is_manual = false
WHERE is_manual IS NULL 
   OR (is_manual = true AND EXISTS (
       SELECT 1 FROM location_point lp 
       WHERE lp.session_id = ruck_session.id
   ));

-- Also update sessions that have terrain data (another indicator of tracked sessions)
UPDATE ruck_session 
SET is_manual = false
WHERE is_manual IS NULL 
   OR (is_manual = true AND EXISTS (
       SELECT 1 FROM terrain_segment ts 
       WHERE ts.session_id = ruck_session.id
   ));

-- Update sessions that have heart rate data (another indicator of tracked sessions)
UPDATE ruck_session 
SET is_manual = false
WHERE is_manual IS NULL 
   OR (is_manual = true AND EXISTS (
       SELECT 1 FROM heart_rate_point hrp 
       WHERE hrp.session_id = ruck_session.id
   ));

-- For any remaining NULL values, default them to false (most sessions are tracked)
UPDATE ruck_session 
SET is_manual = false
WHERE is_manual IS NULL;

-- Show the results
SELECT 
    'After Update' as status,
    is_manual,
    COUNT(*) as session_count
FROM ruck_session 
GROUP BY is_manual
ORDER BY is_manual;

-- Show sessions that are still marked as manual (these should be legitimate manual entries)
SELECT 
    id,
    user_id,
    distance_km,
    duration_seconds,
    created_at,
    -- Check if they have location points (shouldn't if truly manual)
    (SELECT COUNT(*) FROM location_point lp WHERE lp.session_id = ruck_session.id) as location_point_count,
    -- Check if they have terrain data (shouldn't if truly manual)
    (SELECT COUNT(*) FROM terrain_segment ts WHERE ts.session_id = ruck_session.id) as terrain_segment_count,
    -- Check if they have heart rate data (shouldn't if truly manual)
    (SELECT COUNT(*) FROM heart_rate_point hrp WHERE hrp.session_id = ruck_session.id) as heart_rate_point_count
FROM ruck_session 
WHERE is_manual = true
ORDER BY created_at DESC
LIMIT 20;

COMMIT; 