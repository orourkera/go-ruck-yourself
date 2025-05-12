# Lock Screen Widget - Implementation Plan

## 1. Overview & Goal

Display key metrics (elapsed time, distance, calories) of an *active* ruck session on the device's lock screen. Provide quick access back to the app, ideally to the active session screen.

## 2. Key Features

- Real-time (or near real-time) display of:
    - Elapsed Session Time
    - Distance Covered
    - Calories Burned
- Widget lifecycle: Appears/activates when a ruck session starts.
- Widget updates: Reflects ongoing session progress.
- Widget termination: Disappears or updates to a final state when the session ends or is manually stopped from the widget (if supported).
- Interaction: Tapping the widget opens the main application to the relevant active session screen.

## 3. Platform-Specific Implementations

### 3.1. iOS - Live Activities
- **Framework:** `ActivityKit` is the primary framework for managing the lifecycle of Live Activities.
- **UI Technology:** Live Activities UIs are built using `WidgetKit` and `SwiftUI`. They are packaged as part of a Widget Extension in your Xcode project.
- **Presentation:** Displayed on the Lock Screen and in the Dynamic Island (on supported devices).
- **Lifecycle Management:**
    - **Start:** Initiated from the main app using `Activity.request()` with initial content.
    - **Update:** The main app updates the Live Activity's dynamic content using an `Activity` object and its `update()` method. Updates can also be pushed via Apple Push Notification service (APNs) for remote changes.
    - **End:** The main app ends the Live Activity using the `end()` method on the `Activity` object.
- **Interactivity:** Limited interactivity can be added using buttons or toggles (iOS 17+), which typically deep-link back into the app or trigger background tasks via App Intents.

### 3.2. Android - App Widgets
- **Core Component:** `AppWidgetProvider` (a subclass of `BroadcastReceiver`) is essential for handling widget lifecycle events (update, delete, enable, disable).
- **UI Technology:**
    - **Traditional:** `RemoteViews` are used to build the UI. This allows Android to display your widget's UI in another process (the launcher). `RemoteViews` support a limited set of UI elements.
    - **Modern (Recommended):** `Glance` (a Jetpack library) allows building widgets using Compose-like syntax with Kotlin. Glance translates these Composables into `RemoteViews` under the hood, simplifying development.
        - Define a `GlanceAppWidget` (for UI content).
        - Define a `GlanceAppWidgetReceiver` (to host the `GlanceAppWidget`).
- **Manifest Declaration:** Widgets must be declared in `AndroidManifest.xml` with a `<receiver>` tag, specifying the `AppWidgetProvider` and linking to an XML metadata file (`AppWidgetProviderInfo`). This XML defines properties like initial layout, update frequency, widget dimensions, etc.
- **Updating:**
    - Widgets can update periodically based on `updatePeriodMillis` in their metadata.
    - Programmatic updates from the app (or a background service) are done using `AppWidgetManager`.
    - For Glance, you'd typically update the state and then call `update()` on the `GlanceAppWidget` instance or `GlanceAppWidgetManager.update()`.
- **Interactivity:** Achieved using `PendingIntent` to trigger actions in your app (e.g., open an Activity, start a Service, send a Broadcast).

## 4. Data Flow & State Management

- **General Challenge:** The widget/Live Activity runs in a separate process from the main Flutter app.

### 4.1. iOS (Live Activities)
- **Mechanism:**
    - **App Groups:** A capability that allows sharing data between your main app and its extensions (like Widget Extensions). This is crucial.
        - Shared `UserDefaults`: `UserDefaults(suiteName: "group.your.app.id")` can store simple key-value data (e.g., JSON strings representing session stats).
        - Shared Files: Store data in a shared container accessible via App Group ID.
    - **From Flutter to Native (for Live Activity):**
        - The Flutter app (e.g., `ActiveSessionBloc`) would collect session data (time, distance, calories).
        - This data is passed to native Swift/Objective-C code via a MethodChannel.
        - The native code then uses `ActivityKit` to start or update the Live Activity, populating its `ActivityAttributes` (static data) and `ActivityContentState` (dynamic data) with the received information.
    - **Updating Widget UI:** The Live Activity UI (SwiftUI) reads data from its `ActivityContentState`. When the app updates the state, the system automatically redraws the Live Activity.

