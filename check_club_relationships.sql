-- Check foreign key relationships between club_memberships and clubs tables
-- This will show us exactly what relationships exist and their names

-- 1. Check all foreign key constraints on club_memberships table
SELECT 
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
WHERE 
    tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_name = 'club_memberships'
    AND ccu.table_name = 'clubs'
ORDER BY tc.constraint_name;

-- 2. Check the structure of club_memberships table
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'club_memberships'
ORDER BY ordinal_position;

-- 3. Check the structure of clubs table
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'clubs'
ORDER BY ordinal_position; 