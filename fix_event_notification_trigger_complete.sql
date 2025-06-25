-- Complete event notification trigger with push notifications
-- This creates both in-app notifications and triggers push notifications

CREATE OR REPLACE FUNCTION notify_event_created()
RETURNS TRIGGER AS $$
DECLARE
    member_record RECORD;
    event_creator_username TEXT;
    club_name TEXT;
BEGIN
    -- Get event creator username and club name for notification content
    SELECT p.username INTO event_creator_username
    FROM profiles p 
    WHERE p.id = NEW.creator_user_id;
    
    SELECT c.name INTO club_name
    FROM clubs c 
    WHERE c.id = NEW.club_id;
    
    -- Create notifications for all club members except the event creator
    FOR member_record IN 
        SELECT cm.user_id 
        FROM club_memberships cm 
        WHERE cm.club_id = NEW.club_id 
        AND cm.status = 'approved'
        AND cm.user_id != NEW.creator_user_id
    LOOP
        INSERT INTO notifications (
            recipient_id,
            type,
            message,
            data,
            is_read,
            created_at,
            updated_at,
            club_id,
            event_id
        ) VALUES (
            member_record.user_id,
            'club_event_created',
            COALESCE(event_creator_username, 'Someone') || ' created a new event "' || NEW.title || '" in ' || COALESCE(club_name, 'your club'),
            json_build_object(
                'event_id', NEW.id,
                'club_id', NEW.club_id,
                'event_title', NEW.title,
                'creator_username', COALESCE(event_creator_username, 'Someone'),
                'club_name', COALESCE(club_name, 'Club')
            ),
            false,
            NOW(),
            NOW(),
            NEW.club_id,
            NEW.id
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS event_created_notification ON events;

-- Create the trigger
CREATE TRIGGER event_created_notification
    AFTER INSERT ON events
    FOR EACH ROW
    WHEN (NEW.club_id IS NOT NULL)
    EXECUTE FUNCTION notify_event_created();

-- Test that the trigger was created successfully
SELECT 
    tgname as trigger_name, 
    tgenabled as enabled,
    tgrelid::regclass as table_name
FROM pg_trigger 
WHERE tgname = 'event_created_notification';