### 4.2. Android (App Widgets)
- **Mechanism:**
    - **`SharedPreferences`:** For simple key-value data. The Flutter app can save data using the `shared_preferences` plugin. The native Android widget code (`AppWidgetProvider` or code called by it) can then read these `SharedPreferences`.
        - Note: Direct cross-process `SharedPreferences` access needs careful handling or use of a `ContentProvider` for robustness, though for simple app-to-widget data push where the app writes and the widget reads on update, it can work.
    - **Databases/Files:** For more complex data, a shared SQLite database (accessed via `ContentProvider`) or files in shared storage can be used, but this adds complexity.
    - **From Flutter to Native (for App Widget):**
        - Flutter app collects session data.
        - Data is saved (e.g., to `SharedPreferences` via `home_widget` or `shared_preferences` plugin).
        - Flutter then triggers a widget update (e.g., using `home_widget.updateWidget()`).
    - **Updating Widget UI:**
        - The `AppWidgetProvider`'s `onUpdate()` method (or equivalent in Glance) is triggered.
        - It reads the latest data (e.g., from `SharedPreferences`).
        - It then constructs new `RemoteViews` (or recomposes the Glance UI) and uses `AppWidgetManager` to update the widget on the home screen.

- **Frequency of Updates & Battery:** Frequent updates can drain battery. Updates should be optimized.
    - iOS Live Activities have system-managed budget for updates.
    - Android widget updates can be less frequent or rely on `WorkManager` for scheduled background tasks that update widget data.

## 5. UI/UX Design

- Simple, clear, and glanceable layout for both platforms.
- Adherence to iOS Human Interface Guidelines for Live Activities.
- Adherence to Android Material Design guidelines for App Widgets.
- Consistent branding with the main app.

## 6. Technical Implementation Details

- **Flutter Packages:**
    - **iOS & Android General (Data Sharing & Update Trigger):**
        - `home_widget`: (Primarily Android focused, but claims iOS support too) Provides a unified interface for sending data from Flutter to native widgets and triggering updates. **Important:** It *does not* allow writing widget UI in Flutter; native code (SwiftUI for iOS, XML/RemoteViews or Glance/Kotlin for Android) is still required for the UI itself.
    - **iOS Specific (Live Activities):**
        - `live_activities` (or `flutter_live_activities`): These packages aim to provide a Dart interface to the native iOS `ActivityKit` framework. You'd use this to start, update, and end Live Activities from Flutter, passing the necessary data for the native SwiftUI views.
        - `flutter_widgetkit` (mentioned in searches, may assist with general WidgetKit interop if `live_activities` is too specific or lacks features for setup).
    - **Data Storage (Flutter side):**
        - `shared_preferences`: Useful for the Flutter app to persist data that the native widget side might read (especially on Android via `home_widget`).

- **Native Code:** Significant native development will be required.
    - **iOS:**
        - **Widget Extension:** Create a new target in Xcode.
        - **SwiftUI:** Define the Live Activity's views.
        - **ActivityKit:** Implement the logic to handle activity lifecycle (attributes, content state).
        - **App Groups:** Configure in Xcode capabilities for data sharing.
        - **MethodChannel:** Bridge between Flutter and native Swift/Objective-C code.
    - **Android:**
        - **`AppWidgetProvider` subclass (Kotlin/Java):** Handle widget lifecycle.
        - **UI:** Either XML layouts with `RemoteViews` or, preferably, `GlanceAppWidget` and `GlanceAppWidgetReceiver` using Kotlin and Glance Composables.
        - **`AndroidManifest.xml`:** Declare the receiver and widget metadata.
        - **`SharedPreferences` / `AppWidgetManager`:** Read data and update widget UI.
        - **MethodChannel:** Bridge between Flutter and native Kotlin/Java code, if `home_widget` doesn't cover all communication needs.

