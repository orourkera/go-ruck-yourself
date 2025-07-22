-- =====================================================
-- LOCATION_POINT TABLE PARTITIONING IMPLEMENTATION
-- =====================================================
-- Run this step-by-step in Supabase SQL editor
-- BACKUP YOUR DATA FIRST!

-- Step 1: Create partitioned table structure
-- =====================================================
CREATE TABLE location_point_partitioned (
    id bigserial NOT NULL,
    session_id integer,
    latitude numeric,
    longitude numeric,
    altitude numeric,
    timestamp timestamp,
    PRIMARY KEY (id, timestamp)  -- Partition key must be in PK
) PARTITION BY RANGE (timestamp);

-- Step 2: Create monthly partitions
-- =====================================================
-- May 2025 (existing data)
CREATE TABLE location_point_202505
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');

-- June 2025 (existing data - ~168K points)
CREATE TABLE location_point_202506
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');

-- July 2025 (current month - ~160K points)
CREATE TABLE location_point_202507
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

-- August 2025 (future)
CREATE TABLE location_point_202508
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');

-- September 2025 (future)
CREATE TABLE location_point_202509
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');

-- October 2025 (future)
CREATE TABLE location_point_202510
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

-- November 2025 (future)
CREATE TABLE location_point_202511
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

-- December 2025 (future)
CREATE TABLE location_point_202512
PARTITION OF location_point_partitioned 
FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- Step 3: Create performance indexes
-- =====================================================
-- Critical index for session-based queries
CREATE INDEX idx_location_point_part_session_time 
ON location_point_partitioned (session_id, timestamp);

-- Index for session lookups
CREATE INDEX idx_location_point_part_session 
ON location_point_partitioned (session_id);

-- Step 4: Verify structure (run this to check)
-- =====================================================
-- Verify partitions were created
SELECT 
    schemaname, 
    tablename, 
    attname, 
    n_distinct, 
    correlation 
FROM pg_stats 
WHERE tablename LIKE 'location_point%'
ORDER BY tablename;

-- Check partition info
SELECT 
    t.relname as partition_name,
    pg_get_expr(t.relpartbound, t.oid) as partition_range
FROM pg_class t
JOIN pg_inherits i ON i.inhrelid = t.oid
JOIN pg_class p ON i.inhparent = p.oid
WHERE p.relname = 'location_point_partitioned'
ORDER BY t.relname;

-- Step 5: Data migration (THIS IS THE BIG STEP)
-- =====================================================
-- IMPORTANT: This will copy all your location data
-- Run during low traffic period
-- Monitor progress: it should take 1-5 minutes for ~330K rows

INSERT INTO location_point_partitioned 
(id, session_id, latitude, longitude, altitude, timestamp)
SELECT id, session_id, latitude, longitude, altitude, timestamp 
FROM location_point;

-- Step 6: Verify data migration
-- =====================================================
-- Check counts match
SELECT 
    'original' as table_type, COUNT(*) as row_count 
FROM location_point
UNION ALL
SELECT 
    'partitioned' as table_type, COUNT(*) as row_count 
FROM location_point_partitioned;

-- Check partition distribution
SELECT 
    schemaname, 
    tablename, 
    n_tup_ins as rows
FROM pg_stat_user_tables 
WHERE tablename LIKE 'location_point_202%'
ORDER BY tablename;

-- Step 7: Atomic table swap (FINAL STEP - POINT OF NO RETURN)
-- =====================================================
-- This will make the change live
-- Run this only after verifying data migration is correct

BEGIN;
  -- Rename original table to backup
  ALTER TABLE location_point RENAME TO location_point_old_backup;
  
  -- Rename partitioned table to active name
  ALTER TABLE location_point_partitioned RENAME TO location_point;
  
  -- Update sequence if needed
  SELECT setval('location_point_partitioned_id_seq', 
                (SELECT MAX(id) FROM location_point));
COMMIT;

-- Step 8: Performance test (verify it worked)
-- =====================================================
-- Test query that should be much faster now
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) 
FROM location_point 
WHERE timestamp >= '2025-07-01' AND timestamp < '2025-08-01';

-- This should show it only scanned location_point_202507 partition

-- Step 9: Cleanup (optional, after confirming everything works)
-- =====================================================
-- After 1-2 days of successful operation, you can drop the backup
-- DROP TABLE location_point_old_backup;

-- Step 10: Future partition management
-- =====================================================
-- Create function for auto-creating monthly partitions
CREATE OR REPLACE FUNCTION create_monthly_location_partition(start_date date)
RETURNS void AS $$
DECLARE
    partition_name text;
    start_month text;
    end_date date;
BEGIN
    start_month := to_char(start_date, 'YYYYMM');
    partition_name := 'location_point_' || start_month;
    end_date := start_date + interval '1 month';
    
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF location_point FOR VALUES FROM (%L) TO (%L)',
                   partition_name, start_date, end_date);
    
    RAISE NOTICE 'Created partition: %', partition_name;
END;
$$ LANGUAGE plpgsql;

-- Create next 6 months of partitions automatically
SELECT create_monthly_location_partition(
    date_trunc('month', CURRENT_DATE + interval '1 month' * generate_series(1, 6))
);

-- =====================================================
-- ROLLBACK PLAN (if something goes wrong)
-- =====================================================
/*
If you need to rollback after Step 7:

BEGIN;
  ALTER TABLE location_point RENAME TO location_point_partitioned_temp;
  ALTER TABLE location_point_old_backup RENAME TO location_point;
COMMIT;

-- Then investigate the issue and retry
*/
