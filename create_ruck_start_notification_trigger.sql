-- Create trigger for ruck start notifications
-- This creates notifications when a ruck session status changes to 'in_progress'

CREATE OR REPLACE FUNCTION notify_ruck_started()
RETURNS TRIGGER AS $$
DECLARE
    follower_record RECORD;
    user_name TEXT;
BEGIN
    -- Only trigger when status changes to 'in_progress' (ruck started)
    IF NEW.status = 'in_progress' AND (OLD.status IS NULL OR OLD.status != 'in_progress') THEN
        
        -- Get the user's display name
        SELECT COALESCE(display_name, username, 'Someone') INTO user_name
        FROM "user" 
        WHERE id = NEW.user_id;
        
        -- Create notifications for all followers
        FOR follower_record IN 
            SELECT uf.follower_id 
            FROM user_follows uf 
            WHERE uf.followed_id = NEW.user_id
        LOOP
            INSERT INTO notifications (
                recipient_id,
                sender_id,
                type,
                message,
                data
            ) VALUES (
                follower_record.follower_id,
                NEW.user_id,
                'ruck_started',
                user_name || ' started rucking!',
                jsonb_build_object(
                    'ruck_id', NEW.id,
                    'rucker_name', user_name
                )
            );
        END LOOP;
    END IF;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- If there's an error, just continue without failing the ruck start
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS ruck_start_notifications_trigger ON ruck_session;

-- Create trigger for ruck start notifications
CREATE TRIGGER ruck_start_notifications_trigger
    AFTER UPDATE ON ruck_session
    FOR EACH ROW
    EXECUTE FUNCTION notify_ruck_started();
