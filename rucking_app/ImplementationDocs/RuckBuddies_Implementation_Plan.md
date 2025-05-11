# Ruck Buddies - Implementation Plan

## 1. Overview & Goal

The "Ruck Buddies" feature aims to introduce a social dimension to the Rucking App, allowing users to discover and view rucks completed by other users. This will foster a sense of community and provide inspiration and motivation. Initially, users will be able to browse rucks based on various performance and proximity metrics.

## 2. Frontend Implementation

### 2.1. Main Menu Integration
- Add a new item to the main navigation menu: "Ruck Buddies".
- Tapping this item will navigate the user to the Ruck Buddies screen.

### 2.2. Ruck Buddies Screen (`ruck_buddies_screen.dart`)

#### 2.2.1. Page Structure & Layout
- The overall layout will be similar to the existing "Recent Sessions" widget, displaying a list/feed of ruck cards.
- Each ruck card will represent a session from another user.

#### 2.2.2. Filter Chips
- Display a row of filter chips at the top of the screen:
    - "Closest" (Default selection on page load)
    - "Most Calories"
    - "Furthest" (Distance)
    - "Longest" (Duration)
    - "Most Elevation"
- Tapping a chip will re-fetch and re-sort the list of rucks according to the selected filter.

#### 2.2.3. Ruck Card Display
- Each ruck card should display key information, similar to the current session cards:
    - User identifier (e.g., Username or Avatar - consider privacy)
    - Ruck date/time
    - Distance
    - Duration
    - Calories Burned
    - Average Pace
    - Elevation Gain
- **Map Snippet**: Include a small map snapshot for the ruck.
    - **Ruck Weight Chip**: Overlay the ruck weight (e.g., "15 kg") on the top right of the map snippet, similar to how it's displayed on the active session screen's map.

#### 2.2.4. Data Fetching & State Management
- A new BLoC/Cubit (`RuckBuddiesBloc`) will manage the state of the Ruck Buddies screen.
- States will include: `RuckBuddiesInitial`, `RuckBuddiesLoading`, `RuckBuddiesLoaded`, `RuckBuddiesError`.
- The BLoC will fetch data from the backend based on the selected filter.

## 3. Backend Implementation

### 3.1. New API Endpoint (`/api/rucks/community` or `/api/ruckbuddies`)
- Create a new GET endpoint to serve rucks from other users.
- This endpoint must not return rucks belonging to the currently authenticated user.
- **Pagination** should be implemented from the start.

### 3.2. Query Parameters for Filtering & Sorting
- The endpoint should accept query parameters to handle filtering and sorting:
    - `sort_by`: (e.g., `calories_desc`, `distance_desc`, `duration_desc`, `elevation_gain_desc`, `proximity_asc`)
    - `latitude` (required for `proximity_asc` sorting)
    - `longitude` (required for `proximity_asc` sorting)
    - `page`, `per_page` for pagination.

### 3.3. Data Returned
- For each ruck, the API should return:
    - All necessary session details (distance, duration, calories, `completed_at`, `started_at`, `ruck_weight_kg`, route start point for map, etc.).
    - Anonymized or public user information (e.g., username, user ID). **Privacy is paramount.**
    - Ensure only publicly shared rucks are returned (see Data Model Considerations).

### 3.4. Proximity Calculation (for "Closest" filter)
- If sorting by proximity, the backend will need to perform a geospatial query.
- This requires that ruck sessions have a starting location (latitude/longitude) stored.
- The user's current location (or a chosen reference point) will need to be sent to the backend to calculate distances.

## 4. Data Model Considerations

### 4.1. `ruck_session` Table
- Ensure `ruck_session` stores starting latitude and longitude if "Closest" rucks are to be based on the start of the ruck.
- Add a new boolean column: `is_public` (default `false`, not nullable). This flag indicates if an individual ruck session is intended to be shared. Its default value during session creation will be influenced by the user's global `allow_ruck_sharing` preference but can be overridden by the user for that specific session.

### 4.2. `users` Table
- Add a user-level preference: `allow_ruck_sharing` (boolean, default `false`, not nullable). This acts as a master switch. If `false`, none of the user's rucks will be shared, regardless of individual `ruck_session.is_public` settings.

## 5. User Privacy & Sharing Logic

- **Two-Tiered Opt-In:**
    1.  **Global Sharing Preference (`users.allow_ruck_sharing`):** Users must first enable sharing globally in their profile/settings. This defaults to `false`.
    2.  **Per-Ruck Sharing (`ruck_session.is_public`):** When saving a new ruck, if global sharing is enabled, the option to share that specific ruck (i.e., set `is_public` to `true`) will default to `true`. Users can override this for each individual ruck (e.g., make a specific ruck private even if global sharing is on, or public if global is on and it defaulted to public).
- **Backend Filtering:** The API endpoint for Ruck Buddies will only return sessions where `ruck_session.is_public IS TRUE` AND the corresponding `users.allow_ruck_sharing IS TRUE` for the owner of the ruck.
- Users must explicitly opt-in to share their rucks. This could be a per-ruck setting or a global profile setting.
- Clearly communicate what information will be shared.

## 6. UI/UX Considerations
- Loading states for fetching rucks.
- Empty state if no rucks are found or if the user hasn't enabled sharing/no one else has.
- Clear indication of the active filter.
- How to handle users with no location data if "Closest" is selected.

## 7. Future Enhancements
- Ability to "Kudos" or react to rucks.
- Following other users.
- Leaderboards (weekly/monthly based on shared rucks).
- More advanced filtering (e.g., by tags, by specific ruck weight ranges).
- User profiles for Ruck Buddies.

## 8. Detailed Task Checklist

