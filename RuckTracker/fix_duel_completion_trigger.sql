-- Fix duel completion trigger to include required message field
CREATE OR REPLACE FUNCTION notify_duel_completed()
RETURNS TRIGGER AS $$
DECLARE
  p record;
  message_text text;
BEGIN
  IF OLD.status = 'active' AND NEW.status = 'completed' THEN
    -- Generate the message text
    message_text := '''' || NEW.title || ''' has completed! Check the results';
    
    FOR p IN
      SELECT user_id
        FROM public.duel_participants
       WHERE duel_id = NEW.id
         AND status   = 'accepted'
    LOOP
      INSERT INTO public.notifications
             (recipient_id, sender_id, type, message, duel_id, data)
      VALUES (p.user_id,
              NEW.creator_id,
              'duel_completed',
              message_text,
              NEW.id,
              jsonb_build_object(
                'duel_name', NEW.title,
                'duel_id', NEW.id,
                'message', message_text));
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
