-- Check existing indexes on tables used by profile endpoint

-- 1. Check indexes on ruck_session table
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'ruck_session'
ORDER BY indexname;

-- 2. Check indexes on user_duel_stats table  
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'user_duel_stats'
ORDER BY indexname;

-- 3. Check indexes on club_memberships table
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'club_memberships'
ORDER BY indexname;

-- 4. Check indexes on user_follows table (the ones we just created)
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'user_follows'
ORDER BY indexname;
