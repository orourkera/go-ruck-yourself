-- Smart Ruck Session Management & Cleanup
-- This script addresses the root cause: preventing multiple active sessions per user
-- and provides intelligent cleanup for truly abandoned sessions

-- 1. Add unique constraint to prevent multiple active sessions per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_session_per_user 
ON public.ruck_sessions (user_id) 
WHERE completed_at IS NULL;

-- 2. Function to safely start a new session (handles existing active sessions)
CREATE OR REPLACE FUNCTION start_new_ruck_session(
    p_user_id UUID,
    p_session_data JSONB
) RETURNS TABLE(
    session_id UUID,
    action_taken TEXT,
    previous_session_id UUID,
    message TEXT
) AS $$
DECLARE
    existing_session_id UUID;
    existing_session_age INTERVAL;
    new_session_id UUID;
    action_msg TEXT;
BEGIN
    -- Check for existing active session
    SELECT id, (NOW() - created_at) 
    INTO existing_session_id, existing_session_age
    FROM public.ruck_sessions 
    WHERE user_id = p_user_id 
        AND completed_at IS NULL
    LIMIT 1;
    
    IF existing_session_id IS NOT NULL THEN
        -- If session is older than 2 hours, auto-complete it
        IF existing_session_age > INTERVAL '2 hours' THEN
            UPDATE public.ruck_sessions 
            SET 
                completed_at = created_at + INTERVAL '1 hour',
                updated_at = NOW()
            WHERE id = existing_session_id;
            
            action_msg := 'AUTO_COMPLETED_OLD_SESSION';
        ELSE
            -- Session is recent, return it instead of creating new one
            RETURN QUERY
            SELECT 
                existing_session_id,
                'RETURNED_EXISTING_SESSION'::TEXT,
                existing_session_id,
                format('Active session found (%.0f minutes old)', EXTRACT(EPOCH FROM existing_session_age)/60);
            RETURN;
        END IF;
    ELSE
        action_msg := 'CREATED_NEW_SESSION';
    END IF;
    
    -- Create new session
    INSERT INTO public.ruck_sessions (
        user_id,
        ruck_weight_kg,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        COALESCE((p_session_data->>'ruck_weight_kg')::DECIMAL, 0),
        NOW(),
        NOW()
    ) RETURNING id INTO new_session_id;
    
    -- Log the action
    INSERT INTO public.system_logs (
        log_type,
        message,
        details,
        created_at
    ) VALUES (
        'SESSION_START',
        format('Session start: %s', action_msg),
        jsonb_build_object(
            'user_id', p_user_id,
            'new_session_id', new_session_id,
            'previous_session_id', existing_session_id,
            'action', action_msg
        ),
        NOW()
    );
    
    RETURN QUERY
    SELECT 
        new_session_id,
        action_msg,
        existing_session_id,
        format('New session created (ID: %s)', new_session_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to get user's active session
CREATE OR REPLACE FUNCTION get_active_session(p_user_id UUID)
RETURNS TABLE(
    session_id UUID,
    created_at TIMESTAMPTZ,
    age_hours DECIMAL,
    is_stale BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rs.id,
        rs.created_at,
        EXTRACT(EPOCH FROM (NOW() - rs.created_at))/3600 AS age_hours,
        (NOW() - rs.created_at) > INTERVAL '2 hours' AS is_stale
    FROM public.ruck_sessions rs
    WHERE rs.user_id = p_user_id 
        AND rs.completed_at IS NULL
    ORDER BY rs.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Intelligent cleanup function
CREATE OR REPLACE FUNCTION cleanup_abandoned_sessions()
RETURNS TABLE(
    sessions_completed INTEGER,
    sessions_deleted INTEGER,
    cleanup_timestamp TIMESTAMPTZ,
    details JSONB
) AS $$
DECLARE
    completed_count INTEGER := 0;
    deleted_count INTEGER := 0;
    session_record RECORD;
    cleanup_details JSONB := '[]'::jsonb;
BEGIN
    -- 1. Auto-complete sessions older than 6 hours with some activity
    FOR session_record IN
        SELECT 
            id,
            user_id,
            created_at,
            duration_seconds,
            distance_km,
            EXTRACT(EPOCH FROM (NOW() - created_at))/3600 AS hours_since_created
        FROM public.ruck_sessions 
        WHERE completed_at IS NULL 
            AND created_at < NOW() - INTERVAL '6 hours'
            AND (duration_seconds > 0 OR distance_km > 0)
        ORDER BY created_at ASC
    LOOP
        -- Mark as complete with reasonable end time
        UPDATE public.ruck_sessions 
        SET 
            completed_at = CASE 
                WHEN duration_seconds > 0 THEN created_at + (duration_seconds || ' seconds')::INTERVAL
                ELSE created_at + INTERVAL '1 hour'
            END,
            updated_at = NOW()
        WHERE id = session_record.id;
        
        cleanup_details := cleanup_details || jsonb_build_object(
            'action', 'completed',
            'session_id', session_record.id,
            'user_id', session_record.user_id,
            'hours_old', session_record.hours_since_created,
            'had_activity', true
        );
        
        completed_count := completed_count + 1;
    END LOOP;
    
    -- 2. Delete sessions older than 24 hours with no activity
    WITH deleted_sessions AS (
        DELETE FROM public.ruck_sessions 
        WHERE completed_at IS NULL 
            AND created_at < NOW() - INTERVAL '24 hours'
            AND (duration_seconds = 0 OR duration_seconds IS NULL)
            AND (distance_km = 0 OR distance_km IS NULL)
        RETURNING id, user_id, created_at
    ),
    deleted_summary AS (
        SELECT 
            COUNT(*) as count,
            array_agg(id) as session_ids
        FROM deleted_sessions
    )
    SELECT 
        COALESCE(count, 0),
        session_ids
    INTO deleted_count, cleanup_details
    FROM deleted_summary;
    
    -- Log the cleanup
    INSERT INTO public.system_logs (
        log_type,
        message,
        details,
        created_at
    ) VALUES (
        'SESSION_CLEANUP',
        format('Completed %s sessions, deleted %s empty sessions', completed_count, deleted_count),
        jsonb_build_object(
            'completed_count', completed_count,
            'deleted_count', deleted_count,
            'details', cleanup_details
        ),
        NOW()
    );
    
    RETURN QUERY
    SELECT 
        completed_count,
        deleted_count,
        NOW()::TIMESTAMPTZ,
        cleanup_details;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Create system logs table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.system_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    log_type TEXT NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for efficient querying
CREATE INDEX IF NOT EXISTS idx_system_logs_type_created 
ON public.system_logs(log_type, created_at DESC);

-- Enable RLS for system logs
ALTER TABLE public.system_logs ENABLE ROW LEVEL SECURITY;

-- Only allow system (service role) to manage logs
CREATE POLICY "System can manage logs" ON public.system_logs
    FOR ALL USING (auth.uid() IS NULL);

-- 3. Create a more aggressive cleanup function for very old sessions
CREATE OR REPLACE FUNCTION cleanup_very_old_ruck_sessions()
RETURNS TABLE(
    sessions_deleted INTEGER,
    cleanup_timestamp TIMESTAMPTZ
) AS $$
DECLARE
    deleted_count INTEGER := 0;
BEGIN
    -- Delete sessions that are older than 7 days and still incomplete
    -- These are likely test sessions or severely corrupted data
    WITH deleted_sessions AS (
        DELETE FROM public.ruck_sessions 
        WHERE completed_at IS NULL 
            AND created_at < NOW() - INTERVAL '7 days'
            AND (duration_seconds = 0 OR duration_seconds IS NULL)
            AND (distance_km = 0 OR distance_km IS NULL)
        RETURNING id, user_id, created_at
    )
    SELECT COUNT(*) INTO deleted_count FROM deleted_sessions;
    
    -- Log the deletion
    INSERT INTO public.system_logs (
        log_type,
        message,
        details,
        created_at
    ) VALUES (
        'RUCK_SESSION_DELETION',
        format('Deleted %s very old empty ruck sessions', deleted_count),
        jsonb_build_object('deleted_count', deleted_count, 'criteria', 'older_than_7_days_and_empty'),
        NOW()
    );
    
    RETURN QUERY
    SELECT 
        deleted_count,
        NOW()::TIMESTAMPTZ;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Schedule the cleanup jobs using pg_cron extension
-- Note: This requires the pg_cron extension to be installed
-- Run this as a superuser or user with appropriate permissions

-- Schedule the intelligent cleanup to run every 2 hours
SELECT cron.schedule(
    'cleanup-abandoned-sessions',
    '0 */2 * * *',  -- Every 2 hours
    'SELECT cleanup_abandoned_sessions();'
);

-- 5. Manual execution commands (for testing or one-time runs)
-- To run the cleanup manually:
-- SELECT * FROM cleanup_abandoned_sessions();

-- To check if a user has an active session:
-- SELECT * FROM get_active_session('user-uuid-here');

-- To safely start a new session:
-- SELECT * FROM start_new_ruck_session('user-uuid-here', '{"ruck_weight_kg": 20}');

-- 6. View cleanup logs
-- SELECT * FROM public.system_logs WHERE log_type IN ('SESSION_CLEANUP', 'SESSION_START') ORDER BY created_at DESC;

-- 7. Check scheduled jobs
-- SELECT * FROM cron.job ORDER BY created_at DESC;

-- 8. Remove scheduled jobs (if needed)
-- SELECT cron.unschedule('cleanup-abandoned-sessions');

-- 9. One-time manual cleanup (run this now to clean existing orphaned sessions)
-- SELECT * FROM cleanup_abandoned_sessions();
