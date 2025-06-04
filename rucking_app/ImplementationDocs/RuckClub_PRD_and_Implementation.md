# Ruck Club – Product Requirements & Technical Implementation Plan

## 1. Product Requirements Document (PRD)

### 1.1 Purpose
Enable social rucking by allowing users to form **Clubs** that can schedule and perform **Club Rucks** together, compete on leader-boards, and view collective history – all tightly integrated with existing Ruck session flow.

### 1.3 Key Features
1. **Club Management**
   * Admin creates club (title, description, photo, location).
   * Invite members via email / SMS, approve/deny joins, remove members.
2. **Club Ruck Coordination**
   * **Scheduled Rucks**: Creator schedules rucks for specific time/place with automatic club notifications.
   * **RSVP System**: Members can confirm attendance; creator sees headcount before ruck starts.
   * Waiting-room lobby – members tap *Join*; creator taps *Start* to begin synchronized session for all participants.
   * Push notification sent when lobby opens and for scheduled ruck reminders.
3. **Leader-Boards**
   * Global & monthly totals plus per-member averages for distance, weight, elevation & power points.
4. **Club History** 
   * List of past Club Rucks with participant list & aggregated stats.
   * Upcoming scheduled rucks with RSVP status.
5. **Navigation Updates**
   * New **Club** tab in bottom nav.
   * Existing *Stats* panel moved inside *History* tab as sub-tab.

### 1.5 Non-Functional Requirements
* Real-time lobby latency <1 s.
* Notification delivery ≥95 % within 5 s.
* Feature behind remote config flag for staged rollout.

---

## 2. Technical Implementation Plan

### 2.1 Architecture Overview
```
Flutter UI  ─► BLoC  ─► Repository  ─► Supabase RPC / Realtime Channels / DB
                                       ▲                                │
        FCM push  ◄────────────────────┘                                │
```
* **Database**: Supabase Postgres with RLS.
* **Realtime**: Supabase Realtime Channels for lobby presence & live stats.
* **Notifications**: Firebase Cloud Messaging triggered by Supabase Edge Functions.

### 2.2 Database Schema (new tables only)
| Table | Columns | Notes |
| ----- | ------- | ----- |
| club | id (PK), title, description, photo_url, location (GEOGRAPHY), admin_id (FK → users) | |
| club_member | club_id FK, user_id FK, role (admin/member), joined_at | Composite PK (club_id,user_id) |
| club_ruck | id PK, club_id FK, creator_id FK, started_at, ended_at, status (waiting/active/complete), scheduled_at | |
| club_ruck_participant | ruck_id FK, user_id FK, join_time, leave_time, stats_json, rsvp_status (yes/no/maybe) | Aggregated per-person stats |
| scheduled_ruck | id PK, club_id FK, creator_id FK, scheduled_at, location (GEOGRAPHY), description | |

RLS rules ensure only members access their club data.

### 2.3 Backend / Edge Functions
| Endpoint / Topic | Method | Description |
| ---------------- | ------ | ----------- |
| /api/clubs | POST | Create club (admin only) |
| /api/clubs/{id}/invite | POST | Invite/add users |
| /api/clubs/{id}/members/{uid} | DELETE | Remove member |
| /api/club-rucks | POST | Create lobby (status=waiting) |
| /api/scheduled-rucks | POST | Create scheduled ruck |
| /api/scheduled-rucks/{id}/rsvp | POST | Update RSVP status |
| realtime channel `club_ruck_{id}` | WS | Presence & live totals |
| Edge Function `notify_club_ruck_start` | Trigger on club_rucks insert | Send FCM to club members |
| Edge Function `notify_scheduled_ruck_reminder` | Trigger on scheduled_rucks scheduled_at | Send FCM to club members |

### 2.4 Flutter Front-End
1. **Navigation**
   * Add `ClubTab` in `MainNavBar`.
   * Move Stats under History (`HistoryScreen` with `TabBar` [History | Stats]).
