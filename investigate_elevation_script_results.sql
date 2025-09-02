-- Investigation script to check if elevation fix script worked
-- Focusing on session 2858 and other recent sessions

-- 1. Check session 2858 specifically
SELECT 
    id,
    distance_km,
    elevation_gain_m,
    elevation_loss_m,
    started_at,
    completed_at,
    is_manual
FROM ruck_session 
WHERE id = 2858;

-- 2. Check location points for session 2858 to see raw elevation data
SELECT 
    session_id,
    COUNT(*) as total_points,
    MIN(CAST(altitude AS FLOAT)) as min_altitude,
    MAX(CAST(altitude AS FLOAT)) as max_altitude,
    MAX(CAST(altitude AS FLOAT)) - MIN(CAST(altitude AS FLOAT)) as raw_elevation_range,
    AVG(CAST(altitude AS FLOAT)) as avg_altitude,
    COUNT(CASE WHEN altitude IS NOT NULL THEN 1 END) as points_with_altitude
FROM location_point 
WHERE session_id = 2858
GROUP BY session_id;

-- 3. Check the last 50 completed sessions to see which ones still have high elevation
SELECT 
    id,
    distance_km,
    elevation_gain_m,
    elevation_loss_m,
    elevation_gain_m / distance_km as gain_per_km,
    started_at,
    is_manual,
    CASE 
        WHEN elevation_gain_m > 100 AND distance_km > 0 THEN 'HIGH_ELEVATION'
        WHEN elevation_gain_m > 50 AND distance_km > 0 AND (elevation_gain_m / distance_km) > 20 THEN 'SUSPICIOUS'
        ELSE 'OK'
    END as elevation_status
FROM ruck_session 
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND distance_km > 0
ORDER BY started_at DESC 
LIMIT 50;

-- 4. Check specifically for sessions that should have been fixed but weren't
SELECT 
    rs.id,
    rs.distance_km,
    rs.elevation_gain_m,
    rs.elevation_loss_m,
    rs.started_at,
    rs.is_manual,
    COUNT(lp.id) as location_point_count,
    MIN(CAST(lp.altitude AS FLOAT)) as min_point_altitude,
    MAX(CAST(lp.altitude AS FLOAT)) as max_point_altitude,
    MAX(CAST(lp.altitude AS FLOAT)) - MIN(CAST(lp.altitude AS FLOAT)) as actual_elevation_range
FROM ruck_session rs
LEFT JOIN location_point lp ON rs.id = lp.session_id
WHERE rs.status = 'completed' 
    AND rs.started_at >= NOW() - INTERVAL '30 days'
    AND rs.elevation_gain_m > 100
    AND rs.distance_km > 0
    AND rs.is_manual = false
GROUP BY rs.id, rs.distance_km, rs.elevation_gain_m, rs.elevation_loss_m, rs.started_at, rs.is_manual
ORDER BY rs.started_at DESC;

-- 5. Check if any sessions were actually fixed (should show lower elevation values)
SELECT 
    id,
    distance_km,
    elevation_gain_m,
    elevation_loss_m,
    elevation_gain_m / distance_km as gain_per_km,
    started_at
FROM ruck_session 
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND distance_km > 0
    AND elevation_gain_m < 50  -- These might have been fixed
    AND is_manual = false
ORDER BY started_at DESC 
LIMIT 10;

-- 6. Summary statistics
SELECT 
    COUNT(*) as total_recent_sessions,
    COUNT(CASE WHEN elevation_gain_m > 100 THEN 1 END) as high_elevation_sessions,
    COUNT(CASE WHEN elevation_gain_m BETWEEN 20 AND 100 THEN 1 END) as moderate_elevation_sessions,
    COUNT(CASE WHEN elevation_gain_m < 20 THEN 1 END) as low_elevation_sessions,
    AVG(elevation_gain_m) as avg_elevation_gain,
    MAX(elevation_gain_m) as max_elevation_gain
FROM ruck_session 
WHERE status = 'completed' 
    AND started_at >= NOW() - INTERVAL '30 days'
    AND distance_km > 0
    AND is_manual = false;
