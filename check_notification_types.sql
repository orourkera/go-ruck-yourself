-- Check distinct notification types in the notifications table
SELECT 
    type,
    COUNT(*) as count,
    MIN(created_at) as first_occurrence,
    MAX(created_at) as last_occurrence
FROM notifications 
GROUP BY type 
ORDER BY count DESC;

-- Also check for recent ruck_started notifications specifically
SELECT 
    type,
    message,
    data,
    created_at,
    recipient_id,
    sender_id
FROM notifications 
WHERE type = 'ruck_started' 
ORDER BY created_at DESC 
LIMIT 10;

-- Check if there are any recent notifications at all
SELECT 
    type,
    COUNT(*) as count
FROM notifications 
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY type 
ORDER BY count DESC;