- **Background Execution:**
    - **iOS:** Live Activity updates from the app happen while the app is active or has background execution time. For prolonged updates when the app might be suspended, APNs pushes are the reliable way to update Live Activities.
    - **Android:** `WorkManager` is the recommended solution for deferrable, guaranteed background work that could update widget data. For immediate updates triggered by the app, a foreground service (if the app is tracking an active session) can reliably update the widget.

- **Inter-Process Communication (IPC):** As detailed in Section 4, this primarily involves structured data sharing (App Groups, SharedPreferences) and system-level update triggers.

## 7. Potential Challenges

- Strict background update limitations on both platforms.
- Maintaining data consistency between the app and widget.
- Platform-specific nuances and differing capabilities.
- Testing and debugging across different OS versions and devices.

## 8. Future Enhancements (Optional)

- Basic session controls on the widget (e.g., Pause/Resume, End Session) if platform and UX allow.
- Customizable display metrics.
- Different widget states (e.g., compact, expanded).

---
This plan provides a foundational outline. Details will be refined as development progresses.

## 9. Detailed Task Checklist

### I. Common Setup & Flutter Core
- **A. Define Data Model for Widget:**
    - [ ] Define a clear, concise data structure (e.g., a Dart class, then serialized to JSON) for the information to be displayed on the widget (time, distance, calories).
- **B. Flutter `ActiveSessionBloc` (or equivalent) Modifications:**
    - [ ] Ensure the BLoC exposes the necessary active session data (time, distance, calories) in a way that's easily accessible for sending to the native side.
    - [ ] Consider how frequently this data is updated and made available.
- **C. Flutter Service/Interface for Widget Communication:**
    - [ ] Create a Dart abstract class or service to define methods for: 
        - Starting the lock screen widget/live activity with initial data.
        - Updating the widget/live activity with new data.
        - Stopping/ending the widget/live activity.
    - [ ] Implement platform-specific versions of this service using MethodChannels or a chosen plugin.

### II. iOS - Live Activity Implementation
- **A. Xcode Project Setup:**
    - [ ] Add a new Widget Extension target to the Xcode project.
    - [ ] Enable the App Groups capability for both the main app target and the widget extension target. Define a shared App Group ID.
    - [ ] Add `ActivityKit` framework.
    - [ ] Configure `Info.plist` for Live Activity support (`NSSupportsLiveActivities` set to `YES`).
- **B. Native Swift - Data Structures:**
    - [ ] Define the `ActivityAttributes` struct (for static and identifying data of the Live Activity).
    - [ ] Define the `ContentState` struct (for dynamic data that updates).
- **C. Native Swift - SwiftUI View for Live Activity:**
    - [ ] Design and implement the SwiftUI views for the Live Activity's Lock Screen presentation.
    - [ ] Design and implement SwiftUI views for Dynamic Island presentations (compact, minimal, expanded).
    - [ ] Ensure views correctly bind to the `ContentState`.
- **D. Native Swift - `ActivityKit` Management:**
    - [ ] Create Swift code (e.g., a manager class) to handle:
        - Starting a Live Activity (`Activity.request(...)`).
        - Updating a Live Activity (`activity.update(using: newContentState)`).
        - Ending a Live Activity (`activity.end(...)`).
    - [ ] Handle potential errors from `ActivityKit` operations.
- **E. Flutter to Native Bridge (iOS):**
    - [ ] Set up a `MethodChannel` in Flutter and corresponding handlers in `AppDelegate.swift` (or a dedicated Swift class).
    - [ ] Implement methods on the channel to pass data (serialized session stats) from Flutter to Swift to trigger start/update/end of Live Activity.
    - [ ] If using a package like `live_activities`, understand its API for these operations.
