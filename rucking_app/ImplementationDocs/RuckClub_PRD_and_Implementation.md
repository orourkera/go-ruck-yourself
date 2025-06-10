# Ruck Clubs & Events - Product Requirements Document and Technical Implementation Plan

## Overview
The Ruck Clubs & Events feature introduces two core social concepts to the rucking app:
- **Clubs**: Persistent communities for ruck organization and administration
- **Events**: Individual ruck sessions that users can create, join, and optionally associate with clubs

## Core Concepts

### **Clubs**
- Persistent communities with member management
- Admin-controlled membership (invite/approve system)
- Can host club-specific events with automatic member notifications
- Accessible via dedicated top-bar icon (separate from main navigation)

### **Events** 
- Individual ruck sessions (replacing/extending current duels concept)
- Open to all users or club-specific
- Can be standalone or club-affiliated
- Club events automatically notify all club members
- Accessible via main navigation tab (replacing Profile tab)

## Navigation & UI Architecture Changes

### Top Bar (Home Screen)
**Current**: `[Notifications] [Home Title] [Profile]`
**New**: `[Notifications] [Clubs] [Home Title] [Profile]`

- **Clubs Icon**: New icon next to notifications for club management
- **Profile Icon**: Moved from main navigation to top bar

### Main Navigation
**Current**: `[Home] [Buddies] [History] [Profile]`
**New**: `[Home] [Buddies] [History] [Events]`

- **Events Tab**: Replaces Profile tab, uses calendar icon
- **Profile Access**: Now only available via top bar

## Feature Requirements

### Clubs Feature (Top Bar Access)
1. **Club Discovery & Management**
   - Browse/search available clubs
   - View club details, member count, recent activity
   - Create new clubs (with approval process)

2. **Membership Management**
   - Join club (request-based approval)
   - Leave club
   - Admin functions: approve/deny requests, remove members

3. **Club Administration** 
   - Edit club details, logo, description
   - Manage member roles and permissions
   - Club settings and privacy controls

### Events Feature (Main Nav Tab)
1. **Event Discovery**
   - List view similar to current duels interface
   - Filter by: upcoming, past, club events, public events
   - Club events display club logo prominently

2. **Event Creation**
   - Standard event details (location, time, difficulty, etc.)
   - **Club Event Toggle**: If user belongs to clubs, option to make it a club event
   - Club events automatically notify all club members

3. **Event Participation**
   - RSVP system with capacity limits
   - Real-time participant list
   - Event-specific chat/comments

## Database Schema Changes

### New Tables

```sql
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
```

### Row Level Security Policies

```sql
-- Clubs RLS
ALTER TABLE clubs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public clubs viewable by everyone" ON clubs
FOR SELECT USING (is_public = true OR auth.uid() IN (
    SELECT user_id FROM club_memberships 
    WHERE club_id = clubs.id AND status = 'approved'
));

CREATE POLICY "Club admins can update clubs" ON clubs
FOR UPDATE USING (admin_user_id = auth.uid());

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
```

## Backend API Changes

### New Club Endpoints
```
GET    /api/clubs                    # List/search clubs
POST   /api/clubs                    # Create club
GET    /api/clubs/{id}               # Get club details
PUT    /api/clubs/{id}               # Update club (admin only)
DELETE /api/clubs/{id}               # Delete club (admin only)

GET    /api/clubs/{id}/members       # List club members  
POST   /api/clubs/{id}/join          # Request to join club
PUT    /api/clubs/{id}/members/{user_id} # Approve/deny membership
DELETE /api/clubs/{id}/members/{user_id} # Remove member/leave club
```

### Enhanced Event Endpoints (Evolution of Duels)
```
GET    /api/events                   # List events (with club filtering)
POST   /api/events                   # Create event
GET    /api/events/{id}              # Get event details
PUT    /api/events/{id}              # Update event
DELETE /api/events/{id}              # Cancel event

POST   /api/events/{id}/join         # RSVP to event
DELETE /api/events/{id}/leave        # Leave event
GET    /api/events/{id}/participants # List event participants
```

### Push Notification Updates
```
POST   /api/notifications/club-event # Notify club members of new event
POST   /api/notifications/event-reminder # Event reminder notifications
```

## Frontend Implementation

### 1. Navigation Updates

#### Top Bar Component (`home_screen.dart`)
```dart
AppBar(
  leading: IconButton(/* notifications */),
  title: Text('Home'),
  actions: [
    IconButton(
      icon: Icon(Icons.group),
      onPressed: () => Navigator.pushNamed(context, '/clubs'),
    ),
    IconButton(
      icon: Icon(Icons.person),
      onPressed: () => Navigator.pushNamed(context, '/profile'),
    ),
  ],
)
```

#### Main Navigation Update (`app.dart`)
```dart
BottomNavigationBar(
  items: [
    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Buddies'),
    BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
    BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Events'), // Was Profile
  ],
)
```

### 2. New Feature Modules

