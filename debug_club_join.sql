-- Check the actual columns in the events table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'events' 
AND table_schema = 'public'
AND column_name LIKE '%club%'
ORDER BY column_name;

-- Check the specific event that's showing up in logs
SELECT id, title, club_id, hosting_club_id, creator_user_id
FROM events 
WHERE id = '6b60f864-9965-4a03-bf92-3926c12bf727';

-- Test the join with club_id (current approach that's failing)
SELECT e.id, e.title, e.club_id, e.hosting_club_id, c.id as club_table_id, c.name as club_name, c.logo_url
FROM events e
LEFT JOIN clubs c ON e.club_id = c.id
WHERE e.id = '6b60f864-9965-4a03-bf92-3926c12bf727';

-- Test the join with hosting_club_id (what we changed to)
SELECT e.id, e.title, e.club_id, e.hosting_club_id, c.id as club_table_id, c.name as club_name, c.logo_url
FROM events e
LEFT JOIN clubs c ON e.hosting_club_id = c.id
WHERE e.id = '6b60f864-9965-4a03-bf92-3926c12bf727';

-- Check if the club exists in the clubs table
SELECT id, name, logo_url, status, created_at
FROM clubs 
WHERE id = 'd7a05ca7-e65f-46f5-bf2c-5c11893ad186';