2. **Screens / Widgets**
   * `ClubListScreen` – user’s clubs & create button.
   * `CreateClubScreen` – form + image picker + location autocomplete (Mapbox geocoding).
   * `ClubDetailScreen` – members, description, leader-board, history, upcoming scheduled rucks.
   * `InviteMembersSheet` – share link or select contacts.
   * `ClubRuckLobbyScreen` – waiting room list & Start button.
   * `ScheduledRuckScreen` – schedule ruck form.
   * `RSVPScreen` – RSVP list for scheduled ruck.
   * `ActiveSessionScreen` – add aggregate view when `clubRuckId != null` & user is creator.
   * `AvailableLobbiesBottomSheet` – surfaced on Create Session if member has open lobby.
3. **State Management (BLoC)**
   * `ClubBloc` – CRUD, invites, members.
   * `ClubRuckBloc` – lobby state, realtime updates, stats aggregation.
   * `ScheduledRuckBloc` – scheduled ruck state, RSVP updates.
4. **Repositories**
   * `ClubRepository` – Supabase calls for clubs & members.
   * `ClubRuckRepository` – Supabase + realtime.
   * `ScheduledRuckRepository` – Supabase calls for scheduled rucks.
5. **Notifications**
   * Configure FCM topic per club → `club_{id}`.
   * Tap action deep-links to lobby screen or scheduled ruck screen.

### 2.5 Task Breakdown & Estimates
| # | Task | Owner | Est (hrs) |
| - | ---- | ----- | --------- |
| **Backend** |||
| B1 | DB schema migrations & RLS | BE | 8 |
| B2 | CRUD REST/RPC endpoints | BE | 10 |
| B3 | Edge Function for notifications | BE | 6 |
| B4 | Realtime channel setup & row-level triggers | BE | 8 |
| **Flutter** |||
| F1 | Navigation refactor (new Club tab, Stats move) | FE | 4 |
| F2 | Club list & create screens | FE | 12 |
| F3 | Club detail (members, leader-board, history, upcoming scheduled rucks) | FE | 16 |
| F4 | Invite workflow (email/SMS share) | FE | 8 |
| F5 | Lobby screen with realtime presence | FE | 12 |
| F6 | Scheduled ruck screen & RSVP workflow | FE | 14 |
| F7 | Available lobbies selection bottom sheet | FE | 6 |
| F8 | Active session aggregate overlay | FE | 6 |
| **State/BLoC** |||
| S1 | ClubBloc & repository | FE | 10 |
| S2 | ClubRuckBloc & repository | FE | 12 |
| S3 | ScheduledRuckBloc & repository | FE | 10 |
| **Notifications / Deep Links** |||
| N1 | FCM topic subscription management | FE | 4 |
| N2 | Deep link handling into lobby or scheduled ruck | FE | 6 |
| **QA / Testing** |||
| Q1 | Unit tests (repos, blocs) | QA | 10 |
| Q2 | Widget tests (screens) | QA | 8 |
| Q3 | Integration & e2e (2 devices synchronous ruck) | QA | 12 |
| **Dev Ops** |||
| D1 | Feature flag & staged rollout config | DevOps | 2 |
| D2 | CI pipeline updates (migrations, tests) | DevOps | 2 |
| **Total** | | ~170 hrs (~4.5 weeks with 2 devs) |

### 2.6 Risks & Mitigations
| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Realtime sync latency | Poor UX | Use Supabase presence; throttle payloads; fallback polling |
| Notification spam | User annoyance | Throttle function: only one start-notification per lobby |
| Privacy of location | GDPR | Do not expose live GPS; only aggregate/show distance etc. |

### 2.7 Rollout Plan
1. Internal QA (feature flag off)
2. Closed beta with selected clubs
3. Gradual 10 % → 50 % → 100 % rollout
4. Post-launch KPI review after 2 weeks

---

## 3. Detailed Implementation Guide

### 3.1 Detailed Database Schema

