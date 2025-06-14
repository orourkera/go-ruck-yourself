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

-- Event comments (similar to duel comments)
CREATE TABLE event_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    comment TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Events table
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Basic Info
    name VARCHAR(255) NOT NULL,
    description TEXT,
    creator_id UUID NOT NULL REFERENCES auth.users(id),
    
    -- Club Integration
    hosting_club_id UUID REFERENCES clubs(id),
    
    -- DateTime & Location
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE,
    location_name VARCHAR(500),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    
    -- Media
    banner_image_url TEXT,
    
    -- Participation
    min_participants INTEGER DEFAULT 1,
    max_participants INTEGER,
    approval_required BOOLEAN DEFAULT false,
    
    -- Status
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'completed')),
    
    -- Indexes for performance
    CONSTRAINT events_creator_fkey FOREIGN KEY (creator_id) REFERENCES auth.users(id),
    CONSTRAINT events_club_fkey FOREIGN KEY (hosting_club_id) REFERENCES clubs(id)
);

-- Event participants
CREATE TABLE event_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(event_id, user_id)
);

-- Event participant progress (for leaderboard)
CREATE TABLE event_participant_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Ruck session data
    ruck_session_id UUID REFERENCES ruck_session(id) ON DELETE SET NULL,
    distance_km DECIMAL(8,3) DEFAULT 0,
    duration_minutes INTEGER DEFAULT 0,
    calories_burned INTEGER DEFAULT 0,
    elevation_gain_m INTEGER DEFAULT 0,
    average_pace_min_per_km DECIMAL(4,2),
    
    -- Progress tracking
    status VARCHAR(50) DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'completed')),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(event_id, user_id)
);

-- Existing ruck_session table enhancement for event association
ALTER TABLE ruck_session 
ADD COLUMN event_id UUID REFERENCES events(id) ON DELETE SET NULL;

-- Ruck session table
CREATE TABLE ruck_session (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    distance_km DECIMAL(8,3) DEFAULT 0,
    duration_minutes INTEGER DEFAULT 0,
    calories_burned INTEGER DEFAULT 0,
    elevation_gain_m INTEGER DEFAULT 0,
    average_pace_min_per_km DECIMAL(4,2),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, started_at)
);

### Performance Indexes

```sql
-- Performance indexes for efficient queries
CREATE INDEX idx_club_memberships_user_status ON club_memberships(user_id, status);
CREATE INDEX idx_club_memberships_club_status ON club_memberships(club_id, status);
CREATE INDEX idx_event_comments_event ON event_comments(event_id);
CREATE INDEX idx_event_comments_user ON event_comments(user_id);
CREATE INDEX idx_event_participants_event ON event_participants(event_id);
CREATE INDEX idx_event_participants_user ON event_participants(user_id);
CREATE INDEX idx_event_participant_progress_event ON event_participant_progress(event_id);
CREATE INDEX idx_event_participant_progress_user ON event_participant_progress(user_id);
CREATE INDEX idx_events_start_date ON events(start_date);
CREATE INDEX idx_events_location ON events(latitude, longitude);
CREATE INDEX idx_events_club ON events(hosting_club_id);
CREATE INDEX idx_ruck_session_event ON ruck_session(event_id);
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

-- Event comments RLS
ALTER TABLE event_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Event participants can view comments" ON event_comments
FOR SELECT USING (
    auth.uid() IN (
        SELECT user_id FROM event_participants WHERE event_id = event_comments.event_id
    ) OR
    auth.uid() IN (
        SELECT creator_id FROM events WHERE id = event_comments.event_id
    )
);

CREATE POLICY "Event participants can create comments" ON event_comments
FOR INSERT WITH CHECK (
    user_id = auth.uid() AND
    auth.uid() IN (
        SELECT user_id FROM event_participants WHERE event_id = event_comments.event_id
    )
);

CREATE POLICY "Users can update own comments" ON event_comments
FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete own comments" ON event_comments
FOR DELETE USING (user_id = auth.uid());
```

### Additional Row Level Security (Events & Participants)

