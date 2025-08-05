-- Check is_manual flag status in the database

-- 1. Check the column definition and default value
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'ruck_session' AND column_name = 'is_manual';

-- 2. Check current values of is_manual in your sessions
SELECT 
    id,
    user_id,
    distance_km,
    duration_seconds,
    status,
    is_manual,
    created_at
FROM ruck_session 
WHERE user_id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid
ORDER BY created_at DESC
LIMIT 10;

-- 3. Count sessions by is_manual flag
SELECT 
    is_manual,
    COUNT(*) as session_count,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_count
FROM ruck_session 
WHERE user_id = '11683829-2373-46fc-82f1-f905d5316c30'::uuid
GROUP BY is_manual;

-- 4. Check if any sessions have NULL is_manual (which might be the issue)
SELECT COUNT(*) as null_is_manual_count
FROM ruck_session 
WHERE is_manual IS NULL;

-- 5. Check recent sessions across all users to see the pattern
SELECT 
    is_manual,
    COUNT(*) as total_sessions,
    MIN(created_at) as oldest,
    MAX(created_at) as newest
FROM ruck_session 
GROUP BY is_manual
ORDER BY is_manual; 