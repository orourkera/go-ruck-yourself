-- Migration: Create user coaching plans and related tables
-- This creates the tables needed for plan instantiation, progress tracking, and modifications

-- Table 1: user_coaching_plans (active user plans with dates and progress)
CREATE TABLE user_coaching_plans (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    coaching_plan_id INTEGER REFERENCES coaching_plan_templates(id) ON DELETE RESTRICT,
    coaching_personality VARCHAR(50) NOT NULL DEFAULT 'supportive_friend',
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    current_week INTEGER NOT NULL DEFAULT 1,
    current_status VARCHAR(50) NOT NULL DEFAULT 'active',
    plan_modifications JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_personality CHECK (coaching_personality IN ('drill_sergeant', 'supportive_friend', 'data_nerd', 'minimalist')),
    CONSTRAINT valid_status CHECK (current_status IN ('active', 'paused', 'completed', 'cancelled')),
    CONSTRAINT valid_week CHECK (current_week > 0),
    
    -- Unique constraint: user can only have one active plan at a time
    UNIQUE (user_id, current_status) DEFERRABLE INITIALLY DEFERRED
);

-- Table 2: plan_sessions (session tracking against plan expectations)
CREATE TABLE plan_sessions (
    id SERIAL PRIMARY KEY,
    user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id) ON DELETE CASCADE,
    session_id UUID REFERENCES ruck_session(id) ON DELETE SET NULL,
    planned_week INTEGER NOT NULL,
    planned_session_type VARCHAR(100) NOT NULL,
    completion_status VARCHAR(50) NOT NULL DEFAULT 'planned',
    plan_adherence_score DECIMAL(3,2) DEFAULT NULL,
    notes TEXT,
    scheduled_date DATE,
    completed_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_completion_status CHECK (completion_status IN ('planned', 'completed', 'missed', 'modified', 'skipped')),
    CONSTRAINT valid_adherence_score CHECK (plan_adherence_score >= 0.0 AND plan_adherence_score <= 1.0),
    CONSTRAINT valid_week CHECK (planned_week > 0)
);

-- Table 3: plan_modifications (history of plan changes)
CREATE TABLE plan_modifications (
    id SERIAL PRIMARY KEY,
    user_coaching_plan_id INTEGER REFERENCES user_coaching_plans(id) ON DELETE CASCADE,
    modification_type VARCHAR(100) NOT NULL,
    from_value JSONB,
    to_value JSONB,
    reason VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_modification_type CHECK (modification_type IN (
        'extend_duration', 'compress_duration', 'change_goal_type', 
        'enable_travel_mode', 'enable_sick_mode', 'seasonal_adjustment',
        'life_situation_change', 'personality_change', 'intensity_adjustment'
    ))
);

-- Indexes for performance
CREATE INDEX idx_user_coaching_plans_user_status ON user_coaching_plans(user_id, current_status);
CREATE INDEX idx_user_coaching_plans_start_date ON user_coaching_plans(start_date);
CREATE INDEX idx_plan_sessions_user_plan ON plan_sessions(user_coaching_plan_id);
CREATE INDEX idx_plan_sessions_week_status ON plan_sessions(planned_week, completion_status);
CREATE INDEX idx_plan_sessions_scheduled_date ON plan_sessions(scheduled_date);
CREATE INDEX idx_plan_modifications_user_plan ON plan_modifications(user_coaching_plan_id);
CREATE INDEX idx_plan_modifications_type ON plan_modifications(modification_type);

-- Triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_user_coaching_plans_updated_at 
    BEFORE UPDATE ON user_coaching_plans 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_plan_sessions_updated_at 
    BEFORE UPDATE ON plan_sessions 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS Policies (Row Level Security)
ALTER TABLE user_coaching_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_modifications ENABLE ROW LEVEL SECURITY;

-- Users can only access their own coaching plans
CREATE POLICY "Users can view own coaching plans" ON user_coaching_plans
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own coaching plans" ON user_coaching_plans
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own coaching plans" ON user_coaching_plans
    FOR UPDATE USING (auth.uid() = user_id);

-- Users can only access plan sessions for their own plans
CREATE POLICY "Users can view own plan sessions" ON plan_sessions
    FOR SELECT USING (
        user_coaching_plan_id IN (
            SELECT id FROM user_coaching_plans WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own plan sessions" ON plan_sessions
    FOR INSERT WITH CHECK (
        user_coaching_plan_id IN (
            SELECT id FROM user_coaching_plans WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own plan sessions" ON plan_sessions
    FOR UPDATE USING (
        user_coaching_plan_id IN (
            SELECT id FROM user_coaching_plans WHERE user_id = auth.uid()
        )
    );

-- Users can only access plan modifications for their own plans
CREATE POLICY "Users can view own plan modifications" ON plan_modifications
    FOR SELECT USING (
        user_coaching_plan_id IN (
            SELECT id FROM user_coaching_plans WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own plan modifications" ON plan_modifications
    FOR INSERT WITH CHECK (
        user_coaching_plan_id IN (
            SELECT id FROM user_coaching_plans WHERE user_id = auth.uid()
        )
    );
