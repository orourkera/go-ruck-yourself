## Post-Build 127 Change Log (Reference)

This document summarizes major changes made after Build 127, current status, and known regressions to guide a targeted revert/re-apply plan.

### Status Snapshot

- Working
  - VO2 Max pipeline and display (baseline computations and UI flow confirmed by tests/user verification).
  - Strava integration end-to-end (title generation, export; see SessionCompleteScreen → Strava service calls).
  - Heart-rate ingestion on phone during active sessions (stream wired into UI state; HR now visible on phone).

- Broken/Unstable
  - Watch integration (session start/echo behavior and lifecycle) still not reliable.
  - Step count display (watch and phone) not consistently shown/propagated.

### Backend (Python API) Changes

- Achievements
  - Added extensive diagnostic logging to RuckTracker/api/achievements.py to trace validation and awards.
  - Backfill scripts updated to enforce session validation (duration ≥ 300s and distance ≥ 0.5km).
  - RPC coverage: Created/standardized functions for achievement stats/total distance (file: create_missing_achievement_functions.sql).

- Ruck session completion/calories
  - Added physics-based elevation component to fallback calorie estimation in RuckTracker/api/ruck.py (work = m·g·h with efficiency), keeping totals within realistic ranges when client calories are missing.

- Distance correction utilities
  - Authored audit and update SQL to recompute actual GPS distance from location_point and update distance_km, average_pace, and calories_burned proportionally. Latest approach caps calorie adjustments and/or uses mechanical ceilings to avoid runaway values.

### Mobile App (Flutter) Changes

- Heart Rate pipeline
  - Watch → Phone HR routed via WatchConnectivity command watchHeartRateUpdate only (removed EventChannel HR conflicts) in watch_service.dart.
  - HeartRateService start/stop sequencing hardened to avoid early-exit issues; phone UI now updates (fix in ActiveSessionCoordinator._onHeartRateUpdated → aggregate state).

- Watch metrics/timer
  - Fixed timer on watch by sending durationSeconds as Double in metrics payload from phone (watch_service.dart).

- Watch session start/duplication
  - Phone start: watch_service.dart now treats startSession/workoutStarted as ACKs; only startSessionFromWatch triggers watch-initiated flow. This prevents the phone from creating duplicate sessions on ACKs.
  - Coordinator/lifecycle: removed provisional-ID usage in create payloads; consistently uses backend IDs to start sessions; reduced duplicate creation risk in session_lifecycle_manager.dart.

- AI summary (completion)
  - Moved OpenAI session-summary generation from ActiveSessionCoordinator to on-page generation in SessionCompleteScreen so UI doesn’t depend on a re-emission.
  - OpenAI model uses a fast path (gpt-4o-mini), 6s timeout, 2–3 sentence output.

- Calorie method propagation
  - Included calorie_method in initial session creation and in completion payloads so DB persists the user’s configured method. Files: session_lifecycle_manager.dart, session_complete_screen.dart.

- AI Cheerleader
  - Increased tokens and length constraints (backend and frontend) to allow 2–3 sentences; prompt constraints updated.

### iOS Watch App (watchOS) Changes

- SessionManager.swift
  - Added sessionStartedFromPhone flag to prevent the watch from echoing startSessionFromWatch back to the phone after a phone-initiated start (source of DB duplicates).
  - Ensured singleton access (public static let shared) and added/cleaned WCSessionDelegate methods.
  - Fixed brace/structure issues and ensured workout start/permission requests are sequenced.

### SQL Utilities Added/Used

- Distance audit and update (ad-hoc scripts)
  - Audit query to compare recorded vs. actual GPS distance (provided yesterday).
  - Update query to set distance and pace from computed GPS distance; latest revision applies proportional calorie adjustments with caps.

- Orphaned/completion tooling
  - complete_orphaned_sessions.sql present for locking down inconsistent states.

### Known Regressions / Open Issues

- Watch integration
  - Occasional duplicate session creation was mitigated on the phone side; watch-side behavior improved, but lifecycle remains fragile.
  - HR and steps relay from watch can be inconsistent depending on reachability and handler ordering.

- Steps not displayed reliably
  - Live steps subscription wiring exists, but UI/propagation remains inconsistent; confirm HealthKit permissions and re-check state aggregation path.

### Recommended Revert/Cherry-Pick Plan (from Build 127)

1) Revert to Build 127 baseline.
2) Cherry-pick back in, in order:
   - Strava export fixes and VO2 Max work.
   - Phone-side HR pipeline/UI aggregation (no watch-side changes).
   - Timer fix to watch (durationSeconds Double) and metrics payload stabilization.
   - AI summary generation change (SessionCompleteScreen only).
   - Achievement backfill validation changes and RPCs.
3) Defer/guard behind feature flags:
   - Watch session start routing changes.
   - Distance mass-updates and calorie percent-adjust scripts.
   - Session lifecycle create/start refactors.

### File Pointers (for quick reference)

- Backend
  - RuckTracker/api/ruck.py
  - RuckTracker/api/achievements.py
  - create_missing_achievement_functions.sql

- Flutter (phone)
  - rucking_app/lib/core/services/watch_service.dart
  - rucking_app/lib/features/ruck_session/presentation/bloc/active_session_coordinator.dart
  - rucking_app/lib/features/ruck_session/presentation/bloc/managers/session_lifecycle_manager.dart
  - rucking_app/lib/features/ruck_session/presentation/screens/session_complete_screen.dart
  - rucking_app/lib/features/ai_cheerleader/services/openai_service.dart

- watchOS
  - rucking_app/ios/GRY Watch App/SessionManager.swift

---

Use this as the authoritative checklist when re-applying fixes after reverting to Build 127. Focus first on re-landing VO2 Max, Strava, and phone-side HR/timer; hold watch-lifecycle and step display changes for targeted testing.


