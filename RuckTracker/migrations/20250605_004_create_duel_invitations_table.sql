-- Create duel_invitations table for email invitations
CREATE TABLE duel_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  duel_id UUID NOT NULL REFERENCES duels(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
  invitee_email VARCHAR(255) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(duel_id, invitee_email)
);

-- Create indexes for performance
CREATE INDEX idx_duel_invitations_duel_id ON duel_invitations(duel_id);
CREATE INDEX idx_duel_invitations_inviter_id ON duel_invitations(inviter_id);
CREATE INDEX idx_duel_invitations_invitee_email ON duel_invitations(invitee_email);
CREATE INDEX idx_duel_invitations_status ON duel_invitations(status);
CREATE INDEX idx_duel_invitations_expires_at ON duel_invitations(expires_at);

-- Add update trigger for updated_at
CREATE TRIGGER update_duel_invitations_updated_at BEFORE UPDATE ON duel_invitations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
