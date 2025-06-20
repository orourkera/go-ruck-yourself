# Clubs 2.0 — Functional & Technical Design

> **Status:** Draft 2025-06-20   |   **Author:** Cascade

## 1. Objective
Clubs 2.0 elevates the existing clubs feature with:

1. A rich **Club Leaderboard** showing member performance.
2. A consolidated **Events** module embedded in each club page, including the ability for club admins to create events *in-context*.

The goal is to keep users inside the club experience while providing competitive and collaborative motivation.

---

## 2. Club Leaderboard
### 2.1 Functional Requirements
* Display all approved club members.
* Show **avatar** & **username** correctly for every row.
* Sortable by:
  1. Date joined (ascending / descending)
  2. Distance (km / mi)
  3. Elevation gain (m / ft)
  4. Power Points (weight × distance × elevation)
  5. Total rucks (session count)
  6. Calories burned
* Clicking a member opens their public profile.
* Refresh button pulls latest stats.

### 2.2 Data Model Additions
`club_member_stats` *(materialized view or table updated nightly)*
| Column | Type | Notes |
|--------|------|-------|
| club_id | uuid | FK → `clubs(id)` |
| user_id | uuid | FK → `users(id)` |
| total_distance_km | numeric | Sum of ruck sessions within club timeframe |
| total_elevation_m | numeric |  "  |
| total_sessions | int |  "  |
| total_calories | int |  "  |
| power_points | numeric | Pre-calculated for fast sort |
| joined_at | timestamptz | From `club_memberships` |
| updated_at | timestamptz | materialize time |

> Alternative: compute on the fly with Supabase RPC if data size permits.

### 2.3 Backend API
`GET /api/clubs/{club_id}/leaderboard`
```jsonc
{
  "leaderboard": [
    {
      "user_id": "…",
      "stats": {
        "total_distance": 104.7,
        "total_elevation": 2430,
        "total_sessions": 28,
        "power_points": 973.2,
        "total_calories": 18500
      },
      "user": {
        "id": "…",
        "username": "Ruckette",
        "avatar_url": "https://…"
      },
      "joined_at": "2025-01-14T11:43:00Z"
    }
  ],
  "last_updated": "2025-06-20T10:00:00Z"
}
```

#### 2.3.1 Avatar / Username Reliability
* **Primary join**: `user!user_id(id, username, avatar_url)`.
* **Fallback enrichment** (same pattern already used in events / duels):
  1. Identify rows where `user` object is null.
  2. Bulk fetch missing users using admin client to bypass RLS:
  ```python
  missing = [r['user_id'] for r in rows if not r.get('user')]
  users = admin_client.table('user').select('id, username, avatar_url').in_('id', missing).execute()
  ```
  3. Inject into response before returning.
* Guarantees frontend *always* receives populated `user` field.

### 2.4 Sorting Logic
* Query param `sort_by` ( `joined|distance|elevation|powerpoints|sessions|calories` ) and `order` (`asc|desc`).
* Default: `distance` DESC.
* Supabase: `.order(<column>, desc=True)`; add computed columns to view/table for performance.

### 2.5 Frontend (Flutter)
* New widget `ClubLeaderboardWidget` mirroring `EventLeaderboardWidget` patterns.
* Read `preferMetric` & `preferCalories` from user profile for units.
* Display `--` for zero values (reuse helper functions).
* Use `SingleChildScrollView` + `DataTable` or custom list with sticky header for sort icons.

---

## 3. Club Events Integration
### 3.1 Functional Requirements
* Club detail screen gains an **Events** tab.
* Shows upcoming & past events filtered by `club_id`.
* Club admins see **“Create Event”** FAB inside this tab.
* Event creation uses existing `/api/events` POST with `club_id` pre-filled.
* After creation, list auto-refreshes and navigates to new event detail.

### 3.2 Backend
* Existing Events API already supports filtering by `club_id`.
* No new endpoint needed; just expose: `GET /api/events?club_id=eq.{id}`.
* Permissions: ensure club members can view, but only club admin can create (check `clubs.admin_user_id`).

### 3.3 Frontend
* Modify `ClubDetailScreen` → add `TabBar` with `About | Leaderboard | Events`.
* `ClubEventsTab` reuses `EventListWidget` with additional prop `clubId`.
* `FloatingActionButton` visible when `authState.user.id == club.adminUserId`.
* FAB navigates to `CreateEventScreen` with `club_id` & returns to refresh list.

---

## 4. Migration & Roll-out Plan
1. **DB**: create `club_member_stats` view/table + indexes.
2. **Backend**
   * Add leaderboard endpoint with fallback user enrichment.
   * Update `clubs.py` resource to include `events_count` & link if needed.
3. **Frontend**
   * Widgets / BLoCs for leaderboard & events tab.
   * Route adjustments for inline event creation.
4. **QA**
   * Unit tests for API sorting & user enrichment.
   * Widget tests for empty & populated leaderboards.
5. **Deploy**
   * Backend first → migrate DB & push API.
   * Frontend rollout via phased releases.

---

## 5. Open Questions
* Should non-members view the leaderboard?
* Pagination threshold? ( >100 members )
* Real-time updates via Supabase realtime or polling only?
* Power Points formula final confirmation.

---

## 6. Task Breakdown (Jira-style)
| ID | Description | Owner | Est. |
|----|-------------|-------|------|
| CLB-1 | Create `club_member_stats` materialized view | BE | 2d |
| CLB-2 | `/clubs/{id}/leaderboard` endpoint w/ sorting | BE | 1d |
| CLB-3 | Integrate fallback user enrichment util | BE | 0.5d |
| CLB-4 | Flutter `ClubLeaderboardWidget` | FE | 2d |
| CLB-5 | Add Events tab & FAB in `ClubDetailScreen` | FE | 1.5d |
| CLB-6 | Update routing & permissions checks | FE | 0.5d |
| CLB-7 | QA + unit/widget tests | QA | 1d |

---

## 7. Conclusion
Clubs 2.0 strengthens the community aspect by *bringing competition and coordination under one roof.* The design leverages existing patterns (user enrichment fallback, measurement utils, Bloc architecture) to ensure consistency and minimal tech debt.
