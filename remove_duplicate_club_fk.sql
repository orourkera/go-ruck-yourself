-- Remove duplicate foreign key constraint on club_memberships table
-- Keep the shorter named one (club_memberships_club_fk) and remove the longer one

-- Drop the redundant foreign key constraint
ALTER TABLE club_memberships 
DROP CONSTRAINT IF EXISTS club_memberships_club_id_fkey;

-- Verify the remaining constraint
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