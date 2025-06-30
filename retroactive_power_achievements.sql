-- Retroactive script to award missing power achievements
-- This script finds users who have enough cumulative power points but lack the corresponding achievements

-- Power Warrior (1000 power points total)
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    rs.user_id,
    'power-warrior-1000' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM ruck_session rs
WHERE rs.session_status = 'completed'
    AND rs.user_id NOT IN (
        SELECT user_id 
        FROM user_achievements 
        WHERE achievement_id = 'power-warrior-1000'
    )
GROUP BY rs.user_id
HAVING SUM(COALESCE(rs.power_points, 0)) >= 1000;

-- Power Elite (5000 power points total)
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    rs.user_id,
    'power-elite-5000' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM ruck_session rs
WHERE rs.session_status = 'completed'
    AND rs.user_id NOT IN (
        SELECT user_id 
        FROM user_achievements 
        WHERE achievement_id = 'power-elite-5000'
    )
GROUP BY rs.user_id
HAVING SUM(COALESCE(rs.power_points, 0)) >= 5000;

-- Power Legend (10000 power points total) 
INSERT INTO user_achievements (user_id, achievement_id, earned_date, session_id)
SELECT DISTINCT 
    rs.user_id,
    'power-legend-10000' as achievement_id,
    NOW() as earned_date,
    NULL as session_id
FROM ruck_session rs
WHERE rs.session_status = 'completed'
    AND rs.user_id NOT IN (
        SELECT user_id 
        FROM user_achievements 
        WHERE achievement_id = 'power-legend-10000'
    )
GROUP BY rs.user_id
HAVING SUM(COALESCE(rs.power_points, 0)) >= 10000;

-- Show results
SELECT 'Power achievements awarded' as result, COUNT(*) as count FROM user_achievements 
WHERE achievement_id IN ('power-warrior-1000', 'power-elite-5000', 'power-legend-10000')
    AND earned_date >= NOW() - INTERVAL '1 minute';