```sql
-- Events RLS
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public events or club members can select events" ON events
FOR SELECT USING (
    hosting_club_id IS NULL OR
    auth.uid() IN (
        SELECT user_id FROM club_memberships
        WHERE club_id = events.hosting_club_id AND status = 'approved'
    )
);

CREATE POLICY "Event creators or club admins can update events" ON events
FOR UPDATE USING (
    creator_id = auth.uid() OR
    (hosting_club_id IS NOT NULL AND hosting_club_id IN (
        SELECT club_id FROM club_memberships
        WHERE user_id = auth.uid() AND role = 'admin'
    ))
);

-- Event participants RLS
ALTER TABLE event_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can manage own participant rows" ON event_participants
FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Event creators & club admins can view participants" ON event_participants
FOR SELECT USING (
    auth.uid() IN (
        SELECT creator_id FROM events WHERE events.id = event_participants.event_id
    ) OR
    auth.uid() IN (
        SELECT user_id FROM club_memberships
        JOIN events ON events.hosting_club_id = club_memberships.club_id
        WHERE events.id = event_participants.event_id AND club_memberships.role = 'admin'
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
GET    /api/events/{id}/comments     # Get event comments
POST   /api/events/{id}/comments     # Add event comment
PUT    /api/events/{id}/comments/{comment_id}   # Edit comment
DELETE /api/events/{id}/comments/{comment_id}   # Delete comment
GET    /api/events/{id}/progress     # Get event leaderboard/progress
POST   /api/events/{id}/start-ruck   # Start ruck session for event
PUT    /api/events/{id}/progress     # Update participant progress
POST   /api/sessions                 # Create session (with optional event_id)
PUT    /api/sessions/{id}            # Update session (maintains event association)
```

### Push Notification Updates

```
POST   /api/notifications/club-event        # Notify club members of new event
POST   /api/notifications/event-reminder   # Event reminder notifications
```

#### Implementation Details

- **Club Event Notifications** – Integrated into existing backend notification system:
  - In `POST /api/events` endpoint, after successful event creation with `hosting_club_id`:
  - Fetch all approved club members from `club_memberships` table
  - Use existing `create_club_event_notification()` helper to create in-app notifications
  - Use existing `send_club_event_notification()` method in `push_notification_service.py` for push notifications
  - Leverages current notification infrastructure and FCM token management

- **Event Reminders** – Use existing scheduler pattern (similar to achievements):
  - Scheduled job checks for events starting in 24h or 1h
  - Creates notifications for all `event_participants` with `status = 'joined'`
  - Uses existing notification creation and push notification flow
  - Add `eventReminder` to existing notification types

#### New Notification Types to Add

```python
# In notification_types.dart
static const String clubEvent = 'clubEvent';
static const String eventReminder = 'eventReminder';

# In push_notification_service.py
def send_club_event_notification(club_name, event_title, recipient_user_ids):
    # Implementation using existing FCM infrastructure

def send_event_reminder_notification(event_title, recipient_user_ids):
    # Implementation using existing FCM infrastructure
```

### Caching Strategy

Frontend (Flutter):
- `EventsRepository` caches first page per filter key in memory + Hive for **3 min**.
- Individual event details cached **10 min** keyed by `eventId`.
- Pagination page size 20, subsequent pages cached **60 s**.

Backend (Supabase):
- `/api/events` supports `If-Modified-Since` and returns **304** when unchanged.
- PostgREST sets `Cache-Control: public, max-age=60` on list endpoints.

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
        ├── club_logo_picker.dart
        ├── event_leaderboard.dart
        └── event_action_buttons.dart
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
        ├── event_comments_section.dart
        ├── event_leaderboard.dart
        ├── event_action_buttons.dart
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
- [x] **Create Club Screen**: Form for creating new clubs with logo upload and location search
- [x] **Club Logo Upload**: Integrated with avatar service and circular display
- [x] **Location Search**: Same geocoding service as events
- [x] **Clubs Caching**: 15-minute cache system for improved performance
- [x] **UI/UX Improvements**: 
  - Removed redundant plus button from clubs header
  - Made club description required (20-500 characters)
  - Fixed navigation routes and consistency
  - Increased notification bell icon size
- [x] **API Authentication**: Unified to use `@auth_required` decorator consistently
- [x] **Input Validation**: Robust frontend and backend validation for all club fields
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

---

## **🎯 Events System - Comprehensive Implementation**

### **Overview**

Transform the placeholder Events tab into a full-featured event management platform with club integration, location-based discovery, and rich user interactions.

### **Core Features**

#### **Event Discovery & Filtering**

- **📍 Location-based sorting** - Sort events by distance from user's location
- **📅 Date sorting** - Sort by start date (upcoming, recent, etc.)
- **🏷️ Sticky filters:**
  - "My Club Events" - Events hosted by clubs user belongs to
  - "My Joined Events" - Events user has joined/registered for
  - Custom location radius filter
  - Date range filter

