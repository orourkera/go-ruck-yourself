-- Simple AI Cheerleader Logging Table
-- Just tracks the basics: session, personality, and AI response

CREATE TABLE ai_cheerleader_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id INTEGER NOT NULL REFERENCES ruck_session(id) ON DELETE CASCADE,
    personality VARCHAR(50) NOT NULL,
    openai_response TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Basic index for querying by session
CREATE INDEX idx_ai_logs_session ON ai_cheerleader_logs(session_id);
CREATE INDEX idx_ai_logs_created ON ai_cheerleader_logs(created_at);

-- RLS Policy - users can only see their own session logs
ALTER TABLE ai_cheerleader_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_logs_user_policy ON ai_cheerleader_logs
    FOR ALL USING (
        session_id IN (
            SELECT id FROM ruck_session WHERE user_id = auth.uid()
        )
    );
