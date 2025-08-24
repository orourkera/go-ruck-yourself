-- Migration: Create user_goal_notification_schedules table with RLS, indexes, and updated_at trigger
-- Date: 2025-08-24
-- Notes: Follows existing patterns (per-row ownership via auth.uid())

CREATE TABLE IF NOT EXISTS user_goal_notification_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goal_id UUID NOT NULL REFERENCES user_custom_goals(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    schedule_rules_json JSONB NOT NULL, -- cooldown_hours, daily_cap, quiet_hours {start,end}, preferred_time, habit_learning, milestones [...]
    next_run_at TIMESTAMPTZ,
    last_sent_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused')),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_goal_schedules_user ON user_goal_notification_schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_goal_schedules_goal ON user_goal_notification_schedules(goal_id);
CREATE INDEX IF NOT EXISTS idx_goal_schedules_status ON user_goal_notification_schedules(status);
CREATE INDEX IF NOT EXISTS idx_goal_schedules_next_run ON user_goal_notification_schedules(next_run_at);
CREATE INDEX IF NOT EXISTS idx_goal_schedules_created ON user_goal_notification_schedules(created_at);
-- Partial index for active schedules
CREATE INDEX IF NOT EXISTS idx_goal_schedules_active ON user_goal_notification_schedules(user_id) WHERE status = 'active' AND enabled = TRUE;

-- Enable RLS
ALTER TABLE user_goal_notification_schedules ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view their own goal schedules"
    ON user_goal_notification_schedules FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own goal schedules"
    ON user_goal_notification_schedules FOR INSERT
    WITH CHECK (
        auth.uid() = user_id AND EXISTS (
            SELECT 1 FROM user_custom_goals g
            WHERE g.id = goal_id AND g.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update their own goal schedules"
    ON user_goal_notification_schedules FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (
        auth.uid() = user_id AND EXISTS (
            SELECT 1 FROM user_custom_goals g
            WHERE g.id = goal_id AND g.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own goal schedules"
    ON user_goal_notification_schedules FOR DELETE
    USING (auth.uid() = user_id);

-- updated_at trigger support (reuse shared helper)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_goal_schedules_updated_at ON user_goal_notification_schedules;
CREATE TRIGGER trigger_user_goal_schedules_updated_at
    BEFORE UPDATE ON user_goal_notification_schedules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