#### **Event Creation & Management**

- **📝 Event Details:**
  - Event name and description (rich text editor for formatting/prizes)
  - Start date and time (native date/time picker)
  - Geocoded location with address search (like clubs)
  - Duration or end time
  - Banner image upload (medium-sized, optimized for card display)
  
- **👥 Participation Controls:**
  - Minimum participant count (optional)
  - Maximum participant count (optional)
  - Approval required vs. open join
  - Participant list management

- **🏢 Club Integration:**
  - Club admins can host events on behalf of their club
  - Club logo displayed on event cards when club-hosted
  - Club member notifications for club events

#### **Event Cards & UI Design**

- **Card Layout** (similar to ruck buddies cards):
  - **Top Left:** Club logo (if club-hosted) or generic event icon
  - **Banner Area:** Event banner image (where map/photos typically are)
  - **Details Section:** Event name, date/time, location, participant count
  - **Action Buttons:** Join/Leave, Share, More options

#### **Event Details Page**

- **Complete event information** with rich text description
- **Interactive map** showing event location
- **Participant list** with avatars and usernames
- **Join/Leave functionality** with approval workflow if required
- **Share button** with deep link generation
- **Event updates** and announcements section

### **Technical Implementation**

#### **Database Schema**

```sql
-- Events table
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Basic Info
    name VARCHAR(255) NOT NULL,
    description TEXT,
    creator_id UUID NOT NULL REFERENCES auth.users(id),
    
    -- Club Integration
    hosting_club_id UUID REFERENCES clubs(id),
    
    -- DateTime & Location
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE,
    location_name VARCHAR(500),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    
    -- Media
    banner_image_url TEXT,
    
    -- Participation
    min_participants INTEGER DEFAULT 1,
    max_participants INTEGER,
    approval_required BOOLEAN DEFAULT false,
    
    -- Status
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'completed')),
    
    -- Indexes for performance
    CONSTRAINT events_creator_fkey FOREIGN KEY (creator_id) REFERENCES auth.users(id),
    CONSTRAINT events_club_fkey FOREIGN KEY (hosting_club_id) REFERENCES clubs(id)
);

-- Event participants
CREATE TABLE event_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(event_id, user_id)
);

-- Event participant progress (for leaderboard)
CREATE TABLE event_participant_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Ruck session data
    ruck_session_id UUID REFERENCES ruck_session(id) ON DELETE SET NULL,
    distance_km DECIMAL(8,3) DEFAULT 0,
    duration_minutes INTEGER DEFAULT 0,
    calories_burned INTEGER DEFAULT 0,
    elevation_gain_m INTEGER DEFAULT 0,
    average_pace_min_per_km DECIMAL(4,2),
    
    -- Progress tracking
    status VARCHAR(50) DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'completed')),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(event_id, user_id)
);

-- Event comments
CREATE TABLE event_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    comment TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Indexes for performance
    CONSTRAINT event_comments_event_fkey FOREIGN KEY (event_id) REFERENCES events(id),
    CONSTRAINT event_comments_user_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
```

#### **API Endpoints**

```python
# Events CRUD
GET /api/events                    # List events with filters
POST /api/events                   # Create new event
GET /api/events/{event_id}         # Get event details
PUT /api/events/{event_id}         # Update event
DELETE /api/events/{event_id}      # Cancel event

# Event Participation
POST /api/events/{event_id}/join           # Join event
DELETE /api/events/{event_id}/leave        # Leave event
GET /api/events/{event_id}/participants    # Get participant list
GET /api/events/{event_id}/comments     # Get event comments
POST /api/events/{event_id}/comments     # Add event comment
PUT /api/events/{event_id}/comments/{comment_id}   # Edit comment
DELETE /api/events/{event_id}/comments/{comment_id}   # Delete comment
GET /api/events/{event_id}/progress     # Get event leaderboard/progress
POST /api/events/{event_id}/start-ruck   # Start ruck session for event
PUT /api/events/{event_id}/progress     # Update participant progress
POST /api/sessions                 # Create session (with optional event_id)
PUT /api/sessions/{id}            # Update session (maintains event association)
```

#### **Flutter Implementation**

**Repository Methods:**

