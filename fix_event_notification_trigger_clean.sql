-- Fix event notification trigger to use correct column names and data types

CREATE OR REPLACE FUNCTION notify_event_created()
RETURNS TRIGGER AS $$
DECLARE
    member_record RECORD;
BEGIN
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
            'A new event "' || NEW.title || '" has been created in your club',
            json_build_object(
                'event_id', NEW.id,
                'club_id', NEW.club_id,
                'event_title', NEW.title
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

-- Recreate the trigger
DROP TRIGGER IF EXISTS event_created_notification ON events;
CREATE TRIGGER event_created_notification
    AFTER INSERT ON events
    FOR EACH ROW
    WHEN (NEW.club_id IS NOT NULL)
    EXECUTE FUNCTION notify_event_created();
