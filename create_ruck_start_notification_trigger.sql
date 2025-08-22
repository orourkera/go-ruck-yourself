-- Create trigger for ruck start notifications
-- Secure and efficient: SECURITY DEFINER, safe search_path, bulk insert

CREATE OR REPLACE FUNCTION public.notify_ruck_started()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_name TEXT;
BEGIN
    -- Fire when a ruck is inserted already in progress OR transitioned to in_progress
    IF (
        TG_OP = 'INSERT' AND NEW.status = 'in_progress'
    ) OR (
        TG_OP = 'UPDATE' AND NEW.status = 'in_progress' AND (OLD.status IS NULL OR OLD.status <> 'in_progress')
    ) THEN
        -- Get the user's display name
        SELECT COALESCE(display_name, username, 'Someone') INTO user_name
        FROM "user"
        WHERE id = NEW.user_id;

        -- Fan-out notifications to followers in a single statement
        INSERT INTO notifications (
            recipient_id,
            sender_id,
            type,
            message,
            data
        )
        SELECT
            uf.follower_id,
            NEW.user_id,
            'ruck_started',
            user_name || ' started rucking!',
            jsonb_build_object(
                'ruck_id', NEW.id,
                'rucker_name', user_name
            )
        FROM user_follows uf
        WHERE uf.followed_id = NEW.user_id;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log but do not block the ruck start
        RAISE WARNING 'notify_ruck_started error: %', SQLERRM;
        RETURN NEW;
END;
$$;

-- Ensure secure ownership
ALTER FUNCTION public.notify_ruck_started() OWNER TO postgres;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS ruck_start_notifications_trigger ON public.ruck_session;

-- Create trigger for ruck start notifications (on insert or status update)
CREATE TRIGGER ruck_start_notifications_trigger
    AFTER INSERT OR UPDATE ON public.ruck_session
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_ruck_started();
