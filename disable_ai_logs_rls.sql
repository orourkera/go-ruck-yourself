-- Temporarily disable RLS on ai_cheerleader_logs table
-- The AI cheerleader logging doesn't need strict RLS since it's just logging data
ALTER TABLE ai_cheerleader_logs DISABLE ROW LEVEL SECURITY;