#### 3.1.1 club table
```sql
CREATE TABLE club (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    photo_url TEXT,
    location GEOGRAPHY(POINT, 4326),
    location_name VARCHAR(255),
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    member_count INTEGER DEFAULT 1,
    total_distance_km NUMERIC DEFAULT 0,
    total_elevation_m NUMERIC DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    settings JSONB DEFAULT '{}',
    CONSTRAINT club_title_check CHECK (char_length(title) >= 3)
);

CREATE INDEX idx_club_admin_id ON club(admin_id);
CREATE INDEX idx_club_location ON club USING GIST(location);
CREATE INDEX idx_club_created_at ON club(created_at DESC);
```

#### 3.1.2 club_member table
```sql
CREATE TABLE club_member (
    club_id UUID REFERENCES club(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    invite_status VARCHAR(20) DEFAULT 'accepted' CHECK (invite_status IN ('pending', 'accepted', 'rejected')),
    invited_by UUID REFERENCES auth.users(id),
    stats JSONB DEFAULT '{"total_distance": 0, "total_rucks": 0, "total_weight": 0}',
    notification_preferences JSONB DEFAULT '{"club_ruck_start": true, "scheduled_reminders": true}',
    PRIMARY KEY (club_id, user_id)
);

CREATE INDEX idx_club_member_user_id ON club_member(user_id);
CREATE INDEX idx_club_member_joined_at ON club_member(joined_at DESC);
```

#### 3.1.3 club_ruck table
```sql
CREATE TABLE club_ruck (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    club_id UUID REFERENCES club(id) ON DELETE CASCADE,
    creator_id UUID REFERENCES auth.users(id),
    scheduled_ruck_id UUID REFERENCES scheduled_ruck(id),
    status VARCHAR(20) DEFAULT 'waiting' CHECK (status IN ('waiting', 'active', 'complete', 'cancelled')),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    lobby_settings JSONB DEFAULT '{"max_participants": null, "auto_start": false}',
    aggregated_stats JSONB DEFAULT '{}',
    CONSTRAINT club_ruck_times_check CHECK (
        (status = 'waiting' AND started_at IS NULL) OR
        (status IN ('active', 'complete') AND started_at IS NOT NULL)
    )
);

CREATE INDEX idx_club_ruck_club_id ON club_ruck(club_id);
CREATE INDEX idx_club_ruck_status ON club_ruck(status);
CREATE INDEX idx_club_ruck_created_at ON club_ruck(created_at DESC);
```

#### 3.1.4 club_ruck_participant table
```sql
CREATE TABLE club_ruck_participant (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ruck_id UUID REFERENCES club_ruck(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    ruck_session_id INTEGER REFERENCES ruck_session(id),
    join_time TIMESTAMPTZ DEFAULT NOW(),
    leave_time TIMESTAMPTZ,
    rsvp_status VARCHAR(20) CHECK (rsvp_status IN ('yes', 'no', 'maybe')),
    stats_json JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    UNIQUE(ruck_id, user_id)
);

CREATE INDEX idx_club_ruck_participant_ruck_id ON club_ruck_participant(ruck_id);
CREATE INDEX idx_club_ruck_participant_user_id ON club_ruck_participant(user_id);
```

#### 3.1.5 scheduled_ruck table
```sql
CREATE TABLE scheduled_ruck (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    club_id UUID REFERENCES club(id) ON DELETE CASCADE,
    creator_id UUID REFERENCES auth.users(id),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    scheduled_at TIMESTAMPTZ NOT NULL,
    location GEOGRAPHY(POINT, 4326),
    location_name VARCHAR(255),
    recurring_pattern JSONB,
    reminder_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT scheduled_ruck_future_check CHECK (scheduled_at > NOW())
);

CREATE INDEX idx_scheduled_ruck_club_id ON scheduled_ruck(club_id);
CREATE INDEX idx_scheduled_ruck_scheduled_at ON scheduled_ruck(scheduled_at);
```

