-- Export user emails and device types for Mailjet segmentation
-- Gets most recent device token per user, excluding 'unknown' device types

WITH most_recent_devices AS (
    SELECT DISTINCT ON (user_id) 
        user_id,
        device_type
    FROM user_device_tokens 
    WHERE device_type IS NOT NULL 
        AND device_type != 'unknown'
        AND device_type != ''
    ORDER BY user_id, created_at DESC
)
SELECT 
    u.email,
    mrd.device_type
FROM "user" u
INNER JOIN most_recent_devices mrd ON u.id = mrd.user_id
WHERE u.email IS NOT NULL 
    AND u.email != '' 
    AND u.email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' -- Valid email format
ORDER BY u.email;

-- Alternative query focusing just on email and device type for simple Mailjet import
/*
SELECT DISTINCT
    u.email,
    COALESCE(udt.device_type, 'unknown') as device_type,
    COUNT(*) OVER (PARTITION BY u.email) as device_count
FROM "user" u
LEFT JOIN user_device_tokens udt ON u.id = udt.user_id
WHERE u.email IS NOT NULL 
    AND u.email != '' 
    AND u.email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
ORDER BY u.email, device_type;
*/
