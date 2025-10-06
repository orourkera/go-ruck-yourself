# Pause/Resume Bug - Distance/Calories/Pace Freeze

## Issue Report
**Reporter:** stepdebugger
**Device:** iPhone 15 Pro (no Apple Watch)
**Session ID:** 3956

## Symptoms
When pausing and then resuming a ruck session:
- ✅ Step count continues updating
- ❌ Distance freezes at pause point
- ❌ Calories freeze at pause point
- ❌ Pace freezes at pause point
- ❌ `paused_duration_seconds` saved as `null` in database

## Database Evidence
```sql
{
  "id": 3956,
  "distance_km": 2.13478952177729,  // Frozen value
  "duration_seconds": 4045,
  "paused_duration_seconds": null,  // Not tracked!
  "status": "completed"
}
```

## Root Cause Analysis

### What Works:
1. `SessionPaused` event sets `_isPaused = true` (location_tracking_manager.dart:370)
2. `SessionResumed` event restarts location tracking (line 383-405)
3. Location subscription properly restarts
4. `totalPausedDuration` is tracked in state (session_lifecycle_manager.dart:581)

### What's Broken:
1. **Location updates after resume don't update UI metrics**
   - Location manager restarts tracking ✅
   - But distance/pace/calories don't recalculate ❌

2. **paused_duration_seconds not saved to backend**
   - Tracked in state as `totalPausedDuration` ✅
   - Saved to local storage (line 1028-1029) ✅
   - NOT sent in completion payload to backend ❌

3. **State aggregation issue**
   - After resume, `_aggregateAndEmitState()` might not be called
   - Or aggregation uses stale/cached distance calculation

## Likely Bug Location

**File:** `active_session_coordinator.dart:383-405`

The `_onSessionResumed` handler routes to managers but might not trigger state re-aggregation:

```dart
Future<void> _onSessionResumed(SessionResumed event, Emitter emit) async {
  AppLogger.info('[COORDINATOR] Session resumed');
  await _routeEventToManagers(event);
  // MISSING: _aggregateAndEmitState(); ← Need to force recalculation!
}
```

## Fix Strategy

### Short-term (Quick Fix):
1. Add `_aggregateAndEmitState()` after `SessionResumed` routes to managers
2. Force distance/pace/calories recalculation on resume
3. Include `pausedDurationSeconds` in backend save payload

### Long-term (Proper Fix):
1. Add pause/resume integration tests
2. Log pause/resume events to analytics
3. Add UI indicator showing "X minutes paused"
4. Verify all metrics (not just distance) update after resume

## Steps to Reproduce
1. Start a ruck session
2. Let it track for ~1km
3. Tap pause button
4. Wait 1 minute
5. Tap resume
6. Continue rucking
7. **Bug:** Distance stays at ~1km, doesn't increase

## Test User
Username: `stepdebugger`
Session: 3956
Can reproduce issue

## Priority
**HIGH** - Breaks core session tracking functionality
