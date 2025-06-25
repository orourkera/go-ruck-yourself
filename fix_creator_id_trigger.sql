-- Fix the club membership notification trigger to use correct column name
-- The clubs table uses 'admin_user_id', not 'creator_id'

DROP TRIGGER IF EXISTS club_membership_notifications_trigger ON club_memberships;
DROP FUNCTION IF EXISTS handle_club_membership_notifications();

CREATE OR REPLACE FUNCTION handle_club_membership_notifications()
RETURNS TRIGGER AS $$
DECLARE
  c RECORD;
  approver_username TEXT;
  approver_id UUID;
  requester_username TEXT;
BEGIN
  -- Handle new join requests (INSERT)
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    SELECT id, name, admin_user_id
      INTO c
      FROM public.clubs
     WHERE id = NEW.club_id;

    -- Get requester username for the message
    SELECT username
      INTO requester_username
      FROM public."user"
     WHERE id = NEW.user_id;

    INSERT INTO public.notifications
           (recipient_id, sender_id, type, club_id, message, data)
    VALUES (c.admin_user_id,  -- FIXED: was c.creator_id
            NEW.user_id,
            'club_membership_request',
            NEW.club_id,
            requester_username || ' wants to join ' || c.name,
            jsonb_build_object(
              'club_name', c.name,
              'club_id', c.id,
              'requester_id', NEW.user_id,
              'requester_username', requester_username));

  -- Handle approval/rejection (UPDATE)
  ELSIF TG_OP = 'UPDATE' AND NEW.status != OLD.status AND OLD.status = 'pending' THEN
    SELECT id, name, admin_user_id
      INTO c
      FROM public.clubs
     WHERE id = NEW.club_id;

    -- Determine approver
    IF NEW.approved_by IS NOT NULL THEN
      approver_id := NEW.approved_by;
    ELSE
      BEGIN
        approver_id := (current_setting('request.jwt.claim.sub', true))::UUID;
      EXCEPTION WHEN OTHERS THEN
        approver_id := c.admin_user_id;  -- FIXED: was c.creator_id
      END;
    END IF;

    IF NEW.status = 'approved' THEN
      INSERT INTO public.notifications
             (recipient_id, sender_id, type, club_id, message, data)
      VALUES (NEW.user_id,
              approver_id,
              'club_membership_approved',
              NEW.club_id,
              'Your request to join ' || c.name || ' has been approved',
              jsonb_build_object(
                'club_name', c.name,
                'club_id', c.id));

    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO public.notifications
             (recipient_id, sender_id, type, club_id, message, data)
      VALUES (NEW.user_id,
              approver_id,
              'club_membership_rejected',
              NEW.club_id,
              'Your request to join ' || c.name || ' was not approved',
              jsonb_build_object(
                'club_name', c.name,
                'club_id', c.id));
    END IF;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create ONE trigger for both INSERT and UPDATE
CREATE TRIGGER club_membership_notifications_trigger
  AFTER INSERT OR UPDATE ON club_memberships
  FOR EACH ROW
  EXECUTE FUNCTION handle_club_membership_notifications();
