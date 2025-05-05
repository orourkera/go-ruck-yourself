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

## 6. Calories Burned Sanity Check
- **Rule:** Warn (but do not block) if calories/hour is outside expected range.
- **Purpose:** Prevents unrealistic calorie stats.
- **Implementation:**
  - Controlled by `minCaloriesPerHour` and `maxCaloriesPerHour` in validation service.

## 7. Error Handling and Feedback
- **Rule:** User-friendly error messages are shown for all validation failures.
- **Purpose:** Ensure users understand why a session is paused, not saved, or ended.
- **Implementation:**
  - Uses `ErrorHandler` and `_validationMessage` in the UI.

## 8. GPS and Location Validation Rules
- **Minimum GPS Accuracy:** Only accept location points with sufficient accuracy (implementation-specific, e.g., < 20 meters HDOP or accuracy).
- **Initial Distance Calculation:** Uses only valid GPS points to accumulate distance for stats display and session save.
- **Low GPS Signal Handling:** If GPS signal quality drops (accuracy too poor), points may be ignored and a warning may be shown.
- **Distance Calculation:** Uses Haversine formula for accurate earth distances between points.
- **Error Handling:** Poor GPS data does not trigger session end, but may pause stats updates or show a warning.
- **Implementation:**
  - See `SessionValidationService.validateLocationPoint` and `_calculateDistanceBetweenPoints`.
  - Internal state tracks last valid point, cumulative distance, and ignores points with poor accuracy.

---

## **How to Update**
- **Any time you change a validation threshold or rule, update this document immediately.**
- **Review this file before merging, rebasing, or releasing to production.**

---

_Last updated: 2025-05-05_
