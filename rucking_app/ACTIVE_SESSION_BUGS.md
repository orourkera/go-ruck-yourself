# Active Session Page – Known Issues

> Last updated: 2025-05-09
> **Release-candidate focus:** we are closing in on an RC build. Fix bugs only—**no feature regressions and no major refactors** allowed.  The aim is stability and polish. Make sure you keep separation of concerns and remember you're a world class flutter developer. Do not get stuck in analysis paralysis. 

Below is a consolidated list of the *major* bugs currently affecting the **Active Session** page.  Each item captures the observed behaviour, the expected behaviour, and any initial notes that may help triage / reproduce.

| # | Bug / Symptom | Expected Behaviour | Observed Behaviour | Notes / Suspected Cause | Status |
|---|---------------|--------------------|--------------------|-------------------------|--------|
| 1 | **Heart-rate not displayed** | Real-time heart-rate pulled from `HealthService` (or Apple Health / Google Fit) should update every few seconds. | HR field is blank (`-- bpm`). | ‑ Ensure permissions granted.<br>- | **Fixed** |
| 2 | **Calories remain at 0** | Estimated calories should increment during the workout. | Fixed – calories now increment correctly during session. | Implemented real-time calculation using `MetCalculator.calculateRuckingCalories` in `ActiveSessionBloc._onTick`. | **Fixed** |
| 3 | **Pace value extremely large** | Pace should be shown in min/km or min/mi as a small integer with 1 decimal (e.g. `8.3 min/km`). | Fixed – pace now displays correctly. | Number formatting issue resolved in `SessionStatsOverlay` (removed extra `* 60`). | **Fixed** |
| 4 | **Pause overlay blocks resume** | Tapping *Pause* should show a small overlay with *Resume* / *End* buttons and dismiss when *Resume* tapped. | Full-screen semitransparent overlay appears, but *Resume* button is not tappable. | Overlay may be using a `ModalBarrier` with `dismissible:false` placed above gesture detectors; pointer events swallowed. | **Fixed** |
| 5 | **“Session too short” modal shown after every session** | Only show modal when distance < 0.1 km **or** duration < 2 min. | Modal appears even for long sessions. | Condition in `SessionStatsOverlay._shouldShowTooShortModal()` may use wrong units (metres vs km) or state not reset. | **Fixed** |
## Potential Root-Cause Groupings

| Group | Affected Bugs | Likely Common Cause |
|-------|---------------|---------------------|
| **Metrics not updating** | 1 – Heart-rate<br>2 – Calories<br>3 – Pace<br>5 – “Session too short” modal | The real-time **tick/update pipeline** (streams → `ActiveSessionBloc` → UI) may be broken. If distance/heart-rate/calorie streams never emit, the UI shows zeros/large defaults *and* the end-of-session validator thinks the workout is too short. Focus on:
• `watchService` & `HealthService` subscriptions
• Bloc event `SessionTick` fired by timer
• State mapping to the UI widgets |
| **Overlay input blocked** | 4 – Pause overlay blocks resume | `ModalBarrier` or overlay stack order swallowing taps. Likely isolated UI layer bug. |

> Fixing the **Metrics not updating** pipeline will probably resolve **four** of the five issues in one shot.

## Bug-Fix Plan (Release Candidate)

- [x] **Restore heart-rate stream**  
  - [x] Ensure HealthKit permissions request succeeds  
  - [x] Subscribe `ActiveSessionBloc` to `healthService.heartRateStream` (HealthKit) and map to state every tick
- [x] **Correct pace & distance handling**  
  - [x] Verify distance units passed to pace formatter (`m → km`)  
  - [x] Clamp formatter to 1-decimal *min/km* (or *min/mi* when imperial) using `measurement_utils.dart`
- [x] **Wire calorie calculation**  
  - [x] Call `MetCalculator.calculateRuckingCalories` each tick and push to state  
  - [x] Display value with `kcal` suffix
- [x] **Fix “Session too short” logic**  
  - [x] Confirm validator uses **kilometres** and **minutes** (see VALIDATION_RULES_ACTIVE_SESSION.md for thresholds and conversions)  
  - [x] Reset validator state when a new session starts  
- [x] **Repair pause overlay interaction**  
  - [x] Overlay now uses `Stack` + `IgnorePointer` so controls are always accessible and resume button is never blocked  
  - [x] Resume button is fully hit-testable and has focus when paused

> All major bugs for the release candidate are now resolved. The pause overlay interaction is fixed and the resume button is always accessible.

## Next Steps
1. Assign each bug an owner in upcoming sprint planning.
2. ~~Add failing widget / bloc tests where possible to prevent regressions.~~
3. Update this file as fixes are merged (`Status` Fixed and SHA reference).
