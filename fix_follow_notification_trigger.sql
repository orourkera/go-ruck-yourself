-- Fix the follow notification trigger to use correct column names
-- This fixes the "column user_id does not exist" error when following users

CREATE OR REPLACE FUNCTION notify_new_follower()
RETURNS TRIGGER AS $$
BEGIN
    -- Send notification to the followed user
    INSERT INTO notifications (
        recipient_id,
        sender_id,
        type,
        message,
        data,
        created_at
    ) VALUES (
        NEW.followed_id,
        NEW.follower_id,
        'new_follower',
        (SELECT username FROM "user" WHERE id = NEW.follower_id) || ' started following you',
        json_build_object('followerId', NEW.follower_id),
        NOW()
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- If notifications table doesn't exist or there's an error, just continue
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_new_follower ON user_follows;

-- Create trigger for new follows (only if notifications table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications') THEN
        CREATE TRIGGER trigger_new_follower
            AFTER INSERT ON user_follows
            FOR EACH ROW
            EXECUTE FUNCTION notify_new_follower();
    END IF;
END $$; 