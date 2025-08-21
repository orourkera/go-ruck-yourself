-- Debug the specific session from August 15, 2025
-- Distance: 2.07 mi, Duration: 34m 14s, Showing: 0:16/mi (incorrect)

SELECT 
    s.id,
    s.started_at::date as session_date,
    s.distance_km,
    (s.distance_km * 0.621371) as distance_miles,
    s.duration_seconds,
    
    -- Expected pace calculation
    -- 2.07 mi in 34m14s = 2054 seconds
    -- Should be: 2054 / 2.07 = 992.75 seconds per mile = 16:32/mile
    CASE 
        WHEN s.distance_km > 0 THEN 
            -- Calculate seconds per mile from database values
            s.duration_seconds / (s.distance_km * 0.621371)
        ELSE NULL
    END as calculated_seconds_per_mile,
    
    -- Format as MM:SS per mile
    CASE 
        WHEN s.distance_km > 0 THEN 
            CONCAT(
                ((s.duration_seconds / (s.distance_km * 0.621371)) / 60)::int, ':',
                LPAD(((s.duration_seconds / (s.distance_km * 0.621371))::int % 60)::text, 2, '0'),
                '/mi'
            )
        ELSE NULL
    END as correct_pace_per_mile,
    
    -- What's stored in database
    s.average_pace,
    
    -- Convert stored pace to per mile (if it's stored as minutes per km)
    CASE 
        WHEN s.average_pace::numeric > 0 THEN 
            CONCAT(
                ((s.average_pace::numeric * 1.609344)::int), ':',
                LPAD((((s.average_pace::numeric * 1.609344) - (s.average_pace::numeric * 1.609344)::int) * 60)::int::text, 2, '0'),
                '/mi'
            )
        ELSE '--:--/mi'
    END as stored_pace_per_mile,
    
    s.calories_burned,
    s.notes

FROM ruck_session s
WHERE s.started_at::date = '2025-08-15'
  AND s.distance_km BETWEEN 3.3 AND 3.4  -- ~2.07 miles
  AND s.duration_seconds BETWEEN 2000 AND 2100  -- ~34 minutes
ORDER BY ABS(s.duration_seconds - 2054) ASC  -- Find closest to 34m14s
LIMIT 5;
