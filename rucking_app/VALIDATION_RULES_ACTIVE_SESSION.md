# Validation Rules for Active Session Screen

This document lists **all validation rules and thresholds** enforced on the Active Session Screen of the Rucking App. Use this as the single source of truth to prevent regressions and ensure consistent behavior across all branches and features.

---

## 1. Minimum Initial Distance for Stats Display
- **Threshold:** 50 meters
- **Purpose:** Stats (Distance, Pace, Calories, Elevation) are only shown after the user has moved at least 50 meters. Until then, spinners are displayed.
- **Implementation:**
  - Controlled by `SessionValidationService.minInitialDistanceMeters`.
  - `_canShowStats` is set to `true` after this threshold is reached.

## 2. Minimum Session Distance for Saving
- **Threshold:** 100 meters
- **Purpose:** A session cannot be saved unless the user has moved at least 100 meters.
- **Implementation:**
  - Controlled by `SessionValidationService.minSessionDistanceMeters`.
  - Used in session completion and save validation.

## 3. Minimum Session Duration for Saving
- **Threshold:** 2 minutes
- **Purpose:** A session cannot be saved unless it lasts at least 2 minutes.
- **Implementation:**
  - Controlled by `SessionValidationService.minSessionDuration`.

## 4. Auto-Pause on Inactivity
- **Rule:** If user speed drops below 0.5 km/h for more than 1 minute, the session is auto-paused.
- **Purpose:** Prevents false tracking when the user is idle.
- **Implementation:**
  - Controlled by `SessionValidationService.minMovingSpeedKmh` and `longIdleDuration` (1 minute).
  - UI sets `_isPaused = true` and displays a pause message.

## 5. Maximum Speed Validation
- **Threshold:** 10 km/h
- **Purpose:** Prevents tracking if the user is moving too fast (e.g., in a car or running).
- **Implementation:**
  - Controlled by `SessionValidationService.maxSpeedKmh`.
  - If exceeded for more than 1 minute, session may be ended or flagged.

## 6. Segment Validation (Distance & Elevation)
- **All segment-level validation is centralized in `SessionValidationService`**.
- **Distance Segment Validation:**
  - Each new GPS segment is validated using `validateLocationPoint(previousPoint, newPoint, distanceMeters)`.
  - Rules applied:
    - **Max Position Jump:** Segments >20 meters in <5 seconds are ignored as GPS jumps.
    - **GPS Accuracy:** Points with accuracy worse than 20 meters are ignored after a 30s buffer.
    - **Speed:** Segments with speed >10 km/h (for >1 min) are auto-paused.
    - **Idle:** Speed <0.5 km/h for >2 min triggers session end suggestion.
    - **Initial Distance:** Cumulative distance must reach 50m for stats to display.
    - **Session Save:** Cumulative distance must reach 100m to allow saving.
- **Elevation Gain/Loss Validation:**
  - Elevation gain/loss is only counted if the change between two points exceeds 1 meter.
  - This is handled by `validateElevationChange(previousPoint, newPoint, minChangeMeters=1.0)`.

## 7. Calories Burned Sanity Check
- **Rule:** Warn (but do not block) if calories/hour is outside expected range.
- **Purpose:** Prevents unrealistic calorie stats.
- **Implementation:**
  - Controlled by `minCaloriesPerHour` and `maxCaloriesPerHour` in validation service.

## 8. Error Handling and Feedback
- **Rule:** User-friendly error messages are shown for all validation failures.
- **Purpose:** Ensure users understand why a session is paused, not saved, or ended.
- **Implementation:**
  - Uses `ErrorHandler` and `_validationMessage` in the UI.

## 9. GPS and Location Validation Rules
- **Minimum GPS Accuracy:** Only accept location points with sufficient accuracy (implementation-specific, e.g., < 20 meters HDOP or accuracy).
- **Initial Distance Calculation:** Uses only valid GPS points to accumulate distance for stats display and session save.
- **Low GPS Signal Handling:** If GPS signal quality drops (accuracy too poor), points may be ignored and a warning may be shown.
- **Distance Calculation:** Uses Haversine formula for accurate earth distances between points.
- **Error Handling:** Poor GPS data does not trigger session end, but may pause stats updates or show a warning.
- **Implementation:**
  - See `SessionValidationService.validateLocationPoint` and `_calculateDistanceBetweenPoints`.
  - Internal state tracks last valid point, cumulative distance, and ignores points with poor accuracy.

## 10. Centralization of Validation Logic
- **All validation thresholds and logic are implemented in `SessionValidationService` (`domain/services/session_validation_service.dart`).**
- **No validation logic exists in the BLoC or UI.**
- **This ensures a single source of truth and prevents regressions.**

---

**Note:**
If you change any validation logic or thresholds, update this file and `SessionValidationService` together to keep documentation and implementation in sync.

---

_Last updated: 2025-05-05_
