-- Check RLS policies on clubs table
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'clubs';

-- Check if RLS is enabled on clubs table
SELECT 
    schemaname,
    tablename,
    rowsecurity,
    forcerowsecurity
FROM pg_tables 
WHERE tablename = 'clubs';

-- Test direct access to the specific club
SELECT id, name, logo_url, status
FROM clubs 
WHERE id = 'd7a05ca7-e65f-46f5-bf2c-5c11893ad186';
