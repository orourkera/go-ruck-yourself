-- Delete all ruck sessions with 'created' status
-- These are incomplete sessions that were never started or completed

DELETE FROM ruck_sessions 
WHERE status = 'created';

-- Optional: Check how many rows would be affected first (run this before the DELETE)
-- SELECT COUNT(*) FROM ruck_sessions WHERE status = 'created';

-- Optional: See which sessions will be deleted (run this before the DELETE)
-- SELECT id, user_id, status, created_at, started_at, completed_at 
-- FROM ruck_sessions 
-- WHERE status = 'created' 
-- ORDER BY created_at DESC;
