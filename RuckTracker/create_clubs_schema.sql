-- Clubs & Events Database Schema
-- This script creates the complete schema for clubs and events functionality

-- Clubs table
CREATE TABLE clubs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    logo_url TEXT,
    admin_user_id UUID REFERENCES auth.users(id) NOT NULL,
    is_public BOOLEAN DEFAULT true,
    max_members INTEGER DEFAULT 50,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Club memberships
CREATE TABLE club_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id UUID REFERENCES clubs(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member', -- 'admin', 'member'  
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(club_id, user_id)
);

-- Events table (evolution of duels)
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_user_id UUID REFERENCES auth.users(id) NOT NULL,
    club_id UUID REFERENCES clubs(id) ON DELETE SET NULL, -- NULL for public events
    title VARCHAR(200) NOT NULL,
    description TEXT,
    location_name VARCHAR(200),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    scheduled_start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    duration_minutes INTEGER NOT NULL,
    max_participants INTEGER,
    difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
    ruck_weight_kg DECIMAL(5, 2),
    status VARCHAR(20) DEFAULT 'scheduled', -- 'scheduled', 'active', 'completed', 'cancelled'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Event participants (evolution of duel participants)
CREATE TABLE event_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'registered', -- 'registered', 'joined', 'completed', 'no_show'
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(event_id, user_id)
);

-- Performance indexes for efficient queries
CREATE INDEX idx_events_club_id_scheduled ON events(club_id, scheduled_start_time);
CREATE INDEX idx_events_creator_status ON events(creator_user_id, status);
CREATE INDEX idx_club_memberships_user_status ON club_memberships(user_id, status);
CREATE INDEX idx_club_memberships_club_status ON club_memberships(club_id, status);
CREATE INDEX idx_event_participants_user ON event_participants(user_id, status);
CREATE INDEX idx_event_participants_event ON event_participants(event_id, status);

-- Row Level Security Policies

-- Clubs RLS
ALTER TABLE clubs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public clubs viewable by everyone" ON clubs
FOR SELECT USING (is_public = true OR auth.uid() IN (
    SELECT user_id FROM club_memberships 
    WHERE club_id = clubs.id AND status = 'approved'
));

CREATE POLICY "Club admins can update clubs" ON clubs
FOR UPDATE USING (admin_user_id = auth.uid());

CREATE POLICY "Anyone can create clubs" ON clubs
FOR INSERT WITH CHECK (admin_user_id = auth.uid());

-- Club memberships RLS  
ALTER TABLE club_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view club memberships" ON club_memberships
FOR SELECT USING (
    user_id = auth.uid() OR 
    club_id IN (
        SELECT club_id FROM club_memberships cm2 
        WHERE cm2.user_id = auth.uid() AND cm2.status = 'approved'
    )
);

CREATE POLICY "Users can manage their own memberships" ON club_memberships
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can leave clubs" ON club_memberships
FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Club admins can manage memberships" ON club_memberships
FOR UPDATE USING (
    club_id IN (
        SELECT id FROM clubs WHERE admin_user_id = auth.uid()
    )
);

-- Events RLS
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public events viewable by everyone" ON events
FOR SELECT USING (
    club_id IS NULL OR 
    auth.uid() IN (
        SELECT user_id FROM club_memberships 
        WHERE club_id = events.club_id AND status = 'approved'
    )
);

CREATE POLICY "Event creators can update events" ON events
FOR UPDATE USING (creator_user_id = auth.uid());

CREATE POLICY "Anyone can create events" ON events
FOR INSERT WITH CHECK (creator_user_id = auth.uid());

-- Event participants RLS
ALTER TABLE event_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Event participants can view participants" ON event_participants
FOR SELECT USING (
    user_id = auth.uid() OR
    event_id IN (
        SELECT id FROM events WHERE creator_user_id = auth.uid()
    ) OR
    event_id IN (
        SELECT event_id FROM event_participants ep2 
        WHERE ep2.user_id = auth.uid()
    )
);

CREATE POLICY "Users can join events" ON event_participants
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can leave events" ON event_participants
FOR DELETE USING (user_id = auth.uid());

-- Function to automatically add club admin as approved member
CREATE OR REPLACE FUNCTION add_club_admin_membership()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO club_memberships (club_id, user_id, role, status)
    VALUES (NEW.id, NEW.admin_user_id, 'admin', 'approved');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_add_club_admin_membership
    AFTER INSERT ON clubs
    FOR EACH ROW
    EXECUTE FUNCTION add_club_admin_membership();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_clubs_updated_at
    BEFORE UPDATE ON clubs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_events_updated_at
    BEFORE UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