```dart
// EventsRepository
Future<List<Event>> getEvents({
  double? latitude,
  double? longitude,
  int? radiusKm,
  DateTime? startDate,
  DateTime? endDate,
  String? clubId,
  bool? joinedOnly,
});

Future<Event> createEvent({
  required String name,
  required String description,
  required DateTime startDate,
  DateTime? endDate,
  required String locationName,
  required double latitude,
  required double longitude,
  String? bannerImageUrl,
  String? hostingClubId,
  int? minParticipants,
  int? maxParticipants,
  bool approvalRequired = false,
});

Future<EventDetails> getEventDetails(String eventId);
Future<void> joinEvent(String eventId);
Future<void> leaveEvent(String eventId);
Future<String> uploadEventBanner(File imageFile);
```

**Navigation Routes:**

```dart
/events                    # Main events list
/events/{eventId}         # Event details
/events/create            # Create new event
/events/{eventId}/edit    # Edit event (creator only)
```

### **User Experience Features**

#### **Notifications**

- **Join Requests:** Notify event creator when someone requests to join
- **Approval Status:** Notify user when join request is approved/rejected
- **Event Reminders:** Day-before reminder for joined events
- **Club Events:** Notify club members when club hosts new events
- **Event Updates:** Notify participants of event changes

#### **Deep Linking & Sharing**

- **Deep Link Format:** `getrucky://events/{eventId}`
- **Share Integration:** Native share sheet with event details
- **Social Preview:** Rich preview with banner image and event details
- **QR Code Generation:** For easy offline sharing

#### **Location Integration**

- **Distance Calculation:** Real-time distance from user's location
- **Map Integration:** Interactive maps on event details
- **Navigation:** Direct integration with Maps app for directions
- **Location Search:** Same geocoding service as clubs

### **Implementation Phases**

#### **Phase 1: Core Events** 

- [ ] Database schema and migrations
- [ ] Basic CRUD API endpoints
- [ ] Event list screen with filtering
- [ ] Event creation screen
- [ ] Event details screen
- [ ] Basic join/leave functionality
- [ ] **Withdraw from event** functionality on event details page
- [ ] **Session-to-Event association** via event_id in ruck_session table

#### **Phase 2: Rich Features**

- [ ] Banner image upload and display
- [ ] Rich text description editor
- [ ] Club integration for admins
- [ ] Approval workflow for events
- [ ] Distance-based sorting
- [ ] **Event comments system** (similar to duel comments)
- [ ] **Event leaderboard** showing participant progress
- [ ] **Start ruck session** from event details page
- [ ] **Event participant progress tracking**

#### **Phase 3: Advanced Features**

- [ ] Push notifications system
- [ ] Deep linking implementation  
- [ ] Share functionality
- [ ] Event management dashboard
- [ ] Analytics and insights
- [ ] **Comment notifications** (notify participants when someone comments)

#### **Phase 4: Polish & Optimization**

- [ ] Performance optimization
- [ ] Advanced filtering options
- [ ] Event templates
- [ ] Recurring events
- [ ] Integration testing

### **Success Metrics**

- Event creation rate
- Event participation rate  
- User engagement with events
- Club-hosted event adoption
- Notification engagement rates

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
- [x] **Create Club Screen**: Form for creating new clubs with logo upload and location search
- [x] **Club Logo Upload**: Integrated with avatar service and circular display
- [x] **Location Search**: Same geocoding service as events
- [x] **Clubs Caching**: 15-minute cache system for improved performance
- [x] **UI/UX Improvements**: 
  - Removed redundant plus button from clubs header
  - Made club description required (20-500 characters)
  - Fixed navigation routes and consistency
  - Increased notification bell icon size
- [x] **API Authentication**: Unified to use `@auth_required` decorator consistently
- [x] **Input Validation**: Robust frontend and backend validation for all club fields
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

---

### **Session-to-Event Association Implementation**

#### **Database Schema**

```sql
-- Add event_id to existing ruck_session table
ALTER TABLE ruck_session 
ADD COLUMN event_id UUID REFERENCES events(id) ON DELETE SET NULL;

-- Add index for efficient queries
CREATE INDEX idx_ruck_session_event ON ruck_session(event_id);
```

#### **User Flow: Start Ruck from Event**

1. **User Navigation**: Event details page → "Start Ruck" button
2. **Session Creation**: Navigate to active session screen with event context:
   ```dart
   Navigator.pushNamed(context, '/active-session', 
     arguments: {'eventId': event.id});
   ```
