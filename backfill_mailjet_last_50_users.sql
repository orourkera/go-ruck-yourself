-- BACKFILL LAST 50 USERS TO MAILJET
-- This script syncs the most recent 50 users to Mailjet with proper metadata

-- First, let's see what we're working with
SELECT 
    'Preview of last 50 users to be synced' as status,
    u.email,
    u.username,
    CASE 
        WHEN position(' ' in u.username) > 0 THEN 
            substring(u.username from 1 for position(' ' in u.username) - 1)
        ELSE u.username
    END as firstname,
    to_char(u.created_at, 'DD/MM/YYYY') as signup_date,
    u.created_at
FROM public.user u
WHERE u.email IS NOT NULL 
    AND u.email != ''
ORDER BY u.created_at DESC
LIMIT 50;

-- Now perform the actual backfill by calling our internal Mailjet sync endpoint
-- This uses the same HTTP call mechanism as the trigger
DO $$
DECLARE
    user_record RECORD;
    mailjet_response http_response;
    mailjet_payload jsonb;
    success_count INTEGER := 0;
    error_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Starting Mailjet backfill for last 50 users...';
    
    -- Loop through the last 50 users
    FOR user_record IN 
        SELECT 
            u.id,
            u.email,
            u.username,
            u.created_at,
            CASE 
                WHEN position(' ' in u.username) > 0 THEN 
                    substring(u.username from 1 for position(' ' in u.username) - 1)
                ELSE u.username
            END as firstname
        FROM public.user u
        WHERE u.email IS NOT NULL 
            AND u.email != ''
        ORDER BY u.created_at DESC
        LIMIT 50
    LOOP
        BEGIN
            -- Prepare Mailjet payload for this user
            mailjet_payload := jsonb_build_object(
                'email', user_record.email,
                'username', user_record.username,
                'user_metadata', jsonb_build_object(
                    'user_id', user_record.id::text,
                    'signup_date', to_char(user_record.created_at, 'DD/MM/YYYY'),
                    'signup_source', 'backfill_sync',
                    'name', user_record.username,
                    'firstname', user_record.firstname
                )
            );
            
            -- Make HTTP call to internal Mailjet sync endpoint
            SELECT http_post(
                'https://getrucky.com/api/internal/mailjet-sync',
                mailjet_payload::text,
                'application/json'
            ) INTO mailjet_response;
            
            -- Check response and log result
            IF mailjet_response.status = 200 THEN
                success_count := success_count + 1;
                RAISE NOTICE 'SUCCESS: % (% of 50)', user_record.email, success_count;
            ELSE
                error_count := error_count + 1;
                RAISE WARNING 'FAILED: % - Status: %, Response: %', 
                    user_record.email, mailjet_response.status, mailjet_response.content;
            END IF;
            
            -- Small delay to avoid overwhelming the API (100ms)
            PERFORM pg_sleep(0.1);
            
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
            RAISE WARNING 'ERROR syncing %: %', user_record.email, SQLERRM;
        END;
    END LOOP;
    
    -- Final summary
    RAISE NOTICE '=== BACKFILL COMPLETE ===';
    RAISE NOTICE 'Successfully synced: % users', success_count;
    RAISE NOTICE 'Failed to sync: % users', error_count;
    RAISE NOTICE 'Total processed: % users', success_count + error_count;
END;
$$;

-- Verify the backfill worked by checking recent activity
SELECT 'Backfill completed - check your Mailjet dashboard for new contacts!' as status;