#### 3.1.6 Power Points Addition to ruck_session
```sql
-- Add power_points as a calculated column to existing ruck_session table
ALTER TABLE ruck_session 
ADD COLUMN power_points NUMERIC GENERATED ALWAYS AS 
  (ruck_weight_kg * distance_km * (elevation_gain_m / 1000.0)) STORED;

-- Add index for performance when querying by power points
CREATE INDEX idx_ruck_session_power_points ON ruck_session(power_points DESC);
```

### 3.2 Row Level Security (RLS) Policies

#### 3.2.1 club table RLS
```sql
-- Enable RLS
ALTER TABLE club ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view clubs they are members of"
    ON club FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM club_member 
            WHERE club_member.club_id = club.id 
            AND club_member.user_id = auth.uid()
            AND club_member.invite_status = 'accepted'
        )
    );

CREATE POLICY "Only admins can update their clubs"
    ON club FOR UPDATE
    USING (admin_id = auth.uid())
    WITH CHECK (admin_id = auth.uid());

CREATE POLICY "Any authenticated user can create a club"
    ON club FOR INSERT
    WITH CHECK (auth.uid() = admin_id);

CREATE POLICY "Only admins can delete their clubs"
    ON club FOR DELETE
    USING (admin_id = auth.uid());
```

#### 3.2.2 club_member table RLS
```sql
ALTER TABLE club_member ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view other members in their clubs"
    ON club_member FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM club_member cm
            WHERE cm.club_id = club_member.club_id 
            AND cm.user_id = auth.uid()
            AND cm.invite_status = 'accepted'
        )
    );

CREATE POLICY "Club admins can insert members"
    ON club_member FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM club 
            WHERE club.id = club_member.club_id 
            AND club.admin_id = auth.uid()
        )
    );

CREATE POLICY "Club admins can update members"
    ON club_member FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM club 
            WHERE club.id = club_member.club_id 
            AND club.admin_id = auth.uid()
        )
    );

CREATE POLICY "Club admins can delete members"
    ON club_member FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM club 
            WHERE club.id = club_member.club_id 
            AND club.admin_id = auth.uid()
        )
    );
```

### 3.3 Backend Implementation

#### 3.3.1 New Flask Resources

Create `/RuckTracker/api/clubs.py`:
```python
# Club management resources with endpoints:
# /api/clubs - ClubListResource (GET, POST)
# /api/clubs/<uuid:club_id> - ClubResource (GET, PUT, DELETE)
# /api/clubs/<uuid:club_id>/members - ClubMembersResource (GET, POST)
# /api/clubs/<uuid:club_id>/members/<uuid:user_id> - ClubMemberResource (DELETE)
# /api/clubs/<uuid:club_id>/invites - ClubInvitesResource (POST)
# /api/clubs/<uuid:club_id>/stats - ClubStatsResource (GET)
```

Create `/RuckTracker/api/club_rucks.py`:
```python
# Club ruck coordination resources with endpoints:
# /api/club-rucks - ClubRuckListResource (GET, POST)
# /api/club-rucks/<uuid:ruck_id> - ClubRuckResource (GET, PUT)
# /api/club-rucks/<uuid:ruck_id>/lobby - ClubRuckLobbyResource (POST, DELETE)
# /api/club-rucks/<uuid:ruck_id>/participants - ClubRuckParticipantsResource (GET)
```

Create `/RuckTracker/api/scheduled_rucks.py`:
```python
# Scheduled ruck resources with endpoints:
# /api/scheduled-rucks - ScheduledRuckListResource (GET, POST)
# /api/scheduled-rucks/<uuid:scheduled_id> - ScheduledRuckResource (GET, PUT, DELETE)
# /api/scheduled-rucks/<uuid:scheduled_id>/rsvp - ScheduledRuckRSVPResource (POST, DELETE)
```

