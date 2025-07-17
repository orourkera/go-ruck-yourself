-- Create user_follows table for social following functionality
-- This table tracks follower-followed relationships between users

CREATE TABLE IF NOT EXISTS user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    followed_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(follower_id, followed_id),
    CHECK (follower_id != followed_id) -- Users can't follow themselves
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_followed ON user_follows(followed_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_created_at ON user_follows(created_at);

-- Enable RLS (Row Level Security)
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view follow relationships for public profiles or involving themselves
CREATE POLICY "Users can view follow relationships for public profiles" ON user_follows
    FOR SELECT USING (
        -- Can see relationships involving public profiles
        (SELECT COALESCE(is_profile_private, false) FROM "user" WHERE id = followed_id) = false
        OR 
        -- Can see relationships involving yourself
        (auth.uid() = follower_id OR auth.uid() = followed_id)
    );

-- RLS Policy: Users can only create follows where they are the follower and target is public
CREATE POLICY "Users can create follows where they are follower and target is public" ON user_follows
    FOR INSERT WITH CHECK (
        auth.uid() = follower_id 
        AND (SELECT COALESCE(is_profile_private, false) FROM "user" WHERE id = followed_id) = false
    );

-- RLS Policy: Users can only delete follows where they are the follower
CREATE POLICY "Users can delete follows where they are follower" ON user_follows
    FOR DELETE USING (auth.uid() = follower_id);

-- Add update trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_user_follows_updated_at BEFORE UPDATE ON user_follows
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Optional: Create notification trigger for new followers
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