### I. Data Model Setup (Supabase)
- [ ] Add `is_public` (BOOLEAN, NOT NULL, DEFAULT FALSE) column to `ruck_session` table.
- [ ] Add `allow_ruck_sharing` (BOOLEAN, NOT NULL, DEFAULT FALSE) column to `users` table.
- [ ] Verify `ruck_session` table includes columns for `start_latitude` and `start_longitude` (or equivalent for proximity calculations).

### II. Backend API Development (`/api/rucks/community`)
- **A. Endpoint Scaffolding & Basic Logic**
    - [ ] Create new Python file for community rucks resource (e.g., `community_rucks.py`).
    - [ ] Define `CommunityRucksResource` class with a `GET` method.
    - [ ] Register the new route (e.g., `/api/rucks/community`) in the Flask application.
    - [ ] Implement basic request argument parsing for pagination (`page`, `per_page`) and sorting (`sort_by`).
    - [ ] Implement parsing for `latitude` and `longitude` when `sort_by=proximity_asc`.
- **B. Core Data Fetching & Filtering**
    - [ ] Construct Supabase query to select from `ruck_session`.
    - [ ] Join with `users` table to access `allow_ruck_sharing`.
    - [ ] Filter: `ruck_session.is_public IS TRUE`.
    - [ ] Filter: `users.allow_ruck_sharing IS TRUE`.
    - [ ] Filter: `ruck_session.user_id != <current_authenticated_user_id>`.
    - [ ] Select all necessary ruck data fields for display.
    - [ ] Select user information to display (e.g., user ID, username - consider anonymization strategy).
- **C. Sorting Logic**
    - [ ] Implement sorting for `calories_desc`.
    - [ ] Implement sorting for `distance_desc`.
    - [ ] Implement sorting for `duration_desc`.
    - [ ] Implement sorting for `elevation_gain_desc`.
    - [ ] Implement sorting for `proximity_asc` (requires geospatial query capabilities if not using a simpler distance calculation).
- **D. Pagination Logic**
    - [ ] Apply `limit` and `offset` to the Supabase query based on `page` and `per_page`.
    - [ ] Consider returning pagination metadata (total items, total pages) in the API response.
- **E. Ruck Session Creation/Update Logic (for sharing)**
    - [ ] In the existing ruck creation/update API endpoint:
        - [ ] When a new ruck is saved, the default for `ruck_session.is_public` should be based on the user's `users.allow_ruck_sharing` preference.
        - [ ] Allow the user to explicitly set/override `ruck_session.is_public` for the specific session being saved.

### III. Frontend Implementation (Flutter - `ruck_buddies_screen.dart`)
- **A. Navigation & Screen Setup**
    - [ ] Add "Ruck Buddies" item to the main navigation menu/drawer.
    - [ ] Create `ruck_buddies_screen.dart` file with basic page structure.
- **B. State Management (`RuckBuddiesBloc` / Cubit)**
    - [ ] Create `RuckBuddiesBloc` (or Cubit) and associated states (`Initial`, `Loading`, `Loaded`, `Error`).
    - [ ] Define events/methods to fetch data based on active filters and pagination.
    - [ ] Implement API call logic within the BLoC to the `/api/rucks/community` endpoint.
- **C. UI - Filter Chips**
    - [ ] Implement a row of filter chips: "Closest", "Most Calories", "Furthest", "Longest", "Most Elevation".
    - [ ] Ensure default filter is "Closest".
    - [ ] Tapping a chip triggers data refresh via the BLoC with the new `sort_by` parameter.
    - [ ] Visually indicate the currently active filter chip.
- **D. UI - Ruck Card Display**
    - [ ] Create a `RuckBuddyCard` widget (or similar) to display individual ruck details.
    - [ ] Display: User identifier (anonymized as per privacy decisions).
    - [ ] Display: Ruck date/time, distance, duration, calories, avg pace, elevation gain.
    - [ ] Display: Small map snapshot (static map image or simplified polyline).
    - [ ] Display: Ruck weight chip overlaid on the map snippet.
- **E. UI - List & States**
    - [ ] Implement a scrollable list (e.g., `ListView.builder`) to show `RuckBuddyCard`s.
    - [ ] Integrate with `RuckBuddiesBloc` to update the list based on state.
    - [ ] Implement loading indicators (e.g., shimmer effect, progress indicator).
    - [ ] Implement empty state display (e.g., "No rucks found", "Be the first to share!").
    - [ ] Implement error state display (e.g., "Could not load rucks").
    - [ ] Implement pull-to-refresh functionality.
    - [ ] Implement infinite scrolling/pagination for the list.
- **F. User Profile/Settings (Sharing Toggle)**
    - [ ] Add a toggle/switch in the user's profile or app settings screen.
    - [ ] This toggle controls the `users.allow_ruck_sharing` preference.
    - [ ] Persist changes to this preference to the backend.

### IV. User Privacy & Sharing Communication
- [ ] Design and implement clear UI text explaining what data will be shared when enabling global sharing and per-ruck sharing.
- [ ] Finalize anonymization strategy for user identifiers (e.g., show user ID, generated alias, or nothing if too sensitive).
- [ ] Finalize details for map snippet display (e.g., generalized location, no start/end markers by default).

### V. Testing
- [ ] Backend: Unit tests for filtering, sorting, and pagination logic.
- [ ] Backend: Integration tests for the API endpoint.
- [ ] Frontend: Widget tests for `RuckBuddyCard` and filter chips.
- [ ] Frontend: BLoC tests for state management logic.
- [ ] Frontend: Integration tests for screen interactions and API calls.
- [ ] End-to-end testing of the complete feature flow.
- [ ] Test proximity filter with different user locations and ruck start points.
- [ ] Test privacy settings: user disables global sharing, user makes specific ruck private.

---
This plan provides a foundational outline. Details will be refined as development progresses.