- **F. Live Activity Lifecycle from Flutter:**
    - [ ] Call the bridge/plugin methods from the Flutter service (from I.C) to control the Live Activity based on the app's session state.

### III. Android - App Widget Implementation
- **A. Android Project Setup:**
    - [ ] Create an `AppWidgetProviderInfo` XML file (e.g., in `res/xml/`) defining widget properties (min dimensions, update period, initial layout, preview image).
    - [ ] Declare the `AppWidgetProvider` (or `GlanceAppWidgetReceiver`) as a `<receiver>` in `AndroidManifest.xml`, linking to the metadata XML.
- **B. Native Kotlin/Java - Widget UI:**
    - [ ] **Glance (Recommended):**
        - [ ] Create a `GlanceAppWidget` subclass.
        - [ ] Implement the `@Composable` UI using Glance components (Text, Row, Column, etc.).
    - [ ] **XML/RemoteViews (Traditional):**
        - [ ] Create an XML layout file for the widget.
        - [ ] Use `RemoteViews` in the `AppWidgetProvider` to inflate and update this layout.
- **C. Native Kotlin/Java - `AppWidgetProvider` / `GlanceAppWidgetReceiver`:**
    - [ ] Create a class that extends `AppWidgetProvider` (or `GlanceAppWidgetReceiver`).
    - [ ] Override `onUpdate()` to refresh the widget's content.
    - [ ] Implement other lifecycle methods as needed (`onEnabled`, `onDisabled`, `onDeleted`).
    - [ ] For Glance, implement `GlanceAppWidget.provideGlance()`.
- **D. Native Kotlin/Java - Data Handling:**
    - [ ] Implement logic to read shared data (e.g., from `SharedPreferences` written by Flutter via `home_widget` or `shared_preferences` plugin).
    - [ ] If using `home_widget`, implement the necessary callback handlers (e.g., `HomeWidgetBackgroundIntent.getBroadcast`).
- **E. Flutter to Native Bridge (Android):**
    - [ ] **Using `home_widget` package:**
        - [ ] Implement `HomeWidget.saveWidgetData<String>()` in Flutter to send data.
        - [ ] Implement `HomeWidget.updateWidget()` in Flutter to trigger an update.
        - [ ] Set up background callback handling in native Android code if needed for interactions.
    - [ ] **Manual MethodChannel (if `home_widget` is insufficient):**
        - [ ] Set up a `MethodChannel` in Flutter and handlers in `MainActivity.kt` (or a service).
        - [ ] Implement methods to trigger widget data save and update requests from Flutter.
- **F. Widget Lifecycle & Updates from Flutter:**
    - [ ] Call the bridge/plugin methods from the Flutter service (from I.C) to send data and request widget updates based on the app's session state.
    - [ ] Ensure `AppWidgetManager.updateAppWidget()` is called with new `RemoteViews` or Glance state updates.

### IV. Testing
- **A. Unit Tests:**
    - [ ] Test data serialization/deserialization logic.
    - [ ] Test logic within the Flutter communication service.
    - [ ] Test BLoC state changes related to session data for the widget.
- **B. Native UI Tests (Platform permitting):**
    - [ ] iOS: XCUITests for Live Activity appearance (might be complex for dynamic data).
    - [ ] Android: Espresso tests for App Widgets (can be challenging due to `RemoteViews`). Glance testing utilities might offer some support.
- **C. Flutter Widget/Integration Tests:**
    - [ ] Test the Flutter UI that *triggers* the widget operations (if any).
    - [ ] Mock the MethodChannel/plugin to verify communication flow.
- **D. End-to-End Manual Testing:**
    - [ ] Test on physical iOS and Android devices.
    - [ ] Verify widget/Live Activity starts when a session begins.
    - [ ] Verify data updates correctly during an active session.
    - [ ] Verify widget/Live Activity ends or clears when a session stops.
    - [ ] Test app in background, app terminated (for widget persistence/update behavior).
    - [ ] Test tapping the widget/Live Activity opens the app correctly.
    - [ ] Check for battery consumption implications.
