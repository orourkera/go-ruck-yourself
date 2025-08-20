-- Change user_achievements foreign key from SET NULL to CASCADE DELETE
-- This will delete achievements when their triggering session is deleted

-- Step 1: Drop the existing foreign key constraint
ALTER TABLE user_achievements 
DROP CONSTRAINT IF EXISTS user_achievements_session_id_fkey;

-- Step 2: Add new foreign key constraint with CASCADE DELETE
ALTER TABLE user_achievements 
ADD CONSTRAINT user_achievements_session_id_fkey 
FOREIGN KEY (session_id) 
REFERENCES ruck_session(id) 
ON DELETE CASCADE;

-- Step 3: Verify the constraint was created correctly
SELECT 
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' 
    AND tc.table_name = 'user_achievements'
    AND kcu.column_name = 'session_id';
