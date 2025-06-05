-- Create duels table for challenge management
CREATE TABLE duels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  title VARCHAR(50) NOT NULL,
  challenge_type VARCHAR(20) NOT NULL CHECK (challenge_type IN ('distance', 'time', 'elevation', 'power_points')),
  target_value DECIMAL(10,2) NOT NULL,
  timeframe_hours INTEGER NOT NULL,
  creator_city VARCHAR(100) NOT NULL,
  creator_state VARCHAR(100) NOT NULL,
  is_public BOOLEAN DEFAULT true,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  starts_at TIMESTAMP WITH TIME ZONE,
  ends_at TIMESTAMP WITH TIME ZONE,
  winner_id UUID REFERENCES "user"(id),
  max_participants INTEGER DEFAULT 2
);

-- Create indexes for performance
CREATE INDEX idx_duels_creator_id ON duels(creator_id);
CREATE INDEX idx_duels_status ON duels(status);
CREATE INDEX idx_duels_challenge_type ON duels(challenge_type);
CREATE INDEX idx_duels_is_public ON duels(is_public);
CREATE INDEX idx_duels_created_at ON duels(created_at DESC);
CREATE INDEX idx_duels_ends_at ON duels(ends_at);

-- Add update trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_duels_updated_at BEFORE UPDATE ON duels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