3. **Session Association**: Session created with `event_id` field populated
4. **Multi-Purpose Sessions**: Session counts towards:
   - ✅ **Event progress** (leaderboard, participant tracking)
   - ✅ **Active duel** (if user has one - all ruck sessions count towards duels)

#### **Backend Logic**

```python
# When saving ruck session
def save_ruck_session(session_data):
    # Save session with optional event_id
    session = create_ruck_session(session_data)
    
    # If associated with event, update event progress
    if session.event_id:
        update_event_participant_progress(session.event_id, session.user_id, session)
    
    # If user has active duel, update duel progress (existing logic)
    if user_has_active_duel(session.user_id):
        update_duel_progress(session.user_id, session)
    
    return session
```

#### **Key Benefits**

- **Single Session, Multiple Purposes**: One ruck session can contribute to both events and duels
- **Minimal Code Changes**: Leverages existing session infrastructure  
- **Clean Data Model**: Simple foreign key relationship
- **Backward Compatible**: Existing sessions unaffected (event_id is nullable)

```
#### **2.1 Data Models & Entities**
- [x] **Event Models**
  - [x] Create `Event` entity class
  - [x] Create `EventModel` data class with JSON serialization
  - [x] Create `EventDetails` with participants and progress
  - [x] Create `EventParticipant` and `EventParticipantProgress` models

- [x] **Comment Models**
  - [x] Create `EventComment` entity class
  - [x] Create `EventCommentModel` with JSON serialization

#### **2.2 Repository Layer**
- [x] **Events Repository Interface**
  - [x] Define `EventsRepository` abstract class
  - [x] Add all CRUD method signatures
  - [x] Add participation and progress methods
  - [x] Add comment management methods

- [x] **Events Repository Implementation**
  - [x] Create `EventsRepositoryImpl`
  - [x] Implement all API calls with error handling
  - [x] Add caching strategy (10-min cache for events, comments, leaderboards)
  - [x] Add offline support via cache service

#### **2.3 State Management (BLoC)**
- [x] **Events BLoC**
  - [x] Create `EventsEvent` classes (Load, Create, Join, Leave, etc.)
  - [x] Create `EventsState` classes (Loading, Loaded, Error)
  - [x] Create `EventsBloc` with business logic
  - [x] Add error handling and logging

- [x] **Event Comments BLoC**
  - [x] Create `EventCommentsBloc` (similar to duel comments)
  - [x] Add comment CRUD operations
  - [x] Add real-time comment updates

- [x] **Event Progress BLoC**
  - [x] Create `EventProgressBloc` for leaderboard
  - [x] Add progress tracking and updates
  - [x] Add real-time leaderboard updates

#### **2.4 UI Screens**
- [x] **Events List Screen**
  - [x] Create `EventsScreen` with ruck buddies design pattern
  - [x] Add filter chips (All, Upcoming, My Events, Club Events, Completed)
  - [x] Add pull-to-refresh functionality
  - [x] Add empty and error states
  - [x] Add loading skeletons

- [x] **Event Details Screen**
  - [x] Create `EventDetailScreen`
  - [x] Add event info section
  - [x] Add participants list
  - [x] Add leaderboard section
  - [x] Add comments section
  - [x] Add action buttons (Join/Leave/Start Ruck)

- [x] **Create Event Screen**
  - [x] Create `CreateEventScreen`
  - [x] Add form validation
  - [x] Add club event toggle (for club members)
  - [x] Add location search
  - [x] Add banner image upload

#### **2.5 UI Widgets**
- [x] **Event Card**
  - [x] Create `EventCard` widget
  - [x] Add club logo display (for club events)
  - [x] Add participation status
  - [x] Add tap navigation to details

- [x] **Event Filter Chips**
  - [x] Create `EventFilterChips` widget
  - [x] Add filter options and state management
  - [x] Follow ruck buddies design pattern

- [x] **Event Leaderboard**
  - [x] Create `EventLeaderboard` widget
  - [x] Show participant progress (distance, time, status)
  - [x] Add sorting options
  - [x] Add user highlighting

- [x] **Event Comments Section**
  - [x] Create `EventCommentsSection` widget
  - [x] Reuse comment widgets from duels
  - [x] Add comment input field
  - [x] Add real-time updates

- [x] **Event Action Buttons**
  - [x] Create `EventActionButtons` widget
  - [x] Join/Leave event buttons
  - [x] Start Ruck button
  - [x] Withdraw from event button
