-- AI Cheerleader Analytics Database Schema
-- This tracks all AI interactions for analysis and optimization

-- Main table for AI cheerleader interactions
CREATE TABLE ai_cheerleader_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES ruck_session(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- AI Response Data
    personality VARCHAR(50) NOT NULL,
    trigger_type VARCHAR(30) NOT NULL, -- 'pace_drop', 'milestone', 'heart_rate_spike', etc.
    openai_prompt TEXT NOT NULL, -- Full prompt sent to OpenAI
    openai_response TEXT NOT NULL, -- Generated text response
    elevenlabs_voice_id VARCHAR(50), -- Voice ID used for synthesis
    
    -- Context at time of interaction
    session_context JSONB NOT NULL, -- elapsed_time, distance, pace, heart_rate, etc.
    location_context JSONB, -- city, weather, terrain, etc.
    trigger_data JSONB, -- specific trigger details
    
    -- User Preferences
    explicit_content_enabled BOOLEAN NOT NULL DEFAULT false,
    user_gender VARCHAR(10),
    user_prefer_metric BOOLEAN,
    
    -- Performance Metrics
    generation_time_ms INTEGER, -- How long OpenAI took to respond
    synthesis_success BOOLEAN DEFAULT true, -- Did ElevenLabs synthesis work
    synthesis_time_ms INTEGER, -- How long voice synthesis took
    
    -- Analytics Fields
    message_length INTEGER, -- Character count of response
    word_count INTEGER, -- Word count of response
    has_location_reference BOOLEAN DEFAULT false, -- Does message reference location
    has_weather_reference BOOLEAN DEFAULT false, -- Does message reference weather
    has_personal_reference BOOLEAN DEFAULT false, -- Does message use user's name
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient querying
CREATE INDEX idx_ai_interactions_session ON ai_cheerleader_interactions(session_id);
CREATE INDEX idx_ai_interactions_user ON ai_cheerleader_interactions(user_id);
CREATE INDEX idx_ai_interactions_personality ON ai_cheerleader_interactions(personality);
CREATE INDEX idx_ai_interactions_trigger ON ai_cheerleader_interactions(trigger_type);
CREATE INDEX idx_ai_interactions_created ON ai_cheerleader_interactions(created_at);

-- Composite indexes for common analytics queries
CREATE INDEX idx_ai_interactions_user_personality ON ai_cheerleader_interactions(user_id, personality);
CREATE INDEX idx_ai_interactions_date_personality ON ai_cheerleader_interactions(created_at, personality);

-- Table for tracking personality selection patterns
CREATE TABLE ai_personality_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES ruck_session(id) ON DELETE CASCADE,
    
    personality VARCHAR(50) NOT NULL,
    explicit_content_enabled BOOLEAN NOT NULL DEFAULT false,
    
    -- Session details when personality was selected
    session_duration_planned_minutes INTEGER,
    session_distance_planned_km DECIMAL(8,3),
    ruck_weight_kg DECIMAL(5,2),
    
    -- User context
    user_total_rucks INTEGER DEFAULT 0, -- How experienced is the user
    user_total_distance_km DECIMAL(10,3) DEFAULT 0,
    
    selected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_personality_selections_user ON ai_personality_selections(user_id);
CREATE INDEX idx_personality_selections_personality ON ai_personality_selections(personality);
CREATE INDEX idx_personality_selections_date ON ai_personality_selections(selected_at);

-- Table for tracking AI cheerleader feature usage
CREATE TABLE ai_cheerleader_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES ruck_session(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Session settings
    personality VARCHAR(50) NOT NULL,
    explicit_content_enabled BOOLEAN NOT NULL DEFAULT false,
    ai_enabled_at_start BOOLEAN NOT NULL DEFAULT true,
    
    -- Usage metrics
    total_interactions INTEGER DEFAULT 0,
    total_triggers_fired INTEGER DEFAULT 0,
    total_successful_syntheses INTEGER DEFAULT 0,
    total_failed_syntheses INTEGER DEFAULT 0,
    
    -- Performance metrics
    avg_generation_time_ms INTEGER,
    avg_synthesis_time_ms INTEGER,
    
    -- Session outcome
    session_completed BOOLEAN DEFAULT false,
    ai_disabled_during_session BOOLEAN DEFAULT false,
    ai_disabled_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_sessions_session ON ai_cheerleader_sessions(session_id);
CREATE INDEX idx_ai_sessions_user ON ai_cheerleader_sessions(user_id);
CREATE INDEX idx_ai_sessions_personality ON ai_cheerleader_sessions(personality);

-- View for common analytics queries
CREATE OR REPLACE VIEW ai_cheerleader_analytics AS
SELECT 
    i.personality,
    i.trigger_type,
    COUNT(*) as interaction_count,
    AVG(i.generation_time_ms) as avg_generation_time,
    AVG(i.synthesis_time_ms) as avg_synthesis_time,
    AVG(i.message_length) as avg_message_length,
    AVG(i.word_count) as avg_word_count,
    SUM(CASE WHEN i.has_location_reference THEN 1 ELSE 0 END) as location_references,
    SUM(CASE WHEN i.has_weather_reference THEN 1 ELSE 0 END) as weather_references,
    SUM(CASE WHEN i.has_personal_reference THEN 1 ELSE 0 END) as personal_references,
    COUNT(DISTINCT i.user_id) as unique_users,
    DATE_TRUNC('day', i.created_at) as date
FROM ai_cheerleader_interactions i
GROUP BY i.personality, i.trigger_type, DATE_TRUNC('day', i.created_at)
ORDER BY date DESC, interaction_count DESC;

-- RLS Policies
ALTER TABLE ai_cheerleader_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_personality_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_cheerleader_sessions ENABLE ROW LEVEL SECURITY;

-- Users can only see their own data
CREATE POLICY ai_interactions_user_policy ON ai_cheerleader_interactions
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY ai_selections_user_policy ON ai_personality_selections
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY ai_sessions_user_policy ON ai_cheerleader_sessions
    FOR ALL USING (auth.uid() = user_id);

-- Admin users can see aggregated analytics (modify based on your admin setup)
-- CREATE POLICY ai_analytics_admin_policy ON ai_cheerleader_interactions
--     FOR SELECT USING (auth.jwt() ->> 'role' = 'admin');
