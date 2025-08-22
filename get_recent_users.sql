-- Get last 20 new users with username, first name, creation date, and email
SELECT 
    username,
    SPLIT_PART(username, ' ', 1) as first_name,
    TO_CHAR(created_at, 'YYYY-MM-DD') as date_created,
    email
FROM "user"
ORDER BY created_at DESC
LIMIT 20;
