-- Fixed club join request notification trigger
-- Adds missing 'message' field to prevent null constraint violations

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
            requester_username || ' wants to join ' || c.name,  -- Added message field
            jsonb_build_object(
              'requester_id', new.user_id,
              'club_name', c.name,
              'requester_username', requester_username));  -- Added username to data
  end if;
  return new;
end;
$$;
