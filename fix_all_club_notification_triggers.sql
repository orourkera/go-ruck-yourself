-- Fixed club notification triggers
-- Adds missing 'message' field to prevent null constraint violations

-- 1. Fix notify_club_join_request trigger
CREATE OR REPLACE FUNCTION notify_club_join_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
declare
  c record;
  requester_username text;
begin
  if new.status = 'pending' then
    -- Get club details
    select id, creator_id, name
      into c
      from public.clubs
     where id = new.club_id;

    -- Get requester username for the message
    select username
      into requester_username
      from public.users
     where id = new.user_id;

    -- Create notification with required message field
    insert into public.notifications
           (recipient_id, sender_id, type, club_id, message, data)
    values (c.creator_id,
            new.user_id,
            'club_join_request',
            new.club_id,
            requester_username || ' wants to join ' || c.name,
            jsonb_build_object(
              'requester_id', new.user_id,
              'club_name', c.name,
              'requester_username', requester_username));
  end if;
  return new;
end;
$$;

-- 2. Fix notify_club_membership_approval trigger
CREATE OR REPLACE FUNCTION notify_club_membership_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
declare
  c record;
  approver_username text;
begin
  if new.status = 'approved' and old.status = 'pending' then
    -- Get club details
    select id, name
      into c
      from public.clubs
     where id = new.club_id;

    -- Get approver username (could be creator or admin)
    select username
      into approver_username
      from public.users
     where id = new.approved_by; -- assuming there's an approved_by field

    -- Create notification with required message field
    insert into public.notifications
           (recipient_id, sender_id, type, club_id, message, data)
    values (new.user_id,
            new.approved_by,
            'club_membership_approved',
            new.club_id,
            'You have been approved to join ' || c.name,
            jsonb_build_object(
              'club_name', c.name,
              'approved_by', new.approved_by,
              'approver_username', approver_username));
  end if;
  return new;
end;
$$;

-- 3. Fix notify_club_deleted trigger
CREATE OR REPLACE FUNCTION notify_club_deleted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
declare
  member_record record;
  deleter_username text;
begin
  -- Get username of person who deleted the club
  select username
    into deleter_username
    from public.users
   where id = old.creator_id; -- assuming creator is the one who can delete

  -- Notify all members that the club has been deleted
  for member_record in
    select user_id
      from public.club_memberships
     where club_id = old.id
       and status = 'approved'
       and user_id != old.creator_id -- don't notify the creator who deleted it
  loop
    insert into public.notifications
           (recipient_id, sender_id, type, club_id, message, data)
    values (member_record.user_id,
            old.creator_id,
            'club_deleted',
            old.id,
            'The club "' || old.name || '" has been deleted',
            jsonb_build_object(
              'club_name', old.name,
              'deleted_by', old.creator_id,
              'deleter_username', deleter_username));
  end loop;
  
  return old;
end;
$$;

-- Apply the triggers to their respective tables
DROP TRIGGER IF EXISTS notify_club_join_request_trigger ON club_memberships;
CREATE TRIGGER notify_club_join_request_trigger
  AFTER INSERT ON club_memberships
  FOR EACH ROW
  EXECUTE FUNCTION notify_club_join_request();

DROP TRIGGER IF EXISTS notify_club_membership_approval_trigger ON club_memberships;
CREATE TRIGGER notify_club_membership_approval_trigger
  AFTER UPDATE ON club_memberships
  FOR EACH ROW
  EXECUTE FUNCTION notify_club_membership_approval();

DROP TRIGGER IF EXISTS notify_club_deleted_trigger ON clubs;
CREATE TRIGGER notify_club_deleted_trigger
  AFTER DELETE ON clubs
  FOR EACH ROW
  EXECUTE FUNCTION notify_club_deleted();
