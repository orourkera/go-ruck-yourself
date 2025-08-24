-- Migration: Create user_goal_messages table with RLS and indexes
-- Date: 2025-08-24
-- Notes: Stores sent goal-related messages for cooldown/dedupe/analytics. Categories can be stored in metadata_json.

CREATE TABLE IF NOT EXISTS user_goal_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id UUID NOT NULL REFERENCES user_custom_goals(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    channel TEXT NOT NULL CHECK (channel IN ('push','in_session','email')),
    message_type TEXT NOT NULL CHECK (message_type IN (
        'reminder','milestone','on_track','behind_pace','completion'
    )),
    content TEXT NOT NULL,
    metadata_json JSONB,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for querying history and analytics
CREATE INDEX IF NOT EXISTS idx_goal_messages_user ON user_goal_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_goal_messages_goal ON user_goal_messages(goal_id);
CREATE INDEX IF NOT EXISTS idx_goal_messages_type ON user_goal_messages(message_type);
CREATE INDEX IF NOT EXISTS idx_goal_messages_sent_at ON user_goal_messages(sent_at);
CREATE INDEX IF NOT EXISTS idx_goal_messages_created ON user_goal_messages(created_at);

-- Enable RLS
ALTER TABLE user_goal_messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies: owner-only access
CREATE POLICY "Users can view their own goal messages"
    ON user_goal_messages FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own goal messages"
    ON user_goal_messages FOR INSERT
    WITH CHECK (
        auth.uid() = user_id AND EXISTS (
            SELECT 1 FROM user_custom_goals g
            WHERE g.id = goal_id AND g.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own goal messages"
    ON user_goal_messages FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own goal messages"
    ON user_goal_messages FOR DELETE
    USING (auth.uid() = user_id);
