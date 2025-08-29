# Watch‑Initiated Start: Minimal, Dumb‑Relay Design

This document defines a safe, minimal design to let the Apple Watch start a ruck while keeping the iPhone as the single source of truth for session lifecycle and storage. The watch acts as a dumb remote for lifecycle commands and as the primary live source for heart rate and steps.

## Guiding Principles
- Phone owns the session lifecycle (start/pause/resume/end), persistence, distance/GPS, pace, and business logic.
- Watch initiates actions (start/pause/resume/end) and streams sensors (HR, steps) only after the phone acknowledges a start.
- No session IDs or persistence on the watch. No local distance/GPS on the watch.
- Idempotent commands, explicit acknowledgements, and clear failure codes.

## Roles & Sources Of Truth
- Phone: authoritative for lifecycle, IDs, storage, GPS/distance/pace, completion, and UI decisions.
- Watch: primary live source for heart rate and steps during an active session; mirrors state from the phone.
- HealthKit backfill: phone reconciles gaps from HK after session when connectivity dropped.

## Message Protocol (WCSession)
All messages include a `commandId` (UUID) for idempotency. Phone responds with ACK/FAIL including the same `commandId`.

### Commands (Watch → Phone)
- `startSessionFromWatch`:
  ```json
  {
    "commandId": "uuid",
    "command": "startSessionFromWatch",
    "ruckWeightKg": 20.0,
    "userWeightKg": 80.0,
    "routeId": null
  }
  ```
- `pauseSession`, `resumeSession`, `endSession`:
  ```json
  { "commandId": "uuid", "command": "pauseSession" }
  ```
- Sensor updates (only after startConfirmed):
  - `watchHeartRateUpdate`: `{ "command": "watchHeartRateUpdate", "bpm": 132, "ts": 1712345678 }`
  - `watchStepUpdate`: `{ "command": "watchStepUpdate", "steps": 18, "ts": 1712345678 }`

### Responses (Phone → Watch)
- `startConfirmed`:
  ```json
  { "command": "startConfirmed", "commandId": "uuid", "sessionId": "12345" }
  ```
- `sessionStartFailed`:
  ```json
  { "command": "sessionStartFailed", "commandId": "uuid", "reasonCode": "alreadyActive", "error": "A session is already active." }
  ```
- `pauseConfirmed`, `resumeConfirmed`, `sessionEnded`:
  ```json
  { "command": "pauseConfirmed", "commandId": "uuid" }
  ```
- `syncSessionState` / `updateMetrics` (push from phone):
  ```json
  {
    "command": "updateMetrics",
    "isSessionActive": true,
    "isPaused": false,
    "durationSec": 642,
    "distanceKm": 1.84,
    "pace": 10.2,
    "hrBpm": 132
  }
  ```

## Phone Flow (Authoritative)
1. Receive `startSessionFromWatch`.
2. Validate:
   - No active session; required permissions (Location, Motion & Fitness, Health) are available; app not in a “busy” state.
3. Dispatch `SessionStartRequested(ruckWeightKg, userWeightKg, plannedRoute?)` to the phone’s `ActiveSessionBloc`.
4. On success: reply `startConfirmed {sessionId}`; set current `sessionId` in `WatchService`; begin pushing `syncSessionState`/`updateMetrics`.
5. On failure: reply `sessionStartFailed {reasonCode, error}`.
6. Maintain a short‑term cache of processed `commandId`s (e.g., 30–60s) to ignore duplicates.

Pause/Resume/End received from the watch simply dispatch the corresponding events; ACK with `pauseConfirmed`/`resumeConfirmed`/`sessionEnded` once applied.

## Watch Flow (Dumb + Safe)
1. User taps Start → send `startSessionFromWatch` with a fresh `commandId` and show “Starting…”.
2. Only transition to Active on `startConfirmed {sessionId}`.
3. After `startConfirmed`, start `HKWorkoutSession` and begin streaming `watchHeartRateUpdate` (≈1 Hz) and `watchStepUpdate` (≈0.5–1 Hz) to the phone.
4. Pause/Resume/End: send commands and wait for confirmations before updating UI and toggling sensors.
5. If no ACK within ~8s, show a timeout with a Retry action (reuse the same `commandId`).
6. If `WCSession.isReachable` is false, show “Open the iPhone app” and do not attempt background starts.

## Heart Rate & Steps Policy
- Primary live source: Watch. Start sensors only after `startConfirmed`.
- Phone consumes watch HR/steps; if they stop (connectivity loss), phone temporarily falls back to CMPedometer/HealthKit for continuity.
- Post‑session, phone reconciles via HealthKit anchored queries to fill any gaps.

## State Machines
### Watch UI States
- Idle → Starting (waiting for `startConfirmed`) → Active → Paused → Ending (waiting for `sessionEnded`) → Idle.
Transitions only occur on phone confirmations.

### Phone Session States (simplified)
- Inactive → Starting → Running/Paused → Completing → Inactive. Phone pushes mirrored state to the watch.

## Idempotency & Reliability
- Include `commandId` in every watch command; phone caches processed IDs and ignores duplicates.
- ACK timeout (watch): 8s default. Display retry with the same ID.
- HR rate: 1 Hz max; steps: 0.5–1 Hz; debounce on phone to avoid UI thrash.

## Permissions & Failure Codes
Phone returns a `sessionStartFailed.reasonCode` so the watch can show a precise message.

Common `reasonCode` values:
- `alreadyActive`: a session is already active on phone.
- `notReachable`: phone cannot be reached (watch should check before sending).
- `needsPermission:location` | `needsPermission:motion` | `needsPermission:health`.
- `healthNotAvailable`: HK not available on device.
- `busy`: app is performing a critical operation.
- `timeout`: phone could not start in time.
- `unknown`: unexpected error.

## Connectivity & Backfill
- If connectivity drops mid‑session: watch keeps HK workout running and continues recording; phone continues session using last known data and falls back to local sensors when possible.
- After reconnection or on completion: phone fetches HK samples and reconciles distance/HR gaps.

## Feature Flags & Kill Switch
- Gate the flow behind `enableWatchStart`. If stability issues arise, disable the watch start without removing code.

## Telemetry & Logging
- Tag all lifecycle actions with `source: 'watch'` or `source: 'phone'` in logs.
- Log `commandId`, timestamps, ACK times, and failure codes for diagnostics.

## Testing Checklist
- Happy path: start from watch → phone starts session → watch shows Active and streams HR/steps.
- Not reachable: watch shows “Open the iPhone app”.
- Duplicate taps: only one session; duplicates ignored by `commandId` cache.
- Already active: `sessionStartFailed(alreadyActive)` and clear UI on watch.
- Pause/Resume/End: require confirmations; sensors toggle accordingly.
- Permission missing: `needsPermission:*` surfaced with clear user guidance.
- Connectivity loss: watch continues collecting → phone backfills from HK on completion.

## Future Extensions (Optional)
- Heartbeat pings to surface stale connections quickly.
- Automatic reconnection with buffered sensor updates on the watch.
- Granular rate control based on phone battery or app state.

