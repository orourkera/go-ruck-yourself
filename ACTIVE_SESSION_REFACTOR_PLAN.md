# Active Session Screen Refactor Plan

Guiding goal: move all business logic (timers, API calls, validation, HealthKit, watch comms) into `ActiveSessionBloc`, leaving the screen as a thin UI layer.  This will shrink the screen file, centralise logic, and improve debuggability & testability.

---

## Task Checklist

### 1. Bloc Enhancements
- [ ] Extend **ActiveSessionEvent** with any missing events (e.g. `Tick`, `WatchCommandFailed`).
- [ ] Flesh out **ActiveSessionState** with full session metrics & error fields.
- [ ] Implement logic for:
  - [x] `SessionStarted`
  - [x] `LocationUpdated` (validation + batching + API)
  - [x] `HeartRateUpdated` (avg HR + API)
  - [x] `Tick` (elapsed time updates) 
  - [x] `SessionPaused` / `SessionResumed`
  - [x] `SessionCompleted` (final validation, `/complete`, HealthKit)
- [x] Remove duplicated code now handled by Bloc. 

### 2. Screen Refactor
- [x] Replace `ActiveSessionScreen` with a **Stateless** widget that:
  - [x] Provides the Bloc (with dependencies) via `BlocProvider`.
  - [x] Pushes `SessionStarted` in `initState`.
- [ ] Extract small widgets:
  - [x] `MapWidget` (route display) 
  - [x] `SessionStatsOverlay` (distance, pace, HR …) 
  - [x] `SessionControls` (pause/resume/end buttons) 
  - [x] `ValidationBanner` (GPS/idle warnings) 
- [x] Use `BlocConsumer` to react to state changes & errors.

### 3. Validation Integration
- [x] Call `SessionValidationService.validateLocationPoint` inside Bloc. 
- [x] Auto-pause / auto-end based on `shouldPause` / `shouldEnd` flags. 
- [x] Call `validateSessionForSave` before `SessionCompleted` POST. 

### 4. Watch & HealthKit
- [x] Ensure Bloc issues `WatchService.*` commands on pause/resume/end. 
- [x] On `SessionCompleted` -> `HealthService.saveWorkout`.

### 5. Error Handling & Logging
- [ ] Standardise error model (`ApiError`) inside Bloc state.
- [ ] Screen shows SnackBar/dialog on state.error.

### 6. Testing
- [ ] Unit tests for each Bloc event → expected state.
- [ ] Validation edge-cases with fake `LocationPoint`s.
- [ ] Widget tests for screen reacting to Bloc states.

### 7. Cleanup
- [ ] Delete unused fields/methods in `active_session_screen.dart`.
- [ ] Remove redundant helpers after Bloc migration.
- [ ] Update README / docs as needed.

### 8. UI Parity with Legacy `ActiveSessionScreen`
The new Bloc-driven page still lacks some visual/UX elements that existed in the Riverpod screen. Add these widgets/features so the user experience is unchanged before we delete the old file.

- [ ] **Planned Duration Countdown**
  - Circular or linear countdown showing remaining time when `plannedDuration` is set.
  - Triggers SnackBar when finished.
- [x] **Elevation Gain / Loss Tile** in stats overlay.
- [x] **Heart-Rate Tile Style** — colour‐coded zones (green / amber / red) like legacy screen.
- [x] **Calories Colour-Coding** — warning colour if outside expected range.
- [x] **Custom Map Marker Icon** (ruck pin) for current position.
- [x] **Ruck Weight Chip** displayed somewhere on the screen.
- [x] **Pause Overlay** — semi-transparent banner "Paused" when session is paused.
- [ ] **Idle/End Suggestion Dialog** when `shouldEnd` flag emitted.
- [ ] Replace basic `SessionControls` with legacy layout: large central Stop, smaller Pause/Resume.
- [x] **Map Layout** — match legacy proportions (map occupies ~50% height, stats overlay floats on top with padding).
- [x] **Unit-Aware Widgets** — distance/pace weight/calories adapt to `preferMetric` flag (km/kg vs mi/lbs).
- [ ] **Heart Rate Streaming** — subscribe to `HealthService.heartRateStream` in Bloc and render live HR tile with zone colours.
- [ ] **Custom Marker Icon** — load `assets/icons/ruck_pin.png` and use in map `CircleMarker` or `MarkerLayer`.

After these are complete the legacy `active_session_screen.dart` can be safely deleted.

---

## Milestone Flow
1. _Scaffold Bloc state & events_ → compile.
2. _Migrate LocationUpdated_ path → run on real device.
3. _Add HeartRateUpdated & Tick_ → verify stats.
4. _Wire pause/resume/end_ → ensure watch sync.
5. _Swap UI to new stateless view_ → confirm visuals.
6. _Clean up & commit_.

---

_Keep commits small & incremental; validate on-device after each milestone._
