-- Check if the club is marked as public
SELECT id, name, logo_url, status, visibility, created_at
FROM clubs 
WHERE id = 'd7a05ca7-e65f-46f5-bf2c-5c11893ad186';

-- Check all clubs and their visibility settings
SELECT id, name, status, visibility, created_at
FROM clubs 
ORDER BY created_at DESC;

-- Check the schema of clubs table to see visibility column
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'clubs' 
AND table_schema = 'public'
ORDER BY ordinal_position;
