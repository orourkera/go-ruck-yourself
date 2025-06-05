-- Create duel_sessions table for linking sessions to duels
CREATE TABLE duel_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES duel_participants(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES ruck_sessions(id) ON DELETE CASCADE,
  contribution_value DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(duel_id, session_id)
);

-- Create indexes for performance
CREATE INDEX idx_duel_sessions_duel_id ON duel_sessions(duel_id);
CREATE INDEX idx_duel_sessions_participant_id ON duel_sessions(participant_id);
CREATE INDEX idx_duel_sessions_session_id ON duel_sessions(session_id);
CREATE INDEX idx_duel_sessions_created_at ON duel_sessions(created_at DESC);

-- Add update trigger for updated_at
CREATE TRIGGER update_duel_sessions_updated_at BEFORE UPDATE ON duel_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
