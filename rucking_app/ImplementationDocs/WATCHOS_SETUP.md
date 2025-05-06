# Watch Integration Detailed Implementation Plan with Feature Checklists

## 1. Overview

This document outlines a detailed, step-by-step implementation plan for integrating the companion Apple Watch application with the Go Ruck Yourself phone app. The integration follows these key principles:

- **Workout Initiation**: All workouts are started on the phone. The Watch serves purely as a display and notification device.
- **Real-Time Data Flow**: The Watch continuously sends heart rate data to the phone, and the phone pushes live session metrics (calories, distance, pace, elevation) to the Watch.
- **Centralized Computation**: All calculations occur on the phone; the Watch does not perform any processing.
- **Split Notifications**: The phone computes split times (1 km or 1 mile, per user preference) and sends notifications to the Watch.

---

## 2. Project & Directory Structure

The integration involves adding a watchOS target to the existing iOS project within the Flutter app structure. The recommended directory structure is:

```
/Users/rory/RuckingApp/rucking_app/
├── ios/
│   ├── Runner/                    # Main iOS app target
│   ├── GRY Watch App/             # WatchOS App target
│   └── GRY Watch App Extension/   # WatchKit Extension target
├── lib/                           # Flutter Dart code
│   ├── features/
│   │   └── ruck_session/          # Session-related features
│   └── services/                  # Platform services for Watch communication
├── android/                       # Android app components (if applicable)
└── pubspec.yaml                   # Flutter dependencies
```

- **Flutter Code**: Dart code for the app logic resides in `lib/`, including platform channels for Watch communication.
- **Watch Targets**: The `GRY Watch App` and `GRY Watch App Extension` are added via Xcode to the `ios/` directory for Watch-specific UI and logic.

---

## 3. Flutter and Native Integration

Since Go Ruck Yourself is built with Flutter, communication between the Flutter app and the Watch requires bridging Dart with native iOS/watchOS code using platform channels:

- **Platform Channels**: 
  - Use `MethodChannel` for bidirectional communication (e.g., starting a workout, sending commands).
  - Use `EventChannel` for streaming real-time data (e.g., heart rate from Watch to phone).
- **Setup**: Add platform channel definitions in Dart under `lib/services/watch_service.dart` and corresponding native handlers in `ios/Runner/AppDelegate.swift` or a dedicated Swift file.
- **Data Flow**: Flutter sends workout start/stop commands to iOS, which relays them to the Watch via WatchConnectivity. The Watch streams heart rate back through iOS to Flutter.

### Steps:
1. Define `MethodChannel` for control messages (e.g., `startWorkout`, `stopWorkout`).
2. Define `EventChannel` for heart rate streaming.
3. Implement native iOS code to interface with WatchConnectivity framework.

---

## 4. WatchOS App Architecture

The Watch app will be a lightweight display and data collection tool, with minimal logic:

- **UI Components**: Use `WKInterfaceController` to build Watch UI screens for displaying metrics (heart rate, distance, calories, pace, elevation).
- **Communication**: Leverage the WatchConnectivity framework (`WCSession`) for real-time data exchange with the iOS app.
- **HealthKit Integration**: Access heart rate data via HealthKit on the Watch, sending it to the phone.

### Key Classes:
- `InterfaceController`: Main Watch UI controller for displaying live metrics.
- `WorkoutManager`: Manages HealthKit access and heart rate sampling.
- `SessionManager`: Handles `WCSession` communication with the iOS app.

---

## 5. Workout Initiation Flow

Since workouts are initiated on the phone, the flow is as follows:

1. **User Action**: User starts a workout via the Flutter app UI.
2. **Flutter Logic**: Dart code triggers a `MethodChannel` call to notify iOS of workout start.
3. **iOS Relay**: iOS app uses `WCSession` to send a message (e.g., `workoutStarted`) to the Watch.
4. **Watch Response**: Watch app updates UI to show workout in progress and begins sampling heart rate via HealthKit.

---

## 6. Real-Time Data Flow Implementation

Real-time data exchange is critical for live metrics:

- **Heart Rate from Watch to Phone**:
  - Watch app queries HealthKit for heart rate data at regular intervals (e.g., every 5 seconds).
  - Data is sent to iOS app via `WCSession.sendMessage` or `transferCurrentComplicationUserInfo` for complications.
  - iOS app relays data to Flutter via `EventChannel` for processing.
  - **Storage**: Heart rate data points are timestamped and stored in the Flutter app’s local database for each session, with periodic syncing to Supabase for historical analysis and visualization.
- **Metrics from Phone to Watch**:
  - Flutter computes metrics (calories, distance, pace, elevation) based on heart rate and other data.
  - Metrics are sent to iOS via `MethodChannel`, then to Watch via `WCSession`.
  - Watch updates UI with new metrics.
- **Error Handling**:
  - Implement reconnection logic for `WCSession` interruptions.
  - Buffer data during disconnects to prevent loss, syncing when connection resumes.
- **Background Modes**:
  - Enable background modes on Watch and iOS app to maintain data flow when apps are not in foreground.

---

## 7. Centralized Computation Details

All calculations occur on the phone to keep the Watch app lightweight:

- **Data Processing**: Flutter app processes raw heart rate data from the Watch to compute metrics like calories burned (using formulas based on heart rate, user weight, and activity duration), distance (via GPS data), pace, and elevation changes.
- **Storage**: Processed data is stored in the Flutter app’s local database and synced with the Supabase backend for session history.
- **Formatting**: Metrics are formatted in Flutter (e.g., converting meters to km for distance) before being sent to the Watch for display.

---

## 8. Split Notifications

