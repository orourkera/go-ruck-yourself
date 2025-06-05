-- Create duel_participants table for tracking participant progress
CREATE TABLE duel_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  current_value DECIMAL(10,2) DEFAULT 0,
  last_session_id INTEGER REFERENCES ruck_session(id),
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(duel_id, user_id)
);

-- Create indexes for performance
CREATE INDEX idx_duel_participants_duel_id ON duel_participants(duel_id);
CREATE INDEX idx_duel_participants_user_id ON duel_participants(user_id);
CREATE INDEX idx_duel_participants_status ON duel_participants(status);
CREATE INDEX idx_duel_participants_current_value ON duel_participants(current_value DESC);

-- Add update trigger for updated_at
CREATE TRIGGER update_duel_participants_updated_at BEFORE UPDATE ON duel_participants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
