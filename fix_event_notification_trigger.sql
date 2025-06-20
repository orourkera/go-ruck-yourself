-- Fix event notification trigger to include event_id and club_id in data field
-- This enables proper navigation when tapping event notifications

CREATE OR REPLACE FUNCTION notify_event_created()
RETURNS TRIGGER AS $$
DECLARE
    member_record RECORD;
    club_name TEXT;
BEGIN
    -- Get club name
    SELECT name INTO club_name 
    FROM clubs 
    WHERE id = NEW.club_id;
    
    -- Create notifications for all club members except the event creator
    FOR member_record IN 
        SELECT cm.user_id 
        FROM club_memberships cm 
        WHERE cm.club_id = NEW.club_id 
        AND cm.status = 'approved'
        AND cm.user_id != NEW.creator_user_id
    LOOP
        INSERT INTO notifications (
            id,
            user_id,
            type,
            message,
            data,
            is_read,
            created_at,
            updated_at,
            club_id,
            event_id
        ) VALUES (
            gen_random_uuid(),
            member_record.user_id,
            'club_event_created',
            'New event in ' || COALESCE(club_name, 'Unknown Club') || ': ' || NEW.title,
            jsonb_build_object(
                'event_id', NEW.id,
                'club_id', NEW.club_id,
                'event_title', NEW.title,
                'club_name', club_name
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

-- Ensure the trigger exists
DROP TRIGGER IF EXISTS event_created_notification ON events;
CREATE TRIGGER event_created_notification
    AFTER INSERT ON events
    FOR EACH ROW
    WHEN (NEW.club_id IS NOT NULL)
    EXECUTE FUNCTION notify_event_created();
