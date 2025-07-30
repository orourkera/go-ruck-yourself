-- Query to get recent users for Mailjet sync
-- Returns: username, email, first_name, signup_date (DD/MM/YYYY format)

SELECT 
    username,
    email,
    CASE 
        WHEN POSITION(' ' IN username) > 0 
        THEN SUBSTRING(username FROM 1 FOR POSITION(' ' IN username) - 1)
        ELSE username
    END AS first_name,
    TO_CHAR(created_at, 'DD/MM/YYYY') AS signup_date,
    created_at
FROM "user" 
WHERE created_at >= NOW() - INTERVAL '30 days'
  AND email IS NOT NULL
ORDER BY created_at DESC;

-- Alternative for last 7 days:
-- WHERE created_at >= NOW() - INTERVAL '7 days'

-- Alternative for all users:
-- WHERE email IS NOT NULL
