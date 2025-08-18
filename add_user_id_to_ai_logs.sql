-- Add user_id column to ai_cheerleader_logs table
ALTER TABLE ai_cheerleader_logs 
ADD COLUMN user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE;

-- Update RLS policy to use user_id directly
DROP POLICY IF EXISTS ai_logs_user_policy ON ai_cheerleader_logs;

CREATE POLICY ai_logs_user_policy ON ai_cheerleader_logs
    FOR ALL USING (user_id = auth.uid());
