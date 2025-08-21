-- Fix timeout on /api/rucks/{id}/comments endpoint
-- Add COMPOSITE index for ruck_comments query performance

-- CRITICAL: Create composite index on ruck_comments for efficient querying by ruck_id with created_at ordering
-- This is needed because existing idx_ruck_comments_ruck_id only covers ruck_id, 
-- but query also needs ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_ruck_comments_ruck_id_created_at 
ON ruck_comments (ruck_id, created_at DESC);

-- Skip user_id index - already exists as idx_ruck_comments_user_id

-- Check existing indexes on ruck_comments table BEFORE creating new ones
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'ruck_comments' 
ORDER BY indexname;

-- Alternative query to check indexes with more details
SELECT
    i.relname as index_name,
    t.relname as table_name,
    a.attname as column_name,
    ix.indisunique as is_unique,
    ix.indisprimary as is_primary
FROM
    pg_class t,
    pg_class i,
    pg_index ix,
    pg_attribute a
WHERE
    t.oid = ix.indrelid
    AND i.oid = ix.indexrelid
    AND a.attrelid = t.oid
    AND a.attnum = ANY(ix.indkey)
    AND t.relkind = 'r'
    AND t.relname = 'ruck_comments'
ORDER BY
    i.relname,
    a.attname;
