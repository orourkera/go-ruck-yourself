-- Debug query to check session statuses for your user
SELECT 
    id,
    status,
    completed_at,
    distance_km,
    duration_seconds
FROM ruck_session 
WHERE user_id = '11683829-2c73-46fc-82f1-f905d5316c30'
ORDER BY completed_at DESC
LIMIT 10;
