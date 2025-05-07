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
  - [ ] `Tick` (elapsed time updates)
  - [x] `SessionPaused` / `SessionResumed`
  - [x] `SessionCompleted` (final validation, `/complete`, HealthKit)
- [ ] Remove duplicated code now handled by Bloc.

### 2. Screen Refactor
- [x] Replace `ActiveSessionScreen` with a **Stateless** widget that:
  - [x] Provides the Bloc (with dependencies) via `BlocProvider`.
  - [x] Pushes `SessionStarted` in `initState`.
- [ ] Extract small widgets:
  - [ ] `MapWidget` (route display)
  - [ ] `SessionStatsOverlay` (distance, pace, HR …)
  - [ ] `SessionControls` (pause/resume/end buttons)
  - [ ] `ValidationBanner` (GPS/idle warnings)
- [x] Use `BlocConsumer` to react to state changes & errors.

### 3. Validation Integration
- [ ] Call `SessionValidationService.validateLocationPoint` inside Bloc.
- [ ] Auto-pause / auto-end based on `shouldPause` / `shouldEnd` flags.
- [ ] Call `validateSessionForSave` before `SessionCompleted` POST.

### 4. Watch & HealthKit
- [ ] Ensure Bloc issues `WatchService.*` commands on pause/resume/end.
- [ ] On `SessionCompleted` -> `HealthService.saveWorkout`.

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
