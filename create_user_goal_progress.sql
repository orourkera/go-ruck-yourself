-- Migration: Create user_goal_progress table with RLS, indexes, and updated_at trigger
-- Date: 2025-08-24
-- Notes: Mirrors patterns used in create_routes_tables.sql

CREATE TABLE IF NOT EXISTS user_goal_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id UUID NOT NULL REFERENCES user_custom_goals(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    current_value DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (current_value >= 0),
    progress_percent DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (progress_percent >= 0 AND progress_percent <= 100),
    last_evaluated_at TIMESTAMPTZ,
    breakdown_json JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
);

-- Indexes for performance and lookups
CREATE INDEX IF NOT EXISTS idx_user_goal_progress_user ON user_goal_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_user_goal_progress_goal ON user_goal_progress(goal_id);
CREATE INDEX IF NOT EXISTS idx_user_goal_progress_last_eval ON user_goal_progress(last_evaluated_at);
CREATE INDEX IF NOT EXISTS idx_user_goal_progress_created ON user_goal_progress(created_at);

-- Enable RLS
ALTER TABLE user_goal_progress ENABLE ROW LEVEL SECURITY;

-- RLS: Owners can access their progress
CREATE POLICY "Users can view their own goal progress"
    ON user_goal_progress FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own goal progress"
    ON user_goal_progress FOR INSERT
    WITH CHECK (
        auth.uid() = user_id AND EXISTS (
            SELECT 1 FROM user_custom_goals g
            WHERE g.id = goal_id AND g.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own goal progress"
    ON user_goal_progress FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (
        auth.uid() = user_id AND EXISTS (
            SELECT 1 FROM user_custom_goals g
            WHERE g.id = goal_id AND g.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own goal progress"
    ON user_goal_progress FOR DELETE
    USING (auth.uid() = user_id);

-- updated_at trigger support
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_goal_progress_updated_at ON user_goal_progress;
CREATE TRIGGER trigger_user_goal_progress_updated_at
    BEFORE UPDATE ON user_goal_progress
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
