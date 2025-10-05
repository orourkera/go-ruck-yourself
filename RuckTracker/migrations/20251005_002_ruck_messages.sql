-- Create table for live ruck messages
CREATE TABLE IF NOT EXISTS ruck_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ruck_id INTEGER NOT NULL REFERENCES ruck_session(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  voice_id TEXT, -- ElevenLabs voice identifier (drill_sergeant, supportive_friend, etc.)
  audio_url TEXT, -- URL to generated audio file in Supabase storage
  created_at TIMESTAMPTZ DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  played_at TIMESTAMPTZ,
  CONSTRAINT valid_message_length CHECK (length(message) > 0 AND length(message) <= 200)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_ruck_messages_ruck_id ON ruck_messages(ruck_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ruck_messages_recipient ON ruck_messages(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ruck_messages_sender ON ruck_messages(sender_id, created_at DESC);

-- Comments
COMMENT ON TABLE ruck_messages IS 'Messages sent to users during active ruck sessions';
COMMENT ON COLUMN ruck_messages.voice_id IS 'AI voice personality used for text-to-speech';
COMMENT ON COLUMN ruck_messages.audio_url IS 'Public URL to generated audio file';
COMMENT ON COLUMN ruck_messages.played_at IS 'When recipient played the audio message';
