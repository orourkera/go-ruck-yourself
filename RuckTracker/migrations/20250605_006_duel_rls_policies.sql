-- Enable RLS on all duel tables
ALTER TABLE duels ENABLE ROW LEVEL SECURITY;
ALTER TABLE duel_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE duel_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE duel_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_duel_stats ENABLE ROW LEVEL SECURITY;

-- Service role policies (allow all operations for backend)
-- DUELS table policies
CREATE POLICY "Service role can manage duels" ON duels
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY "Users can view public duels" ON duels
FOR SELECT TO authenticated
USING (is_public = true OR creator_id = auth.uid());

CREATE POLICY "Users can create duels" ON duels
FOR INSERT TO authenticated
WITH CHECK (creator_id = auth.uid());

CREATE POLICY "Users can update their own duels" ON duels
FOR UPDATE TO authenticated
USING (creator_id = auth.uid())
WITH CHECK (creator_id = auth.uid());

-- DUEL_PARTICIPANTS table policies
CREATE POLICY "Service role can manage duel participants" ON duel_participants
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY "Users can view participants in their duels" ON duel_participants
FOR SELECT TO authenticated
USING (
  user_id = auth.uid() OR 
  duel_id IN (
    SELECT id FROM duels 
    WHERE creator_id = auth.uid() OR is_public = true
  )
);

CREATE POLICY "Users can join duels" ON duel_participants
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own participation" ON duel_participants
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DUEL_SESSIONS table policies
CREATE POLICY "Service role can manage duel sessions" ON duel_sessions
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY "Users can view their own duel sessions" ON duel_sessions
FOR SELECT TO authenticated
USING (
  participant_id IN (
    SELECT id FROM duel_participants WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Users can create their own duel sessions" ON duel_sessions
FOR INSERT TO authenticated
WITH CHECK (
  participant_id IN (
    SELECT id FROM duel_participants WHERE user_id = auth.uid()
  )
);

-- DUEL_INVITATIONS table policies
CREATE POLICY "Service role can manage duel invitations" ON duel_invitations
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY "Users can view their invitations" ON duel_invitations
FOR SELECT TO authenticated
USING (
  invitee_email = (SELECT email FROM auth.users WHERE id = auth.uid()) OR
  inviter_id = auth.uid()
);

CREATE POLICY "Users can create invitations for their duels" ON duel_invitations
FOR INSERT TO authenticated
WITH CHECK (inviter_id = auth.uid());

CREATE POLICY "Users can update invitations they received" ON duel_invitations
FOR UPDATE TO authenticated
USING (invitee_email = (SELECT email FROM auth.users WHERE id = auth.uid()))
WITH CHECK (invitee_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

-- USER_DUEL_STATS table policies
CREATE POLICY "Service role can manage user duel stats" ON user_duel_stats
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

CREATE POLICY "Users can view their own duel stats" ON user_duel_stats
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users can view public duel stats" ON user_duel_stats
FOR SELECT TO authenticated
USING (true);

-- Allow service role to create stats records
CREATE POLICY "Service role can create user duel stats" ON user_duel_stats
FOR INSERT TO service_role
WITH CHECK (true);

CREATE POLICY "Service role can update user duel stats" ON user_duel_stats
FOR UPDATE TO service_role
USING (true)
WITH CHECK (true);
