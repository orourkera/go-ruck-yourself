-- Debug pace calculation issue
-- Check raw session data vs calculated pace for recent sessions

SELECT 
    s.id,
    s.started_at,
    s.distance_km,
    s.duration_seconds,
    s.average_pace,
    
    -- Convert distance to miles for display
    (s.distance_km * 0.621371) AS distance_miles,
    
    -- Convert duration to readable format
    CONCAT(
        LPAD((s.duration_seconds / 3600)::text, 2, '0'), ':',
        LPAD(((s.duration_seconds % 3600) / 60)::text, 2, '0'), ':',
        LPAD((s.duration_seconds % 60)::text, 2, '0')
    ) AS duration_formatted,
    
    -- Calculate pace from raw data (seconds per km)
    CASE 
        WHEN s.distance_km > 0 THEN s.duration_seconds / s.distance_km
        ELSE NULL
    END AS calculated_pace_sec_per_km,
    
    -- Convert calculated pace to minutes:seconds per km
    CASE 
        WHEN s.distance_km > 0 THEN 
            CONCAT(
                ((s.duration_seconds / s.distance_km) / 60)::int, ':',
                LPAD(((s.duration_seconds / s.distance_km)::int % 60)::text, 2, '0')
            )
        ELSE NULL
    END AS calculated_pace_min_sec_per_km,
    
    -- Convert calculated pace to minutes:seconds per mile  
    CASE 
        WHEN s.distance_km > 0 THEN 
            CONCAT(
                (((s.duration_seconds / s.distance_km) * 1.609344) / 60)::int, ':',
                LPAD((((s.duration_seconds / s.distance_km) * 1.609344)::int % 60)::text, 2, '0')
            )
        ELSE NULL
    END AS calculated_pace_min_sec_per_mile,
    
    -- Stored average pace (convert from string and format)
    CASE 
        WHEN s.average_pace::numeric > 0 THEN 
            CONCAT(
                FLOOR(s.average_pace::numeric)::int, ':',
                LPAD(((s.average_pace::numeric - FLOOR(s.average_pace::numeric)) * 60)::int::text, 2, '0')
            )
        ELSE '--:--'
    END AS stored_pace_formatted,
    
    -- Check if there's a mismatch between calculated and stored
    CASE 
        WHEN s.distance_km > 0 AND s.average_pace::numeric > 0 THEN
            CASE 
                WHEN ABS((s.duration_seconds / s.distance_km / 60) - s.average_pace::numeric) > 0.1 
                THEN '❌ MISMATCH'
                ELSE '✅ MATCH'
            END
        ELSE '⚠️ NO_DATA'
    END AS pace_validation,
    
    s.notes
    
FROM ruck_session s
WHERE s.distance_km > 0 
  AND s.duration_seconds > 0
  AND s.started_at >= CURRENT_DATE - INTERVAL '7 days'  -- Last 7 days
ORDER BY s.started_at DESC
LIMIT 20;
