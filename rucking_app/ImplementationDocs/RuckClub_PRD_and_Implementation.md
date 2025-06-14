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
- Individual ruck sessions 
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
```

### Performance Indexes

```sql
-- Performance indexes for efficient queries
CREATE INDEX idx_club_memberships_user_status ON club_memberships(user_id, status);
CREATE INDEX idx_club_memberships_club_status ON club_memberships(club_id, status);
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

### Phase 2: Events Feature Enhancement  
1. Implement enhanced events functionality with club integration
2. Add event filtering and improved UI
3. Club event creation with member notifications
4. Standalone events system (separate from existing duels)

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

1. **Notification Performance**: Club event notifications could create spam
2. **Real-time Scaling**: Multiple club channels require careful resource management
3. **User Adoption**: New navigation might confuse existing users initially

## Success Metrics

- **Club Adoption**: % of users who join/create clubs within 30 days
- **Club Event Participation**: Participation rates for club events
- **Notification Engagement**: Click-through rates on club event notifications
- **User Retention**: Impact on DAU/MAU after feature launch

## Implementation Progress

### Phase 1: Navigation & Structure 
- [x] **Navigation Updates**: Updated main navigation to add Events tab, moved Profile to top bar, added Clubs icon to top bar
- [x] **Events Screen**: Created Events screen showing existing duels data with informational banner
- [x] **Clubs Screen Placeholder**: Created initial placeholder Clubs screen (later replaced with functional version)
- [x] **Routing**: Added `/clubs` route registration in main app routing

### Phase 3: Clubs Integration 
#### Frontend Implementation 
- [x] **Domain Models**: Created `Club`, `ClubMember`, and `ClubDetails` data models with JSON serialization
- [x] **Repository Interface**: Created `ClubsRepository` abstract class defining all club operations
- [x] **Repository Implementation**: Created `ClubsRepositoryImpl` with full API integration for:
  - Get clubs (with search/filtering)
  - Create club
  - Get club details
  - Update club
  - Delete club
  - Request membership
  - Manage membership (approve/deny/role changes)
  - Remove membership/leave club
- [x] **Bloc Architecture**: Created complete `ClubsBloc` with events and state management:
  - `ClubsEvent`: All club-related events (LoadClubs, CreateClub, etc.)
  - `ClubsState`: Comprehensive state management (loading, loaded, error states)
  - `ClubsBloc`: Full business logic with error handling and logging
- [x] **Functional Clubs Screen**: Replaced placeholder with fully functional clubs UI featuring:
  - Search functionality
  - Filter chips (All Clubs, My Clubs, Public, Private)
  - Club cards showing membership status and details
  - Empty and error states
  - Pull-to-refresh
  - Navigation to club details and create club screens
- [x] **Service Registration**: Registered `ClubsRepository` and `ClubsBloc` in service locator

#### Backend Implementation 
- [x] **Database Schema**: Clubs and club_memberships tables with RLS policies
- [x] **REST API Endpoints**: Full CRUD operations for clubs and membership management
- [x] **Push Notifications**: Integration for club events and membership updates

#### Next Steps (Pending)
- [x] **Club Detail Screen**: Full club details with member management 
- [ ] **Create Club Screen**: Form for creating new clubs
- [ ] **Club Management**: Admin functions for membership approval/denial
- [ ] **Real-time Updates**: Supabase realtime integration for live updates
- [ ] **Push Notifications**: Test end-to-end notification flow

#### Phase 2: Events Evolution (Future)
- [ ] Implement enhanced events functionality with club integration
- [ ] Add event filtering and improved UI
- [ ] Club event creation with member notifications
- [ ] Standalone events system (separate from existing duels)

### Backend Status
**Complete** - All backend infrastructure including database schema, API endpoints, RLS policies, and push notification integration is implemented and deployed.

### Current Status Summary
- **Navigation**: ✅ **COMPLETED** - Club detail routing with parameter handling
- **Clubs Frontend Core**: ✅ **COMPLETED** - Full repository implementation with proper API client integration  
- **Clubs UI Screens**: ✅ **Main & Detail screens COMPLETED** - Create screen pending
- **Events Feature**: ✅ **Phase 1 COMPLETED** - Events tab shows duels (duels remain unchanged, future events will be separate)
- **Real-time Integration**: ⏳ Pending
- **Testing & Polish**: ⏳ Pending
