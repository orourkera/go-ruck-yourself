-- Apply the backfill updates - restore missing session data
-- Run this after confirming the preview calculations look correct

UPDATE ruck_session 
SET 
    distance_km = sc.calculated_distance_km,
    average_pace = sc.calculated_pace_min_per_km::text,
    elevation_gain_m = sc.calculated_elevation_gain_m,
    calories_burned = sc.calculated_calories_burned,
    updated_at = NOW()
FROM session_calculations sc
WHERE ruck_session.id = sc.session_id
  AND ruck_session.status = 'completed'
  AND sc.calculated_distance_km > 0;