Split notifications for distance milestones are computed on the phone:

- **Logic**: Flutter monitors distance traveled during a session, triggering a split notification at user-defined intervals (1 km or 1 mile, based on user preference stored in app settings).
- **Notification Delivery**: Notification data (e.g., split time, distance) is sent to iOS via `MethodChannel`, then to Watch via `WCSession.sendMessage`.
- **Watch Display**: Watch app shows a local notification or updates UI with haptic feedback for the split.

---

## 9. Feature Checklist

Below are detailed checklists for each feature to track implementation progress:

### Workout Initiation
- [x] Add `MethodChannel` in Flutter for sending workout start/stop commands.
- [x] Implement iOS handler to relay commands to Watch via `WCSession`.
- [x] Update Watch app to listen for `workoutStarted` message and change UI state.

### Real-Time Heart Rate Streaming
- [x] Set up HealthKit access on Watch for heart rate data.
- [x] Implement periodic heart rate sampling on Watch (e.g., every 5 seconds).
- [x] Send heart rate data to iOS app using `WCSession.sendMessage`.
- [x] Relay heart rate from iOS to Flutter via `EventChannel`.
- [x] Store timestamped heart rate data points in local database for each session.

### Live Metrics Display on Watch
- [x] Design Watch UI with `WKInterfaceController` to show metrics (heart rate, distance, calories, pace, elevation).
- [x] Receive metrics from phone via `WCSession` and update Watch UI in real-time.

### Split Notifications
- [ ] Implement distance tracking logic in Flutter to detect splits (1 km or 1 mile).
- [ ] Send split notification data to Watch via `MethodChannel` and `WCSession`.
- [ ] Display split notifications on Watch with haptic feedback.

### Heart Rate Graph on Session Summary
- [ ] Design a heart rate graph UI component in Flutter for the session summary page in the iOS app.
- [ ] Retrieve stored heart rate data points for a completed session from the local database.
- [ ] Plot heart rate over time using the existing `fl_chart` library (version 0.64.0).
- [ ] Ensure the graph updates dynamically based on session selection.

### General Setup
- [x] Add WatchKit target in Xcode for Watch App and Extension.
- [x] Configure project capabilities for WatchConnectivity and HealthKit.
  - [x] Enabled HealthKit capability in Xcode.
  - [x] Update `Info.plist` with HealthKit privacy descriptions (NSHealthShareUsageDescription, NSHealthUpdateUsageDescription).

---

## 10. Permissions and Capabilities

- **HealthKit**: Required on Watch for heart rate data access. Add `com.apple.developer.healthkit` entitlement and request user permission.
- **WatchConnectivity**: Enable in both iOS and Watch targets for data exchange.
- **Background Modes**: Enable `Background App Refresh` and `Workout Processing` for continuous operation.
- **Privacy Descriptions**: Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` to `Info.plist` for user consent.

---

## 11. Testing and Debugging Plan

- **Simulator Testing**: Use Xcode’s iOS and Watch simulators to test paired app behavior.
- **Connection States**: Test data flow under various states (Watch app active, background, disconnected).
- **Data Validation**: Verify heart rate data accuracy and metric calculations between Watch and phone.
- **Debugging Tools**: Use Xcode logs for native code and Flutter DevTools for Dart/platform channel debugging.
- **Physical Device Testing**: Test on real Apple Watch and iPhone for accurate HealthKit data and performance.

---

## 12. Deployment and Compatibility

- **Target Versions**: Support watchOS 9.0+ and iOS 16.0+ for modern API compatibility.
- **Deployment**: Package Watch app as part of the iOS app submission to App Store Connect, ensuring both are bundled together.
- **Compatibility Handling**: Gracefully degrade features (e.g., disable Watch features) if user lacks an Apple Watch or runs older OS versions.

---

## 13. User Experience (UX) Considerations

- **Watch UI Design**: Optimize for small screen with clear, glanceable metrics (e.g., large font for heart rate, minimal text).
- **Haptic Feedback**: Use Watch haptics for split notifications to alert users without needing to look at the screen.
- **Audio Cues**: Optional audio alerts for splits if user enables them in settings.
- **Customization**: Allow users to choose which metrics appear on Watch via phone app settings.

---

## 14. Security and Privacy

- **Data Encryption**: Ensure heart rate and session data are encrypted during transmission via `WCSession` (handled by Apple’s secure channel).
- **User Consent**: Prompt for HealthKit permissions with clear explanations of data usage.
- **Data Minimization**: Only transmit necessary data between Watch and phone, avoiding storage of sensitive info on Watch.

---

## 15. Integration with Existing Backend

- **Supabase Sync**: Heart rate and session data processed in Flutter are synced to Supabase for long-term storage and analysis.
- **Session Records**: Store complete workout data (including heart rate history if user opts in) in `ruck_session` table or a dedicated `heart_rate_data` table linked to session IDs.
- **User Profile**: Link user preferences (e.g., split distance preference) to Supabase `user` table for consistency across devices.
- **Heart Rate Data**: Periodically upload timestamped heart rate data points to Supabase for historical tracking and potential cross-device visualization.

---

## 16. Next Steps

1. Set up WatchKit targets in Xcode and configure project capabilities.
2. Implement platform channels in Flutter for Watch communication.
3. Develop basic Watch UI for displaying metrics.
4. Test heart rate streaming and metric updates in simulator.
5. Iterate based on user feedback for UX improvements.

This plan provides a comprehensive roadmap for integrating Apple Watch functionality into Go Ruck Yourself, ensuring seamless data flow and a polished user experience. If adjustments or additional features are needed, they can be added to the feature checklist.