#### Club Feature Structure
```
lib/features/clubs/
├── data/
│   ├── models/
│   │   ├── club_model.dart
│   │   └── club_membership_model.dart
│   ├── repositories/
│   │   └── clubs_repository_impl.dart
│   └── datasources/
│       └── clubs_remote_datasource.dart
├── domain/
│   ├── entities/
│   │   ├── club.dart
│   │   └── club_membership.dart
│   ├── repositories/
│   │   └── clubs_repository.dart
│   └── usecases/
│       ├── get_clubs.dart
│       ├── create_club.dart
│       ├── join_club.dart
│       └── manage_club_members.dart
└── presentation/
    ├── bloc/
    │   ├── clubs_bloc.dart
    │   ├── club_management_bloc.dart
    │   └── club_membership_bloc.dart
    ├── screens/
    │   ├── clubs_screen.dart
    │   ├── club_detail_screen.dart
    │   ├── create_club_screen.dart
    │   └── club_management_screen.dart
    └── widgets/
        ├── club_card.dart
        ├── club_member_list.dart
        └── club_logo_picker.dart
```

#### Events Feature Structure (Evolution of Duels)
```
lib/features/events/
├── data/
│   ├── models/
│   │   ├── event_model.dart
│   │   └── event_participant_model.dart
│   ├── repositories/
│   │   └── events_repository_impl.dart
│   └── datasources/
│       └── events_remote_datasource.dart
├── domain/
│   ├── entities/
│   │   ├── event.dart
│   │   └── event_participant.dart
│   ├── repositories/
│   │   └── events_repository.dart
│   └── usecases/
│       ├── get_events.dart
│       ├── create_event.dart
│       ├── join_event.dart
│       └── manage_event.dart
└── presentation/
    ├── bloc/
    │   ├── events_bloc.dart
    │   ├── event_creation_bloc.dart
    │   └── event_participation_bloc.dart
    ├── screens/
    │   ├── events_screen.dart
    │   ├── event_detail_screen.dart
    │   └── create_event_screen.dart
    └── widgets/
        ├── event_card.dart
        ├── event_participants_list.dart
        └── club_event_toggle.dart
```

### 3. Key UI Components

#### Event Card with Club Integration
```dart
class EventCard extends StatelessWidget {
  final Event event;
  
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (event.club != null) 
            Container(
              // Prominent club logo and name header
              child: Row(
                children: [
                  ClubLogo(club: event.club!, size: 40),
                  Text(event.club!.name, style: boldStyle),
                ],
              ),
            ),
          // Event details
          ListTile(
            title: Text(event.title),
            subtitle: Text(event.description),
            trailing: EventJoinButton(event: event),
          ),
        ],
      ),
    );
  }
}
```

#### Club Event Toggle in Creation
```dart
class ClubEventToggle extends StatelessWidget {
  final List<Club> userClubs;
  final Function(Club?) onClubSelected;
  
  Widget build(BuildContext context) {
    if (userClubs.isEmpty) return SizedBox.shrink();
    
    return Column(
      children: [
        SwitchListTile(
          title: Text('Make this a club event'),
          subtitle: Text('Notify all club members'),
          value: selectedClub != null,
          onChanged: (value) => _toggleClubEvent(value),
        ),
        if (showClubSelector)
          DropdownButton<Club>(
            items: userClubs.map((club) => 
              DropdownMenuItem(value: club, child: Text(club.name))
            ).toList(),
            onChanged: onClubSelected,
          ),
      ],
    );
  }
}
```

## Real-time Features

### Supabase Realtime Channels
- **Club Events Channel**: `club_events:{club_id}` for club-specific event notifications
- **Event Updates Channel**: `event_updates:{event_id}` for participant changes, event updates
- **Club Management Channel**: `club_management:{club_id}` for membership approvals, admin actions

### Push Notifications via FCM
- **Club Event Created**: Notify all club members when admin creates club event
- **Event Reminders**: 24h and 1h before event start time  
- **Membership Updates**: Club join approvals/denials
- **Event Participant Updates**: When someone joins/leaves event you created

## Migration Strategy

### Phase 1: Navigation & Structure
1. Update main navigation and top bar
2. Create new Events screen (initially showing existing duels data)
3. Move profile to top bar access
4. Create empty Clubs screen with "Coming Soon"

### Phase 2: Events Evolution  
1. Migrate duels data to events table structure
2. Implement enhanced events functionality
3. Add event filtering and improved UI
4. Test event creation and participation

### Phase 3: Clubs Integration
1. Implement club creation and management
2. Add club membership system
3. Integrate club events with notifications
4. Test end-to-end club event workflow

### Phase 4: Polish & Optimization
1. Real-time updates and notifications
2. Performance optimization
3. Advanced filtering and discovery
4. Analytics and monitoring

## Estimated Implementation Effort

### Backend (Flask + Supabase)
- Database schema and RLS policies: **8 hours**
- Club management APIs: **16 hours**
- Events API enhancement: **12 hours** 
- Push notifications integration: **8 hours**
- **Backend Total: ~44 hours**

### Frontend (Flutter)
- Navigation restructure: **6 hours**
- Clubs feature complete: **32 hours**
- Events feature enhancement: **24 hours**
- Real-time integration: **12 hours**
- UI polish and testing: **16 hours**
- **Frontend Total: ~90 hours**

### **Grand Total: ~134 hours** (3.5 weeks with 2 developers)

## Risk Considerations

1. **Data Migration**: Existing duels → events migration must be seamless
2. **Notification Performance**: Club event notifications could create spam
3. **Real-time Scaling**: Multiple club channels require careful resource management
4. **User Adoption**: New navigation might confuse existing users initially

## Success Metrics

- **Club Adoption**: % of users who join/create clubs within 30 days
- **Event Engagement**: Event creation rate vs. old duels creation rate
- **Club Event Participation**: Higher participation rates for club vs. public events
- **Notification Engagement**: Click-through rates on club event notifications
- **User Retention**: Impact on DAU/MAU after feature launch
