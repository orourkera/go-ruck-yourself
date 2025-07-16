
# Implementation Plan for Manual Offline Ruck Feature

## Overview
This document outlines the step-by-step plan to implement the "Record Offline Ruck" feature in the Rucking App. This allows users to manually enter completed ruck sessions (offline/manual mode) without live tracking. Key requirements:
- Toggle via a text link on the Create Session screen.
- Manual inputs: duration (required, minutes), distance (required, respects metric/imperial), elevation gain/loss (optional).
- Calculations: Pace (min/km), Calories (using MET formula).
- Save directly to DB as a completed session.
- Navigate to Session Complete screen post-save.
- Special rules: These sessions do NOT trigger achievements and do NOT appear in the Ruck Buddies feed.
- Integration with existing Bloc architecture, repositories, and models.

The implementation will modify existing files (e.g., CreateSessionScreen, SessionRepository) and add minimal new code for calculations and flags.

## Requirements Breakdown
- **UI**: Small text link "Record Offline Ruck" below start button. Toggles to show fields and change button to "Save Offline Ruck". Link becomes "Cancel" in offline mode.
- **Inputs**:
  - Duration: Required, positive integer (minutes).
  - Distance: Required, decimal, in km (metric) or miles (imperial); convert to km for storage.
  - Elevation Gain/Loss: Optional, decimal, in meters (metric) or feet (imperial); convert to meters for storage.
  - Reuse existing ruck weight and user weight from form.
- **Calculations**:
  - Pace: (durationMinutes / distanceKm) as min/km.
  - Calories: MET * (userWeightKg + ruckWeightKg) * (durationSeconds / 3600), with MET based on pace (e.g., 8.0 for fast, 6.5 moderate, 5.0 slow).
  - Elevation: User-entered or 0.
- **Saving**:
  - Generate manual session ID (e.g., 'manual_${timestamp}').
  - Create RuckSession object with backdated startTime = now - duration.
  - Flag as manual (new field: isManual: true) to skip achievements/feed.
  - POST to /rucks via SessionRepository.
- **Restrictions**:
  - No achievements: Skip achievement checks in completion flow.
  - No Ruck Buddies feed: Add DB filter or API param to exclude manual sessions from feeds.
- **Edge Cases**: Invalid inputs, offline saves, metric conversions, zero values, large numbers.

## Affected Files and Changes
1. **rucking_app/lib/features/ruck_session/presentation/screens/create_session_screen.dart**
   - Add state vars: _isOfflineMode (bool), controllers for duration/distance/elevation.
   - Add TextButton for toggle.
   - Conditionally add fields to form Column if _isOfflineMode.
   - Update button: onPressed = _isOfflineMode ? _saveOfflineRuck : _createSession; label = "Save Offline Ruck" or "Start Session".
   - Implement _saveOfflineRuck(): Validate, parse/convert inputs, calculate pace/calories, build RuckSession, call repository to save, navigate to SessionCompleteScreen.

2. **rucking_app/lib/features/ruck_session/data/repositories/session_repository.dart**
   - Add createManualSession(Map<String, dynamic> data): POST to /rucks, include 'is_manual': true.
   - Ensure API handles 'is_manual' flag (assume backend update needed).

3. **rucking_app/lib/features/ruck_session/domain/models/ruck_session.dart**
   - Add bool isManual = false; to model and fromJson/toJson.

4. **rucking_app/lib/features/ruck_session/presentation/screens/session_complete_screen.dart**
   - In save logic: If session.isManual, skip achievement checks (e.g., don't call achievementRepository.clearCache() or checkAchievements).

5. **Ruck Buddies Feed Integration**:
   - In rucking_app/lib/features/ruck_buddies/data/datasources/ruck_buddies_remote_datasource.dart, add 'exclude_manual': 'true' to queryParams in getRuckBuddies.

6. **New Helper (Optional)**: rucking_app/lib/features/ruck_session/domain/services/manual_session_service.dart
   - For calculations: double calculatePace(double durationMin, double distanceKm); double calculateCalories(...).

## Step-by-Step Implementation Steps
1. **Update Models (10 min)**:
   - Add isManual to RuckSession.

2. **UI Toggle and Fields (30 min)**:
   - In CreateSessionScreen, add toggle logic, fields, and conditional button.

3. **Save Logic (45 min)**:
   - Implement _saveOfflineRuck: Parse inputs, conversions (use preferMetric), calculations.
   - Build RuckSession with isManual: true, backdated times.
   - Call createManualSession in repository.

4. **Repository Update (20 min)**:
   - Add createManualSession method.

5. **Skip Achievements/Feed (30 min)**:
   - In SessionCompleteScreen: If isManual, skip achievement logic.
   - In feed-related code: Filter out manual sessions (search codebase for feed queries and add condition).
   - In Ruck Buddies data source: Add exclude_manual param to API query.

6. **Testing (1 hour)**:
   - Unit: Test calculations (e.g., pace=12 min/km for 60min/5km).
   - Integration: Simulate save, verify DB entry, no achievements triggered.
   - UI: Toggle works, validations fire, metric/imperial correct.
   - Edge: Zero distance (allow but warn), invalid inputs, offline mode.

## Potential Challenges and Solutions
- **Metric Conversions**: Always store in metric; convert in UI. Solution: Helper functions for toMetric/fromMetric.
- **Achievements Skipping**: Ensure no side-effects; mock repository in tests.
- **Feed Exclusion**: If feed is in another module, coordinate with that (e.g., add param to API).
- **Security**: Manual entries could be abused; add server-side validation (e.g., rate limits).

## Timeline Estimate
- Total: 3-4 hours for implementation + testing.
- Review backend for 'is_manual' support if needed.

This plan ensures clean integration. Proceed to code changes via tool calls. 