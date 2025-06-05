-- Create user_duel_stats table for tracking user duel statistics
CREATE TABLE user_duel_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  duels_created INTEGER DEFAULT 0,
  duels_joined INTEGER DEFAULT 0,
  duels_completed INTEGER DEFAULT 0,
  duels_won INTEGER DEFAULT 0,
  duels_lost INTEGER DEFAULT 0,
  duels_abandoned INTEGER DEFAULT 0,
  total_distance_challenged DECIMAL(10,2) DEFAULT 0,
  total_time_challenged INTEGER DEFAULT 0,
  total_elevation_challenged DECIMAL(10,2) DEFAULT 0,
  total_power_points_challenged INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Create indexes for performance
CREATE INDEX idx_user_duel_stats_user_id ON user_duel_stats(user_id);
CREATE INDEX idx_user_duel_stats_duels_won ON user_duel_stats(duels_won DESC);
CREATE INDEX idx_user_duel_stats_duels_completed ON user_duel_stats(duels_completed DESC);

-- Add update trigger for updated_at
CREATE TRIGGER update_user_duel_stats_updated_at BEFORE UPDATE ON user_duel_stats
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to initialize duel stats for new users
CREATE OR REPLACE FUNCTION initialize_user_duel_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_duel_stats (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-create duel stats for new users
CREATE TRIGGER auto_create_user_duel_stats
    AFTER INSERT ON "user"
    FOR EACH ROW
    EXECUTE FUNCTION initialize_user_duel_stats();
