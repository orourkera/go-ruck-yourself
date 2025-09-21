-- Migration: Enhance coaching plan notifications and behavior tracking
-- Adds scheduling metadata to plan_sessions, user-level behavior tables, and user profile preferences

BEGIN;

-- plan_sessions notification fields
ALTER TABLE plan_sessions
    ADD COLUMN IF NOT EXISTS scheduled_start_time TIME,
    ADD COLUMN IF NOT EXISTS scheduled_timezone TEXT DEFAULT 'UTC',
    ADD COLUMN IF NOT EXISTS next_notification_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_notification_type TEXT,
    ADD COLUMN IF NOT EXISTS missed_state TEXT,
    ADD COLUMN IF NOT EXISTS notification_metadata JSONB DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_plan_sessions_next_notification
    ON plan_sessions(next_notification_at)
    WHERE next_notification_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_plan_sessions_missed_state
    ON plan_sessions(missed_state)
    WHERE missed_state IS NOT NULL;

-- User plan behavior table captures learned cadence windows per plan
CREATE TABLE IF NOT EXISTS user_plan_behavior (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_coaching_plan_id INTEGER NOT NULL REFERENCES user_coaching_plans(id) ON DELETE CASCADE,
    prime_window_start_minute SMALLINT,
    prime_window_end_minute SMALLINT,
    confidence_score NUMERIC(3,2) DEFAULT 0.0,
    weekday_pattern JSONB DEFAULT '{}'::jsonb,
    deviations JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    last_recomputed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, user_coaching_plan_id)
);

CREATE INDEX IF NOT EXISTS idx_user_plan_behavior_user ON user_plan_behavior(user_id);
CREATE INDEX IF NOT EXISTS idx_user_plan_behavior_plan ON user_plan_behavior(user_coaching_plan_id);

-- updated_at trigger helper (reuse if already exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_plan_behavior_updated_at ON user_plan_behavior;
CREATE TRIGGER trigger_user_plan_behavior_updated_at
    BEFORE UPDATE ON user_plan_behavior
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS and policies
ALTER TABLE user_plan_behavior ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their plan behavior" ON user_plan_behavior;
CREATE POLICY "Users can view their plan behavior"
    ON user_plan_behavior FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can upsert their plan behavior" ON user_plan_behavior;
CREATE POLICY "Users can upsert their plan behavior"
    ON user_plan_behavior FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their plan behavior" ON user_plan_behavior;
CREATE POLICY "Users can update their plan behavior"
    ON user_plan_behavior FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Audit log for sent notifications (for observability and dedupe)
CREATE TABLE IF NOT EXISTS plan_notification_audit (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id) ON DELETE CASCADE,
    plan_session_id INTEGER REFERENCES plan_sessions(id) ON DELETE SET NULL,
    notification_type TEXT NOT NULL,
    scheduled_for TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    status TEXT DEFAULT 'scheduled',
    payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_plan_notification_audit_user ON plan_notification_audit(user_id);
CREATE INDEX IF NOT EXISTS idx_plan_notification_audit_plan ON plan_notification_audit(user_coaching_plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_notification_audit_type ON plan_notification_audit(notification_type);

ALTER TABLE plan_notification_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their notification audit" ON plan_notification_audit;
CREATE POLICY "Users can view their notification audit"
    ON plan_notification_audit FOR SELECT
    USING (auth.uid() = user_id);

-- User profile preferences for notifications
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
    ) THEN
        ALTER TABLE user_profiles
            ADD COLUMN IF NOT EXISTS plan_notification_prefs JSONB DEFAULT '{}'::jsonb,
            ADD COLUMN IF NOT EXISTS plan_quiet_hours_start SMALLINT,
            ADD COLUMN IF NOT EXISTS plan_quiet_hours_end SMALLINT,
            ADD COLUMN IF NOT EXISTS plan_evening_brief_offset_minutes INTEGER DEFAULT 540,
            ADD COLUMN IF NOT EXISTS plan_notification_timezone TEXT DEFAULT 'UTC';
    ELSE
        ALTER TABLE public."user"
            ADD COLUMN IF NOT EXISTS plan_notification_prefs JSONB DEFAULT '{}'::jsonb,
            ADD COLUMN IF NOT EXISTS plan_quiet_hours_start SMALLINT,
            ADD COLUMN IF NOT EXISTS plan_quiet_hours_end SMALLINT,
            ADD COLUMN IF NOT EXISTS plan_evening_brief_offset_minutes INTEGER DEFAULT 540,
            ADD COLUMN IF NOT EXISTS plan_notification_timezone TEXT DEFAULT 'UTC';
    END IF;
END;
$$;

COMMIT;
