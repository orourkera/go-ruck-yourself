-- Create coaching plans table to store personalized plans for users
CREATE TABLE coaching_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    base_plan_id TEXT NOT NULL, -- 'fat-loss', 'get-faster', etc.
    plan_name TEXT NOT NULL, -- e.g. "Fat Loss & Feel Better"
    duration_weeks INTEGER NOT NULL,
    
    -- Personalization data (from the 6 questions)
    personalization JSONB NOT NULL DEFAULT '{}',
    
    -- Generated plan structure (personalized version of base plan)
    plan_structure JSONB NOT NULL DEFAULT '{}',
    
    -- Coaching personality selected
    coaching_personality TEXT NOT NULL, -- 'drill-sergeant', 'supportive-friend', etc.
    
    -- Plan status
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'archived')),
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    
    -- Ensure user can only have one active plan per base plan type
    UNIQUE(user_id, base_plan_id, status) DEFERRABLE INITIALLY DEFERRED
);

-- Add RLS policies
ALTER TABLE coaching_plans ENABLE ROW LEVEL SECURITY;

-- Users can only see their own coaching plans
CREATE POLICY "Users can view own coaching plans" ON coaching_plans
    FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own coaching plans
CREATE POLICY "Users can insert own coaching plans" ON coaching_plans
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own coaching plans
CREATE POLICY "Users can update own coaching plans" ON coaching_plans
    FOR UPDATE USING (auth.uid() = user_id);

-- Users can delete their own coaching plans
CREATE POLICY "Users can delete own coaching plans" ON coaching_plans
    FOR DELETE USING (auth.uid() = user_id);

-- Create indexes for performance
CREATE INDEX idx_coaching_plans_user_id ON coaching_plans(user_id);
CREATE INDEX idx_coaching_plans_status ON coaching_plans(status);
CREATE INDEX idx_coaching_plans_base_plan_id ON coaching_plans(base_plan_id);
CREATE INDEX idx_coaching_plans_user_status ON coaching_plans(user_id, status);

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_coaching_plans_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_coaching_plans_updated_at
    BEFORE UPDATE ON coaching_plans
    FOR EACH ROW
    EXECUTE FUNCTION update_coaching_plans_updated_at();