-- Fix elevation calculations for last 50 completed sessions
-- This script recalculates elevation gain/loss using validated GPS points only

BEGIN;

-- Store affected sessions for logging
CREATE TEMP TABLE affected_sessions AS
WITH recent_sessions AS (
    SELECT rs.id as session_id, rs.completed_at, rs.elevation_gain_m, rs.elevation_loss_m
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND rs.completed_at IS NOT NULL
    ORDER BY rs.completed_at DESC
    LIMIT 50
),
elevation_calculations AS (
    SELECT 
        lp.session_id,
        -- Calculate elevation gain using ordered altitude differences with GPS noise filtering
        SUM(
            CASE 
                WHEN lp.altitude > prev_altitude 
                     AND (lp.altitude - prev_altitude) > 2.0  -- Match backend ELEV_THRESHOLD_M = 2.0
                     AND (lp.altitude - prev_altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN lp.altitude - prev_altitude
                ELSE 0
            END
        ) as calculated_elevation_gain_m,
        -- Calculate elevation loss using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude < prev_altitude 
                     AND (prev_altitude - lp.altitude) > 2.0  -- Match backend ELEV_THRESHOLD_M = 2.0
                     AND (prev_altitude - lp.altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN prev_altitude - lp.altitude
                ELSE 0
            END
        ) as calculated_elevation_loss_m,
        COUNT(*) as total_points,
        MIN(lp.altitude) as min_altitude,
        MAX(lp.altitude) as max_altitude,
        rs.elevation_gain_m as old_elevation_gain_m,
        rs.elevation_loss_m as old_elevation_loss_m
    FROM (
        SELECT 
            lp.session_id,
            lp.altitude,
            lp.timestamp,
            LAG(lp.altitude) OVER (
                PARTITION BY lp.session_id 
                ORDER BY lp.timestamp
            ) as prev_altitude
        FROM location_point lp
        INNER JOIN recent_sessions rs ON lp.session_id = rs.session_id
        WHERE lp.altitude IS NOT NULL
          AND lp.altitude BETWEEN -500 AND 9000  -- Reasonable altitude range
        ORDER BY lp.session_id, lp.timestamp
    ) lp
    INNER JOIN recent_sessions rs ON lp.session_id = rs.session_id
    WHERE prev_altitude IS NOT NULL  -- Skip first point of each session
    GROUP BY lp.session_id, rs.elevation_gain_m, rs.elevation_loss_m
)
SELECT 
    session_id,
    old_elevation_gain_m,
    old_elevation_loss_m,
    calculated_elevation_gain_m,
    calculated_elevation_loss_m,
    total_points,
    min_altitude,
    max_altitude,
    (calculated_elevation_gain_m - COALESCE(old_elevation_gain_m, 0)) as gain_difference,
    (calculated_elevation_loss_m - COALESCE(old_elevation_loss_m, 0)) as loss_difference
FROM elevation_calculations
ORDER BY session_id;

-- Show summary before update
SELECT 
    'BEFORE UPDATE' as status,
    COUNT(*) as sessions_count,
    AVG(old_elevation_gain_m) as avg_old_gain,
    AVG(calculated_elevation_gain_m) as avg_new_gain,
    AVG(old_elevation_loss_m) as avg_old_loss,
    AVG(calculated_elevation_loss_m) as avg_new_loss
FROM affected_sessions;

-- Update ruck_session table with corrected elevation values
WITH recent_sessions AS (
    SELECT rs.id as session_id
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND rs.completed_at IS NOT NULL
    ORDER BY rs.completed_at DESC
    LIMIT 50
),
elevation_calculations AS (
    SELECT 
        lp.session_id,
        -- Calculate elevation gain using ordered altitude differences with GPS noise filtering
        SUM(
            CASE 
                WHEN lp.altitude > prev_altitude 
                     AND (lp.altitude - prev_altitude) > 2.0  -- Match backend ELEV_THRESHOLD_M = 2.0
                     AND (lp.altitude - prev_altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN lp.altitude - prev_altitude
                ELSE 0
            END
        ) as calculated_elevation_gain_m,
        -- Calculate elevation loss using ordered altitude differences
        SUM(
            CASE 
                WHEN lp.altitude < prev_altitude 
                     AND (prev_altitude - lp.altitude) > 2.0  -- Match backend ELEV_THRESHOLD_M = 2.0
                     AND (prev_altitude - lp.altitude) < 100.0  -- Filter unrealistic jumps > 100m
                THEN prev_altitude - lp.altitude
                ELSE 0
            END
        ) as calculated_elevation_loss_m
    FROM (
        SELECT 
            lp.session_id,
            lp.altitude,
            lp.timestamp,
            LAG(lp.altitude) OVER (
                PARTITION BY lp.session_id 
                ORDER BY lp.timestamp
            ) as prev_altitude
        FROM location_point lp
        INNER JOIN recent_sessions rs ON lp.session_id = rs.session_id
        WHERE lp.altitude IS NOT NULL
          AND lp.altitude BETWEEN -500 AND 9000  -- Reasonable altitude range
        ORDER BY lp.session_id, lp.timestamp
    ) lp
    WHERE prev_altitude IS NOT NULL  -- Skip first point of each session
    GROUP BY lp.session_id
)
UPDATE ruck_session 
SET 
    elevation_gain_m = ROUND(ec.calculated_elevation_gain_m::numeric, 1),
    elevation_loss_m = ROUND(ec.calculated_elevation_loss_m::numeric, 1),
    updated_at = NOW()
FROM elevation_calculations ec
WHERE ruck_session.id = ec.session_id
  AND ruck_session.status = 'completed';

-- Show summary after update
WITH recent_sessions AS (
    SELECT rs.id as session_id, rs.elevation_gain_m, rs.elevation_loss_m
    FROM ruck_session rs
    WHERE rs.status = 'completed'
      AND rs.completed_at IS NOT NULL
    ORDER BY rs.completed_at DESC
    LIMIT 50
)
SELECT 
    'AFTER UPDATE' as status,
    COUNT(*) as sessions_updated,
    AVG(elevation_gain_m) as avg_gain_m,
    AVG(elevation_loss_m) as avg_loss_m,
    MIN(elevation_gain_m) as min_gain_m,
    MAX(elevation_gain_m) as max_gain_m,
    MIN(elevation_loss_m) as min_loss_m,
    MAX(elevation_loss_m) as max_loss_m
FROM recent_sessions
WHERE elevation_gain_m IS NOT NULL OR elevation_loss_m IS NOT NULL;

COMMIT;
