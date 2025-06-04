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

### 1.4 User Stories (MoSCoW)
* **Must** – As an admin I can create a club and invite members.
* **Must** – As a member I can join a waiting lobby and ruck together.
* **Must** – As a member I receive notification when a club ruck starts.
* **Must** – As a creator I can schedule rucks and see RSVPs.
* **Should** – As an admin I can remove inactive members.
* **Should** – As a member I can view my club’s leader-board monthly & lifetime.
* **Could** – As a member I can chat in the lobby.
* **Won’t (v1)** – Multi-club membership.

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
| clubs | id (PK), title, description, photo_url, location (GEOGRAPHY), admin_id (FK → users) | |
| club_members | club_id FK, user_id FK, role (admin/member), joined_at | Composite PK (club_id,user_id) |
| club_rucks | id PK, club_id FK, creator_id FK, started_at, ended_at, status (waiting/active/complete), scheduled_at | |
| club_ruck_participants | ruck_id FK, user_id FK, join_time, leave_time, stats_json, rsvp_status (yes/no/maybe) | Aggregated per-person stats |
| scheduled_rucks | id PK, club_id FK, creator_id FK, scheduled_at, location (GEOGRAPHY), description | |

RLS rules ensure only members access their club data.

### 2.3 Backend / Edge Functions
| Endpoint / Topic | Method | Description |
| ---------------- | ------ | ----------- |
| /clubs | POST | Create club (admin only) |
| /clubs/{id}/invite | POST | Invite/add users |
| /clubs/{id}/members/{uid} | DELETE | Remove member |
| /club-rucks | POST | Create lobby (status=waiting) |
| /scheduled-rucks | POST | Create scheduled ruck |
| /scheduled-rucks/{id}/rsvp | POST | Update RSVP status |
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

*Last updated: 2025-06-03*
