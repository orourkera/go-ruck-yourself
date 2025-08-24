-- Migration: Create user_custom_goals table with RLS, indexes, and updated_at trigger
-- Date: 2025-08-24
-- Notes: Mirrors patterns used in create_routes_tables.sql and create_user_follows_table.sql

CREATE TABLE IF NOT EXISTS user_custom_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Goal definition
    title TEXT NOT NULL,
    description TEXT,
    metric TEXT NOT NULL CHECK (metric IN (
        'distance_km_total',
        'session_count',
        'streak_days',
        'elevation_gain_m_total',
        'duration_minutes_total',
        'steps_total',
        'power_points_total',
        'load_kg_min_sessions'
    )),
    target_value DOUBLE PRECISION NOT NULL CHECK (target_value >= 0),
    unit TEXT NOT NULL CHECK (unit IN ('km','mi','minutes','steps','m','kg','points')),
    window TEXT CHECK (window IN ('7d','30d','weekly','monthly','until_deadline')),
    constraints_json JSONB,

    -- Timing
    start_at TIMESTAMPTZ DEFAULT NOW(),
    end_at TIMESTAMPTZ,
    deadline_at TIMESTAMPTZ,

    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN ('active','paused','completed','canceled','expired')),

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for common filters and evaluators
CREATE INDEX IF NOT EXISTS idx_user_custom_goals_user ON user_custom_goals(user_id);
CREATE INDEX IF NOT EXISTS idx_user_custom_goals_status ON user_custom_goals(status);
CREATE INDEX IF NOT EXISTS idx_user_custom_goals_created_at ON user_custom_goals(created_at);
-- Partial index to speed active goal scans per user
CREATE INDEX IF NOT EXISTS idx_user_custom_goals_active ON user_custom_goals(user_id) WHERE status = 'active';

-- Enable Row Level Security
ALTER TABLE user_custom_goals ENABLE ROW LEVEL SECURITY;

-- RLS: Owners only (per-row user ownership). Separate policies per command.
DROP POLICY IF EXISTS "Users can view their own custom goals" ON user_custom_goals;
CREATE POLICY "Users can view their own custom goals"
    ON user_custom_goals FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create their own custom goals" ON user_custom_goals;
CREATE POLICY "Users can create their own custom goals"
    ON user_custom_goals FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own custom goals" ON user_custom_goals;
CREATE POLICY "Users can update their own custom goals"
    ON user_custom_goals FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own custom goals" ON user_custom_goals;
CREATE POLICY "Users can delete their own custom goals"
    ON user_custom_goals FOR DELETE
    USING (auth.uid() = user_id);

-- updated_at trigger support (reuse shared helper)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_custom_goals_updated_at ON user_custom_goals;
CREATE TRIGGER trigger_user_custom_goals_updated_at
    BEFORE UPDATE ON user_custom_goals
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
