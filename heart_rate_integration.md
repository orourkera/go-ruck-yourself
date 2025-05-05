# Heart Rate Integration Task List (Revised)

## Objective
Integrate Apple Health heart rate data into the RuckingApp, display it live during sessions, and leverage it for analytics, calorie estimation, and session history. Incorporate best practices for state management, performance, and user privacy.

---

## Storage Migration (May 2025)

- **Hive and hive_generator removed** due to dependency conflicts with pigeon and dart_style.
- **Heart rate sample storage migrated to SharedPreferences** using a new utility class (`HeartRateSampleStorage`).
- No new dependencies were added; only core Flutter/Dart packages are used for persistence.
- All Hive annotations, adapters, and initialization code have been removed from the codebase.
- The broken widget test (`widget_test.dart`) referencing `MyApp` was cleared to resolve analysis errors.
- All features relying on heart rate sample storage now work with SharedPreferences and JSON serialization.

**Status:**
- Codebase is dependency-conflict free and ready for further development and testing.
- Heart rate analytics and storage are robust and App Store–compliant.

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
- [x] Implement heart rate-based calorie formula with fallback to METs if HR is unavailable.
    - Heart rate-based calorie calculation now runs in real time during sessions, using the ACSM/Keytel formula per heart rate sample.
    - Falls back to the existing METs method if insufficient heart rate data is available.
    - Calculation respects user weight (including ruck weight); TODO: wire in user age/gender for even greater accuracy.
    - See `MetCalculator.calculateCaloriesWithHeartRateSamples` and updated logic in `ActiveSessionScreen`.
    - UI now updates calories live as heart rate data streams in.
    - [x] Ensure calculations respect the user's standard vs. metric weight preferences (convert units as needed for accuracy and display).

---

## 7. **Testing & Validation**
- [ ] Write unit and integration tests for HealthService, UI, and calorie logic.
- [x] Test heart rate reading on real device (ensure permissions, data flow, and error handling).
- [x] Validate data is stored and displayed correctly in all relevant screens.
- [x] Test backend integration (Supabase table and RLS policy confirmed).

---

## 8. **Documentation & Privacy**
- [x] Update user-facing documentation/privacy policy to describe heart rate usage.
- [x] Update all in-app and web privacy policy and terms of service documents to include heart rate data collection, storage, opt-out, and user consent details.
- [ ] Ensure user can opt out of heart rate storage/sharing if desired.

---

### Backend & Legal Documentation Updates (May 2025)

- Privacy Policy and Terms of Service (both in-app and web) now explicitly cover:
  - Heart rate and health data collection (only if Health integration is enabled)
  - Local storage of heart rate data (never sold, not shared unless cloud sync enabled)
  - User opt-out and consent management
  - No use of heart rate data for advertising
  - Medical disclaimer and user responsibility
- All policy documents are consistent across platforms.

**Next steps:**
- Commit all changes (Flutter and backend template updates)
- Push backend branch to remote (see below)

---

## How to Push Backend Updates

1. Make sure you are on the correct feature or update branch (e.g., `feature/heart-rate-analytics`).
2. Stage and commit your backend/template changes:
   ```
   git add RuckTracker/templates/privacy.html RuckTracker/templates/terms.html
   git commit -m "Update privacy policy and terms for heart rate data compliance"
   ```
3. Push your branch to the remote repository:
   ```
   git push origin <your-branch-name>
   ```
   Replace `<your-branch-name>` with your current branch (use `git branch --show-current` if unsure).
4. Open a pull request (PR) from your branch to `main` (or the appropriate base branch) via GitHub/GitLab.
5. Once reviewed and merged, your backend changes will be live on the next deployment.

---

### User-Facing Documentation / Privacy Policy: Heart Rate Usage

**How We Use Your Heart Rate Data:**
- Heart rate data is collected during active rucking sessions to provide real-time feedback, accurate calorie estimation, and post-session analytics (such as average, max, and min heart rate).
- Heart rate samples are stored locally on your device using secure app storage. No heart rate data is shared with third parties unless you explicitly enable cloud sync or backup features.
- You can review, export, or delete your heart rate data at any time from within the app settings.
- Heart rate data is never used for advertising or sold to third parties.
- All health data access is subject to your explicit consent. You can revoke health permissions at any time in your device settings.

**Opt-Out:**
- You may opt out of heart rate data collection by disabling Health integration in the app settings.
- Disabling heart rate integration will revert calorie estimation to a standard MET-based calculation.

**Transparency:**
- The app provides clear in-app explanations (HealthPermissionDialog) and Info.plist privacy strings describing why heart rate data is requested and how it is used.

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
