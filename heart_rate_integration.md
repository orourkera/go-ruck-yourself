# Heart Rate Integration Task List (Revised)

## Objective
Integrate Apple Health heart rate data into the RuckingApp, display it live during sessions, and leverage it for analytics, calorie estimation, and session history. Incorporate best practices for state management, performance, and user privacy.

---

## 1. **Data Model & Storage Strategy**
- [x] **Define heart rate storage strategy**: Choose between local (device-only), cloud (backend/Supabase), or hybrid. Document schema for heart rate samples (timestamp, bpm).
- [x] Cap in-memory heart rate samples (e.g., last 100–200 points) and periodically save to local storage for long sessions.
- [x] Update backend API and Supabase schema (if storing HR in cloud):
    - [x] Backend endpoint for heart rate sample upload implemented
    - [x] Supabase table `heart_rate_sample` created with RLS policy

---

## 2. **Apple Health Integration**
- [x] Use the `health` package for Apple Health integration.
- [x] Implement a Stream for live heart rate data.
- [x] Ensure permissions for heart rate reading are requested and explained (HealthPermissionDialog, Info.plist).
- [ ] Add heart rate opt-out toggle and localize permission dialogs.

---

## 3. **State Management**
- [x] Use Riverpod for state management of live heart rate and session stats.
- [x] Optimize performance with throttled UI updates and data sampling (e.g., update UI every 3–5 seconds, sample HR every 1–2 seconds).

---

## 4. **Session Tracking (ActiveSessionScreen)**
- [x] Display live heart rate in the UI (verify and enhance as needed).
- [x] Store heart rate samples (timestamp, bpm) during the session.
- [x] Calculate and display:
    - Average heart rate
    - Max/min heart rate
    - Time in heart rate zones (optional, stretch goal)
- [x] Periodically persist heart rate data (local/cloud) during session.
- [x] Send heart rate data to backend when session completes (if cloud storage enabled).

---

## 5. **Session Summary & History**
- [x] Update `SessionCompleteScreen` to show:
    - Average/max/min heart rate for the session
    - Heart rate chart (use `fl_chart`)
- [ ] Update session history (`SessionHistoryScreen`, `SessionDetailScreen`) to display heart rate stats and charts.

---

## 6. **Calorie Estimation**
- [ ] Implement heart rate-based calorie formula with fallback to METs if HR is unavailable.
    - **Note:** This will require modifying the `MetCalculator` or METs file to incorporate heart rate into calorie calculations.
    - **Note:** Ensure calculations respect the user's standard vs. metric weight preferences (convert units as needed for accuracy and display).

---

## 7. **Testing & Validation**
- [ ] Write unit and integration tests for HealthService, UI, and calorie logic.
- [x] Test heart rate reading on real device (ensure permissions, data flow, and error handling).
- [x] Validate data is stored and displayed correctly in all relevant screens.
- [x] Test backend integration (Supabase table and RLS policy confirmed).

---

## 8. **Documentation & Privacy**
- [ ] Update user-facing documentation/privacy policy to describe heart rate usage.
- [ ] Ensure user can opt out of heart rate storage/sharing if desired.

---

## **Affected Pages/Files**
- `lib/features/ruck_session/presentation/screens/active_session_screen.dart`
- `lib/features/ruck_session/presentation/screens/session_complete_screen.dart`
- `lib/features/ruck_session/presentation/screens/session_history_screen.dart`
- `lib/features/ruck_session/presentation/screens/session_detail_screen.dart`
- `lib/features/health_integration/domain/health_service.dart`
- `lib/features/ruck_session/domain/services/met_calculator.dart` (or similar METs/calorie logic)
- Backend API & Supabase schema (if storing HR)
- Info.plist & HealthPermissionDialog
- Riverpod providers (new or updated)

---

## **Stretch Goals**
- Heart rate zone analytics
- Heart rate charts/graphs in session details
- Export/share heart rate data

---

## Notes
- All heart rate data handling must comply with privacy best practices and App Store guidelines.
- Add heart rate opt-out toggle and localize all permission dialogs and user-facing text.
- Ensure robust error handling and user feedback for permissions and data issues.
- Optimize for battery and performance by throttling UI updates and limiting data retention.