#### 3.3.2 API Endpoint Registration in app.py
```python
# Add to app.py imports
from RuckTracker.api.clubs import (
    ClubListResource, ClubResource, ClubMembersResource, 
    ClubMemberResource, ClubInvitesResource, ClubStatsResource
)
from RuckTracker.api.club_rucks import (
    ClubRuckListResource, ClubRuckResource, 
    ClubRuckLobbyResource, ClubRuckParticipantsResource
)
from RuckTracker.api.scheduled_rucks import (
    ScheduledRuckListResource, ScheduledRuckResource, 
    ScheduledRuckRSVPResource
)

# Add resource registrations
# Club endpoints
api.add_resource(ClubListResource, '/api/clubs')
api.add_resource(ClubResource, '/api/clubs/<uuid:club_id>')
api.add_resource(ClubMembersResource, '/api/clubs/<uuid:club_id>/members')
api.add_resource(ClubMemberResource, '/api/clubs/<uuid:club_id>/members/<uuid:user_id>')
api.add_resource(ClubInvitesResource, '/api/clubs/<uuid:club_id>/invites')
api.add_resource(ClubStatsResource, '/api/clubs/<uuid:club_id>/stats')

# Club ruck endpoints
api.add_resource(ClubRuckListResource, '/api/club-rucks')
api.add_resource(ClubRuckResource, '/api/club-rucks/<uuid:ruck_id>')
api.add_resource(ClubRuckLobbyResource, '/api/club-rucks/<uuid:ruck_id>/lobby')
api.add_resource(ClubRuckParticipantsResource, '/api/club-rucks/<uuid:ruck_id>/participants')

# Scheduled ruck endpoints
api.add_resource(ScheduledRuckListResource, '/api/scheduled-rucks')
api.add_resource(ScheduledRuckResource, '/api/scheduled-rucks/<uuid:scheduled_id>')
api.add_resource(ScheduledRuckRSVPResource, '/api/scheduled-rucks/<uuid:scheduled_id>/rsvp')
```

#### 3.3.3 Supabase Edge Functions for Push Notifications

{{ ... }}

### 3.4 Flutter Frontend Structure

#### 3.4.1 Directory Structure
```
lib/features/clubs/
├── data/
│   ├── datasources/
│   │   ├── clubs_remote_datasource.dart
│   │   └── clubs_realtime_datasource.dart
│   ├── models/
│   │   ├── club_model.dart
│   │   ├── club_member_model.dart
│   │   ├── club_ruck_model.dart
│   │   └── scheduled_ruck_model.dart
│   └── repositories/
│       └── clubs_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── club.dart
│   │   ├── club_member.dart
│   │   ├── club_ruck.dart
│   │   └── scheduled_ruck.dart
│   ├── repositories/
│   │   └── clubs_repository.dart
│   └── usecases/
│       ├── create_club.dart
│       ├── join_club_ruck.dart
│       ├── schedule_ruck.dart
│       └── get_club_stats.dart
├── presentation/
│   ├── blocs/
│   │   ├── club_bloc/
│   │   ├── club_ruck_bloc/
│   │   └── scheduled_ruck_bloc/
│   ├── screens/
│   │   ├── club_list_screen.dart
│   │   ├── create_club_screen.dart
│   │   ├── club_detail_screen.dart
│   │   ├── club_ruck_lobby_screen.dart
│   │   ├── schedule_ruck_screen.dart
│   │   └── club_leaderboard_screen.dart
│   └── widgets/
│       ├── club_card.dart
│       ├── member_list_item.dart
│       ├── lobby_participant_tile.dart
│       └── ruck_stats_aggregate.dart
└── di/
    └── clubs_injection.dart
```

### 3.5 Push Notifications Implementation

#### 3.5.1 FCM Topic Structure
```
- club_{club_id} - All club notifications
- club_{club_id}_rucks - Club ruck start notifications
- club_{club_id}_scheduled - Scheduled ruck reminders
```

#### 3.5.2 Notification Payload Structure
```json
{
  "notification": {
    "title": "Club Ruck Starting!",
    "body": "Join the Iron Warriors ruck now"
  },
  "data": {
    "type": "club_ruck_start",
    "club_id": "uuid",
    "ruck_id": "uuid",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "apns": {
    "payload": {
      "aps": {
        "category": "CLUB_RUCK",
        "sound": "default"
      }
    }
  },
  "android": {
    "priority": "high",
    "notification": {
      "channel_id": "club_rucks"
    }
  }
}
```

