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
- [x] **Create Club Screen**: Form for creating new clubs with logo upload and location search
- [x] **Club Logo Upload**: Integrated with avatar service and circular display
- [x] **Location Search**: Type-ahead search with geocoding and coordinate storage
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

## **API Endpoints & Methods Reference**

### **Backend API Endpoints** (`/api/clubs/...`)
- `GET /clubs` - List clubs with filters (search, is_public, membership)
- `POST /clubs` - Create new club (requires: name, description, is_public; optional: max_members, logo_url, latitude, longitude)
- `GET /clubs/{club_id}` - Get club details with members
- `PUT /clubs/{club_id}` - Update club (name, description, is_public, max_members)
- `DELETE /clubs/{club_id}` - Delete club (admin only)
- `POST /clubs/{club_id}/join` - Request membership
- `PUT /clubs/{club_id}/members/{user_id}` - Manage membership (action: approve/reject/promote/demote, role: admin/member)
- `DELETE /clubs/{club_id}/members/{user_id}` - Remove member
- `DELETE /clubs/{club_id}/members/me` - Leave club

### **Flutter Repository Methods** (`ClubsRepository`)
- `getClubs({search?, isPublic?, membershipFilter?})` - Get filtered clubs list
- `createClub({name, description, isPublic, maxMembers?, logoUrl?, latitude?, longitude?})` - Create club
- `getClubDetails(clubId)` - Get detailed club info
- `updateClub({clubId, name?, description?, isPublic?, maxMembers?})` - Update club
- `deleteClub(clubId)` - Delete club
- `requestMembership(clubId)` - Request to join
- `manageMembership({clubId, userId, action?, role?})` - Manage member
- `removeMembership(clubId, userId)` - Remove member
- `leaveClub(clubId)` - Leave club

### **Flutter Navigation Routes**
- `/clubs` - Main clubs list screen  
- `/club_detail` - Club details screen (requires clubId parameter)
- `/create_club` - Create new club screen

### **Caching System** (`ClubsCacheService`)
- `getCachedFilteredClubs({search?, isPublic?, membershipFilter?})` - Get cached clubs
- `cacheFilteredClubs(data, {search?, isPublic?, membershipFilter?})` - Cache clubs list
- `getCachedClubDetails(clubId)` - Get cached club details
- `cacheClubDetails(clubId, data)` - Cache club details
- `invalidateCache()` - Clear all clubs cache
- `invalidateClubDetails(clubId)` - Clear specific club cache
- `clearAllCache()` - Clear entire cache

---

### Current Status Summary
- **Navigation**: ✅ **COMPLETED** - Club detail routing with parameter handling
- **Clubs Frontend Core**: ✅ **COMPLETED** - Full repository implementation with proper API client integration  
- **Clubs UI Screens**: ✅ **COMPLETED** - All screens implemented with logo upload and location search
- **Caching System**: ✅ **COMPLETED** - 15-minute cache with smart invalidation
- **Events Feature**: ✅ **Phase 1 COMPLETED** - Events tab shows duels (duels remain unchanged, future events will be separate)
- **Club Management**: ⏳ **IN PROGRESS** - Admin functions for membership approval/denial
- **Real-time Integration**: ⏳ Pending
- **Testing & Polish**: ⏳ Pending

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
    creator_user_id UUID NOT NULL REFERENCES auth.users(id),
    
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
    CONSTRAINT events_creator_fkey FOREIGN KEY (creator_user_id) REFERENCES auth.users(id),
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

-- Indexes for performance
CREATE INDEX idx_events_start_date ON events(start_date);
CREATE INDEX idx_events_location ON events(latitude, longitude);
CREATE INDEX idx_events_club ON events(hosting_club_id);
CREATE INDEX idx_event_participants_event ON event_participants(event_id);
CREATE INDEX idx_event_participants_user ON event_participants(user_id);
```

#### **API Endpoints**
```python
# Events CRUD
GET /api/events                    # List events with filters
POST /api/events                   # Create new event
GET /api/events/{event_id}         # Get event details
PUT /api/events/{event_id}         # Update event (creator only)
DELETE /api/events/{event_id}      # Delete event (creator only)

# Event Participation
POST /api/events/{event_id}/join           # Join event
DELETE /api/events/{event_id}/leave        # Leave event
GET /api/events/{event_id}/participants    # Get participant list

# Event Management (creator/admin only)
PUT /api/events/{event_id}/participants/{user_id}    # Approve/reject participant
DELETE /api/events/{event_id}/participants/{user_id} # Remove participant

# Event Media
POST /api/events/upload-banner     # Upload event banner image
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

#### **Phase 2: Rich Features**
- [ ] Banner image upload and display
- [ ] Rich text description editor
- [ ] Club integration for admins
- [ ] Approval workflow for events
- [ ] Distance-based sorting

#### **Phase 3: Advanced Features**
- [ ] Push notifications system
- [ ] Deep linking implementation  
- [ ] Share functionality
- [ ] Event management dashboard
- [ ] Analytics and insights

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

---