#### 3.5.3 Platform-Specific Considerations

**iOS:**
- Request notification permissions with provisional authorization
- Handle background fetch for scheduled ruck reminders
- Configure notification categories for quick actions
- Add NSLocationWhenInUseUsageDescription for club location features

**Android:**
- Create notification channels: club_rucks, scheduled_reminders
- Handle notification trampolining for Android 12+
- Request POST_NOTIFICATIONS permission for Android 13+
- Configure ProGuard rules for FCM

### 3.6 Real-time Implementation

#### 3.6.1 Supabase Realtime Channels
```dart
// Club ruck lobby presence
final channel = supabase.channel('club_ruck_$ruckId')
  .on(
    RealtimeListenTypes.presence,
    ChannelFilter(event: 'sync'),
    (payload, [ref]) {
      // Update participant list
    },
  )
  .on(
    RealtimeListenTypes.broadcast,
    ChannelFilter(event: 'stats_update'),
    (payload, [ref]) {
      // Update aggregated stats
    },
  )
  .subscribe();
```

#### 3.6.2 Aggregate Stats Broadcasting
```dart
// Broadcast stats every 10 seconds during active ruck
Timer.periodic(Duration(seconds: 10), (timer) {
  channel.send(
    type: RealtimeListenTypes.broadcast,
    event: 'stats_update',
    payload: {
      'user_id': userId,
      'distance': currentDistance,
      'elevation': currentElevation,
      'pace': currentPace,
    },
  );
});
```

### 3.7 API Endpoints Update

Add to `/RuckTracker/app.py`:
```python
# Club endpoints
api.add_resource(ClubResource, '/api/clubs', '/api/clubs/<string:club_id>')
api.add_resource(ClubMembersResource, '/api/clubs/<string:club_id>/members')
api.add_resource(ClubInvitesResource, '/api/clubs/<string:club_id>/invites')
api.add_resource(ClubRuckResource, '/api/club-rucks', '/api/club-rucks/<string:ruck_id>')
api.add_resource(ClubRuckLobbyResource, '/api/club-rucks/<string:ruck_id>/lobby')
api.add_resource(ScheduledRuckResource, '/api/scheduled-rucks', '/api/scheduled-rucks/<string:id>')
api.add_resource(ScheduledRuckRSVPResource, '/api/scheduled-rucks/<string:id>/rsvp')
```

### 3.8 Navigation Updates

Modify `/lib/core/navigation/app.dart`:
```dart
// Add new routes
static const String clubList = '/clubs';
static const String clubDetail = '/clubs/:id';
static const String createClub = '/clubs/create';
static const String clubRuckLobby = '/clubs/:clubId/rucks/:ruckId/lobby';
static const String scheduleRuck = '/clubs/:clubId/schedule-ruck';

// Update bottom navigation
BottomNavigationBarItem(
  icon: Icon(Icons.group),
  label: 'Clubs',
),
```

### 3.9 Testing Strategy

#### 3.9.1 Unit Tests
- Club repository tests
- Club bloc tests
- Notification handler tests
- Real-time sync tests

#### 3.9.2 Integration Tests
- Multi-device club ruck synchronization
- Notification delivery across platforms
- RLS policy validation
- Performance under load (50+ participants)

### 3.10 Performance Considerations

- Implement pagination for club member lists (50 per page)
- Throttle real-time updates to max 1 per second per user
- Cache club data locally with 5-minute TTL
- Use database indexes for all foreign keys and frequently queried fields
- Implement connection pooling for Supabase real-time

### 3.11 Migration & Rollback Plan

1. Database migrations versioned in `/supabase/migrations/`
2. Feature flag: `enable_clubs` in remote config
3. Gradual rollout: 5% → 25% → 50% → 100%
4. Rollback procedure: Disable feature flag, no DB rollback needed

---

*Last updated: 2025-06-04*
