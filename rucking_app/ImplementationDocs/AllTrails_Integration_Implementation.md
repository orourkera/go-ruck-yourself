# AllTrails Integration Implementation Guide

## 📁 Implementation File Checklist

### 🆕 NEW FILES TO CREATE

#### Platform-Specific Integration

##### iOS Share Extension
- `ios/ShareExtension/ShareViewController.swift` - Main share extension controller
- `ios/ShareExtension/Info.plist` - Share extension configuration
- `ios/ShareExtension/ShareExtension.entitlements` - App group entitlements
- `ios/Runner.xcodeproj/project.pbxproj` - Updated Xcode project (auto-modified)

##### Android Intent Handling
- `android/app/src/main/kotlin/com/goruckyourself/app/FileShareReceiver.kt` - Intent receiver for GPX files
- `android/app/src/main/kotlin/com/goruckyourself/app/MainActivity.kt` - Updated with intent handling
- `android/app/src/main/AndroidManifest.xml` - Intent filters and file associations
- `android/app/src/main/res/xml/file_provider_paths.xml` - File provider configuration

#### Flutter Route Models & Services
- `lib/core/models/route.dart` - Core route data model
- `lib/core/models/route_elevation_point.dart` - Elevation profile data
- `lib/core/models/route_point_of_interest.dart` - POI data model
- `lib/core/models/planned_ruck.dart` - Planned ruck session model
- `lib/core/services/route_service.dart` - Route API service
- `lib/core/services/planned_ruck_service.dart` - Planned ruck API service
- `lib/core/services/gpx_parser_service.dart` - GPX file parsing
- `lib/core/services/gpx_export_service.dart` - GPX file generation
- `lib/core/utils/eta_calculator.dart` - Real-time ETA calculations

#### UI Screens & Components
- `lib/features/planned_rucks/presentation/screens/my_rucks_screen.dart` - Main My Rucks section
- `lib/features/planned_rucks/presentation/screens/route_import_screen.dart` - Route import flow
- `lib/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart` - Detailed planned ruck view
- `lib/features/planned_rucks/presentation/widgets/route_map_preview.dart` - Interactive route map
- `lib/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart` - Elevation visualization
- `lib/features/planned_rucks/presentation/widgets/planned_ruck_card.dart` - Ruck list item

#### Route Session Enhancement Widgets (Conditional Overlays)
- `lib/features/planned_rucks/presentation/widgets/route_map_overlay.dart` - Live route map overlay for active sessions
- `lib/features/planned_rucks/presentation/widgets/eta_display.dart` - Real-time ETA widget
- `lib/features/planned_rucks/presentation/widgets/route_progress_indicator.dart` - Progress visualization
- `lib/features/planned_rucks/presentation/widgets/turn_guidance_hint.dart` - Navigation hints

#### State Management (BLoC)
- `lib/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart` - Main planned ruck state
- `lib/features/planned_rucks/presentation/bloc/planned_ruck_event.dart` - Bloc events
- `lib/features/planned_rucks/presentation/bloc/planned_ruck_state.dart` - Bloc states
- `lib/features/planned_rucks/presentation/bloc/route_import_bloc.dart` - Route import state

#### Route Progress Tracking (Services)
- `lib/core/services/route_progress_tracker.dart` - Track progress along planned routes
- `lib/core/services/route_navigation_service.dart` - Calculate turns and guidance

#### Backend API Endpoints
- `RuckTracker/api/routes.py` - Routes CRUD API
- `RuckTracker/api/planned_rucks.py` - Planned rucks API
- `RuckTracker/api/route_analytics.py` - Route analytics API
- `RuckTracker/api/gpx_import.py` - GPX import processing
- `RuckTracker/api/gpx_export.py` - GPX export generation

#### Database
- `create_routes_tables.sql` - ✅ Database schema migration (CREATED)

### 🔄 EXISTING FILES TO MODIFY

#### App Configuration
- `lib/main.dart` - Add planned ruck dependencies and platform channels
- `lib/app.dart` - Add route handling and My Rucks navigation
- `pubspec.yaml` - Add new dependencies (xml, file_picker, etc.)

##### iOS Configuration Updates
- `ios/Runner/Info.plist` - Add file type associations and URL schemes
- `ios/Runner/Runner.entitlements` - Add app group capabilities

##### Android Configuration Updates
- `android/app/src/main/AndroidManifest.xml` - Add intent filters, file associations, permissions
- `android/app/build.gradle` - Update for file provider and intent handling

#### Navigation & Routing
- `lib/core/navigation/app_router.dart` - Add My Rucks and route import routes
- `lib/features/home/presentation/screens/home_screen.dart` - Add My Rucks tab/section
- `lib/shared/widgets/bottom_navigation.dart` - Update navigation structure

#### Session Management Integration
- `lib/features/ruck_session/presentation/bloc/active_session_bloc.dart` - Add route data and progress to existing session state
- `lib/features/ruck_session/presentation/screens/active_session_screen.dart` - ✨ ENHANCE existing screen with conditional route widgets
- `lib/features/ruck_session/presentation/screens/manual_ruck_creation_screen.dart` - Add route import integration
- `lib/features/ruck_session/domain/models/ruck_session.dart` - Add route_id and planned_ruck_id fields
- `lib/features/ruck_session/data/repositories/session_repository.dart` - Add route linking

#### Backend Integration
- `RuckTracker/app.py` - Register new API routes
- `RuckTracker/requirements.txt` - Add GPX processing dependencies
- `RuckTracker/models/__init__.py` - Export new models

#### Database Schema Updates
- Existing `ruck_session` table - Add route_id, planned_ruck_id, is_guided_session columns

---

## ✅ Implementation Task Checklist

### 🏗️ **Phase 1: Foundation & Backend (Week 1-2)**

#### Database & Schema
- [x] **1.1** Run `create_routes_tables.sql` migration on development database
- [ ] **1.2** Run `create_routes_tables.sql` migration on production database
- [ ] **1.3** Test database constraints and RLS policies
- [ ] **1.4** Verify PostGIS extension is working for geographic queries

#### Backend Models & API
- [x] **2.1** Create `RuckTracker/models/route.py` - Route model
- [x] **2.2** Create `RuckTracker/models/planned_ruck.py` - Planned ruck model  
- [x] **2.3** Create `RuckTracker/models/route_analytics.py` - Analytics model
- [x] **2.4** Update `RuckTracker/models/__init__.py` - Export new models
- [x] **2.5** Create `RuckTracker/api/routes.py` - Routes CRUD API
- [x] **2.6** Create `RuckTracker/api/planned_rucks.py` - Planned rucks API
- [x] **2.7** Create `RuckTracker/services/route_analytics_service.py` - Analytics service
- [x] **2.8** Create `RuckTracker/api/gpx_import.py` - GPX parsing endpoint
- [x] **2.9** Create `RuckTracker/api/gpx_export.py` - GPX generation endpoint
- [x] **2.10** Update `RuckTracker/app.py` - Register all new API routes
- [x] **2.11** No additional dependencies needed - uses Python standard library
- [ ] **2.12** Test all API endpoints with Postman/curl

### 📱 **Phase 2: Flutter Models & Services (Week 2-3)**

#### Core Models
- [ ] **3.1** Create `lib/core/models/route.dart` - Route data model
- [ ] **3.2** Create `lib/core/models/route_elevation_point.dart` - Elevation model
- [ ] **3.3** Create `lib/core/models/route_point_of_interest.dart` - POI model
- [ ] **3.4** Create `lib/core/models/planned_ruck.dart` - Planned ruck model
- [ ] **3.5** Update `lib/features/ruck_session/domain/models/ruck_session.dart` - Add route fields

#### Core Services
- [ ] **4.1** Create `lib/core/services/route_service.dart` - Route API service
- [ ] **4.2** Create `lib/core/services/planned_ruck_service.dart` - Planned ruck API service
- [ ] **4.3** Create `lib/core/services/gpx_parser_service.dart` - GPX file parsing
- [ ] **4.4** Create `lib/core/services/gpx_export_service.dart` - GPX file generation
- [ ] **4.5** Create `lib/core/services/route_progress_tracker.dart` - Route progress tracking
- [ ] **4.6** Create `lib/core/services/route_navigation_service.dart` - Turn guidance
- [ ] **4.7** Create `lib/core/utils/eta_calculator.dart` - Real-time ETA calculations
- [ ] **4.8** Update `lib/features/ruck_session/data/repositories/session_repository.dart` - Route linking

### 🛠️ **Phase 3: Platform Integration (Week 3-4)**

#### iOS Share Extension
- [ ] **5.1** Create `ios/ShareExtension/ShareViewController.swift` - Main controller
- [ ] **5.2** Create `ios/ShareExtension/Info.plist` - Extension configuration
- [ ] **5.3** Create `ios/ShareExtension/ShareExtension.entitlements` - App groups
- [ ] **5.4** Update `ios/Runner/Info.plist` - File associations and URL schemes
- [ ] **5.5** Update `ios/Runner/Runner.entitlements` - App group capabilities
- [ ] **5.6** Update Xcode project configuration
- [ ] **5.7** Test iOS share extension with GPX files

#### Android Intent Handling
- [ ] **6.1** Create `android/app/src/main/kotlin/.../FileShareReceiver.kt` - Intent receiver
- [ ] **6.2** Update `android/app/src/main/kotlin/.../MainActivity.kt` - Intent handling
- [ ] **6.3** Update `android/app/src/main/AndroidManifest.xml` - Intent filters
- [ ] **6.4** Create `android/app/src/main/res/xml/file_provider_paths.xml` - File provider
- [ ] **6.5** Update `android/app/build.gradle` - File provider config
- [ ] **6.6** Test Android intent handling with GPX files

#### App Configuration
- [ ] **7.1** Update `pubspec.yaml` - Add new dependencies (xml, file_picker, etc.)
- [ ] **7.2** Update `lib/main.dart` - Add planned ruck dependencies and platform channels
- [ ] **7.3** Update `lib/app.dart` - Add route handling and navigation

### 🎨 **Phase 4: UI Components & Screens (Week 4-5)**

#### My Rucks Section
- [ ] **8.1** Create `lib/features/planned_rucks/presentation/screens/my_rucks_screen.dart` - Main screen
- [ ] **8.2** Create `lib/features/planned_rucks/presentation/screens/route_import_screen.dart` - Import flow
- [ ] **8.3** Create `lib/features/planned_rucks/presentation/screens/planned_ruck_detail_screen.dart` - Detail view
- [ ] **8.4** Create `lib/features/planned_rucks/presentation/widgets/planned_ruck_card.dart` - List item
- [ ] **8.5** Create `lib/features/planned_rucks/presentation/widgets/route_map_preview.dart` - Map widget
- [ ] **8.6** Create `lib/features/planned_rucks/presentation/widgets/elevation_profile_chart.dart` - Elevation chart

#### Active Session Enhancements
- [ ] **9.1** Create `lib/features/planned_rucks/presentation/widgets/route_map_overlay.dart` - Live map overlay
- [ ] **9.2** Create `lib/features/planned_rucks/presentation/widgets/eta_display.dart` - ETA widget
- [ ] **9.3** Create `lib/features/planned_rucks/presentation/widgets/route_progress_indicator.dart` - Progress bar
- [ ] **9.4** Create `lib/features/planned_rucks/presentation/widgets/turn_guidance_hint.dart` - Navigation hints
- [ ] **9.5** Update `lib/features/ruck_session/presentation/screens/active_session_screen.dart` - Add conditional route widgets

### 🧠 **Phase 5: State Management (Week 5-6)**

#### BLoC Implementation
- [ ] **10.1** Create `lib/features/planned_rucks/presentation/bloc/planned_ruck_event.dart` - Events
- [ ] **10.2** Create `lib/features/planned_rucks/presentation/bloc/planned_ruck_state.dart` - States
- [ ] **10.3** Create `lib/features/planned_rucks/presentation/bloc/planned_ruck_bloc.dart` - Main BLoC
- [ ] **10.4** Create `lib/features/planned_rucks/presentation/bloc/route_import_bloc.dart` - Import BLoC
- [ ] **10.5** Update `lib/features/ruck_session/presentation/bloc/active_session_bloc.dart` - Add route data and progress

#### Navigation Integration
- [ ] **11.1** Update `lib/core/navigation/app_router.dart` - Add My Rucks routes
- [ ] **11.2** Update `lib/features/home/presentation/screens/home_screen.dart` - Add My Rucks access
- [ ] **11.3** Update `lib/shared/widgets/bottom_navigation.dart` - Navigation updates
- [ ] **11.4** Update `lib/features/ruck_session/presentation/screens/manual_ruck_creation_screen.dart` - Route import

### 🧪 **Phase 6: Testing & Polish (Week 6-7)**

#### Integration Testing
- [ ] **12.1** Test GPX import flow end-to-end (iOS)
- [ ] **12.2** Test GPX import flow end-to-end (Android)
- [ ] **12.3** Test route-guided session with real GPS data
- [ ] **12.4** Test GPX export and sharing
- [ ] **12.5** Test planned ruck creation and management
- [ ] **12.6** Test ETA calculations with various scenarios
- [ ] **12.7** Test database performance with large route datasets

#### User Experience Polish
- [ ] **13.1** Add loading states for all API calls
- [ ] **13.2** Add error handling and user-friendly messages
- [ ] **13.3** Add empty states for My Rucks section
- [ ] **13.4** Optimize map rendering performance
- [ ] **13.5** Add haptic feedback for route milestones
- [ ] **13.6** Add accessibility labels and support
- [ ] **13.7** Final UI polish and design review

### 🚀 **Phase 7: Deployment (Week 7-8)**

#### Production Deployment
- [ ] **14.1** Deploy database migration to production
- [ ] **14.2** Deploy backend APIs to production
- [ ] **14.3** Test production API endpoints
- [ ] **14.4** Submit iOS app update for review
- [ ] **14.5** Submit Android app update for review
- [ ] **14.6** Prepare release notes and marketing materials
- [ ] **14.7** Monitor launch metrics and user feedback

---

### 📊 **Progress Tracking**

**Overall Progress:** 0/97 tasks completed (0%)

**Phase Breakdown:**
- 🏗️ **Phase 1 (Foundation):** 0/16 tasks (0%)
- 📱 **Phase 2 (Flutter):** 0/13 tasks (0%) 
- 🛠️ **Phase 3 (Platform):** 0/16 tasks (0%)
- 🎨 **Phase 4 (UI):** 0/11 tasks (0%)
- 🧠 **Phase 5 (State):** 0/9 tasks (0%)
- 🧪 **Phase 6 (Testing):** 0/13 tasks (0%)
- 🚀 **Phase 7 (Deploy):** 0/7 tasks (0%)

**Estimated Timeline:** 7-8 weeks with 2 developers

---

## 🧪 **Strategic Testing Checkpoints**

### 🏁 **Checkpoint 1: Backend Foundation (End of Week 1)**
**Test After Completing:** Tasks 1.1 - 2.12

#### 🔍 **What to Test:**
- [ ] **Database Schema Validation**
  - All 5 new tables created successfully
  - RLS policies working (users can only see their own data)
  - Foreign key constraints enforced
  - PostGIS geographic queries functional

- [ ] **API Endpoint Testing** (via Postman/curl)
  - `POST /api/routes` - Create new route
  - `GET /api/routes/{id}` - Retrieve route details
  - `POST /api/planned-rucks` - Create planned ruck
  - `GET /api/planned-rucks?user_id={id}` - List user's planned rucks
  - `POST /api/gpx-import` - Parse GPX file and extract route data
  - `GET /api/gpx-export/{route_id}` - Generate GPX from route

#### 🎯 **Success Criteria:**
- ✅ All API endpoints return proper HTTP status codes
- ✅ Database constraints prevent invalid data
- ✅ RLS policies block unauthorized access
- ✅ GPX parsing correctly extracts coordinates and elevation

---

### 🏁 **Checkpoint 2: Flutter Data Layer (End of Week 2)**
**Test After Completing:** Tasks 3.1 - 4.8

#### 🔍 **What to Test:**
- [ ] **Model Serialization**
  - Route.fromJson() / .toJson() with real API data
  - PlannedRuck.fromJson() / .toJson() with real API data
  - GPX parsing service with real AllTrails files

- [ ] **Service Integration**
  - RouteService.createRoute() calls API successfully
  - PlannedRuckService.getMyRucks() returns user's data
  - GPXParserService.parseFile() extracts correct data
  - ETACalculator.calculateETA() with various scenarios

#### 🎯 **Success Criteria:**
- ✅ All models serialize/deserialize correctly
- ✅ Services handle API errors gracefully
- ✅ GPX parsing works with real AllTrails files
- ✅ ETA calculations are reasonable and consistent

---

### 🏁 **Checkpoint 3: Platform Integration (End of Week 3)**
**Test After Completing:** Tasks 5.1 - 7.3

#### 🔍 **What to Test:**
- [ ] **iOS Share Extension**
  - Share GPX file from AllTrails app → Your app
  - Extension receives file and passes to main app
  - Deep linking works from extension to route import

- [ ] **Android Intent Handling**
  - Share GPX file from AllTrails app → Your app
  - Intent receiver processes file correctly
  - File associations work (open GPX files directly)

- [ ] **Cross-Platform File Handling**
  - Same GPX file works on both platforms
  - File validation and error handling

#### 🎯 **Success Criteria:**
- ✅ Both platforms can receive GPX files from other apps
- ✅ File data correctly transferred to main app
- ✅ Error handling for corrupted/invalid files
- ✅ User sees appropriate feedback during import process

---

### 🏁 **Checkpoint 4: My Rucks MVP (End of Week 4)**
**Test After Completing:** Tasks 8.1 - 8.6

#### 🔍 **What to Test:**
- [ ] **My Rucks Screen**
  - Empty state when no planned rucks
  - List displays planned rucks correctly
  - Tabs (Planned, Today, Completed) work
  - Route map previews render properly

- [ ] **Route Import Flow**
  - Import GPX file creates route in database
  - Route data displays correctly (distance, elevation)
  - User can save as planned ruck
  - Elevation profile chart displays properly

#### 🎯 **Success Criteria:**
- ✅ Users can import and view routes
- ✅ My Rucks section is fully navigable
- ✅ Route visualizations are accurate
- ✅ Data persists between app sessions

---

### 🏁 **Checkpoint 5: Enhanced Active Session (End of Week 5)**
**Test After Completing:** Tasks 9.1 - 10.5

#### 🔍 **What to Test:**
- [ ] **Route-Guided Session**
  - Start planned ruck → enhanced active session
  - Route overlay displays on map
  - Real-time progress tracking works
  - ETA updates dynamically based on pace

- [ ] **Preserved Functionality**
  - Normal sessions (no route) work exactly as before
  - All existing session features functional
  - No regressions in session completion flow

- [ ] **Route Progress Features**
  - Turn guidance hints appear at appropriate times
  - Elevation profile shows current position
  - Distance to waypoints calculated correctly

#### 🎯 **Success Criteria:**
- ✅ Route-guided sessions provide real-time navigation
- ✅ Normal sessions completely unchanged
- ✅ ETA calculations are accurate and responsive
- ✅ No performance impact on session tracking

---

### 🏁 **Checkpoint 6: End-to-End Integration (End of Week 6)**
**Test After Completing:** Tasks 11.1 - 12.7

#### 🔍 **What to Test:**
- [ ] **Complete User Journey**
  - Import route from AllTrails → Plan ruck → Start guided session → Complete → Export to AllTrails
  - Test on both iOS and Android devices
  - Test with various GPX file formats and sizes

- [ ] **Edge Cases & Error Handling**
  - Poor GPS signal during guided session
  - Large route files (50+ miles)
  - Corrupted or invalid GPX files
  - Network interruptions during import/export

#### 🎯 **Success Criteria:**
- ✅ Complete end-to-end flow works smoothly
- ✅ Error cases handled gracefully with user feedback
- ✅ Performance acceptable with large datasets
- ✅ Cross-platform consistency maintained

---

### 📝 **Testing Strategy Tips:**

**⚡ Quick Testing Commands:**
```bash
# Database testing
psql -h localhost -d rucking_app_dev -c "SELECT COUNT(*) FROM routes;"

# API testing
curl -X POST http://localhost:5000/api/routes \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Route","distance_km":5.0}'

# Flutter testing
flutter test lib/core/models/
flutter test lib/core/services/
```

**🛠️ Test Data Sources:**
- **Sample GPX files** from AllTrails (various trail types)
- **Mock route data** for consistent testing
- **Edge case files** (very large, corrupted, minimal data)

**📊 Success Metrics:**
- **Import time** < 5 seconds for typical routes
- **ETA accuracy** within 10% of actual completion time
- **Memory usage** no significant increase during route sessions
- **Battery impact** minimal additional drain for guided sessions

---

## 🌐 Cross-Platform Compatibility

### ✅ YES - This works on both iOS and Android!

**Core Integration Methods by Platform:**

#### iOS Implementation
- **Share Extension** - Receives GPX files from AllTrails via iOS share sheet
- **App Groups** - Shared container for data exchange between main app and extension
- **File Associations** - Opens GPX files directly in the app
- **URL Schemes** - Deep linking from AllTrails app

#### Android Implementation  
- **Intent Filters** - Receives GPX files via Android's sharing system
- **File Provider** - Secure file access and sharing
- **MIME Type Associations** - Opens GPX files in the app
- **Custom Intent Actions** - Deep linking from AllTrails app

#### Shared Flutter Implementation
- **All UI components** work identically on both platforms
- **GPX parsing/export** uses same Dart code
- **Route management** uses same BLoC architecture  
- **API integration** identical across platforms
- **Database schema** platform-agnostic

### Import/Export Flow Comparison

| Feature | iOS | Android |
|---------|-----|----------|
| **Import GPX** | Share Extension | Intent Filter |
| **File Association** | Info.plist | AndroidManifest.xml |
| **Deep Linking** | URL Schemes | Intent Actions |
| **Data Storage** | App Groups | Internal Storage |
| **Export GPX** | System Share Sheet | Intent Chooser |
| **File Access** | Document Provider | File Provider |

**Result:** Users get the same great experience regardless of platform! 🎯

---

## 🎯 Enhanced Session Approach (Preserves Existing Functionality)

### ✅ **Key Decision: Enhance, Don't Replace**

Instead of creating a new "guided session" screen, we enhance the existing `active_session_screen.dart` with **conditional route features**:

#### **When `routeId == null` (Normal Session):**
- ✅ **Exact same experience as today**
- ✅ All existing functionality preserved
- ✅ No visual changes whatsoever
- ✅ Zero regression risk

#### **When `routeId != null` (Route-Guided Session):**
- ✅ **All existing functionality PLUS:**
  - Route map overlay with live progress
  - Real-time ETA calculations
  - Distance to waypoints
  - Turn-by-turn guidance hints
  - Elevation profile progress

### 🏗️ **Implementation Strategy:**

```dart
// Enhanced ActiveSessionBloc state
class ActiveSessionRunning {
  final RuckSession session;
  final Route? activeRoute;     // NEW - optional
  final RouteProgress? progress; // NEW - optional
  // ... all existing fields remain unchanged
}

// Conditional UI in active_session_screen.dart
if (state.activeRoute != null) {
  RouteMapOverlay(route: state.activeRoute!),
  ETADisplay(progress: state.progress!),
  RouteProgressIndicator(progress: state.progress!),
}
```

### 🎯 **Benefits:**
- **Zero Learning Curve** - Same familiar screen
- **No Code Duplication** - Reuse all session logic
- **Easy Testing** - Enhanced features are purely additive
- **Consistent UX** - One screen, enhanced capabilities

---

## Overview
This document outlines the technical implementation for seamless bi-directional integration between the Rucking App and AllTrails, enabling users to:

1. **Import Completed Activities** - Convert completed AllTrails hikes to ruck sessions using the existing manual ruck creation flow
2. **Import Trail Routes** - Plan future rucks using AllTrails trail data
3. **Export Rucking Sessions** - Share completed rucks to AllTrails community

The primary use case is importing completed activities where users hiked with a ruck and want to convert the session to proper ruck metrics by leveraging the existing manual session creation workflow.

## Integration Architecture

### Core Integration Methods
1. **iOS Share Extension** - For importing AllTrails activities and routes
2. **Document Provider Extension** - For file system integration  
3. **System Share Sheet** - For exporting to AllTrails
4. **File Association** - For "Open In" functionality
5. **Manual Ruck Creation Flow Integration** - Reuse existing UI with pre-populated data

### Import Types Supported

#### 1. Completed Activity Import (Primary Use Case)
**What GPX contains:**
- ✅ Full GPS track with timestamps
- ✅ Elevation profile with time data
- ✅ Speed/pace at each point
- ✅ Total duration and distance
- ✅ Elevation gain/loss
- ❌ Ruck weight (user provides via manual form)
- ❌ Body weight (user provides via manual form)

**Integration workflow:**
1. User exports completed AllTrails hike as GPX
2. Shares to Rucking App via share sheet
3. App parses GPX and extracts performance data
4. **Navigates to existing manual ruck creation page**
5. **Pre-populates form with imported data**
6. User completes ruck-specific fields using familiar UI
7. Submits via existing manual ruck creation logic

#### 2. Route-Only Import (Planned Rucks)
**What GPX contains:**
- ✅ Complete trail path and waypoints
- ✅ Static elevation profile with terrain data
- ✅ Total distance and estimated difficulty
- ✅ Points of interest and trail markers
- ❌ No timing or performance data

**Integration workflow (Planning Phase):**
1. User finds interesting trail on AllTrails (at home, during week)
2. Exports route as GPX from AllTrails website
3. Shares to Rucking App via iOS share sheet
4. **Navigates to "Save as Planned Ruck" page**
5. **Route displayed with detailed planning info:**
   - Interactive map with elevation profile
   - Projected completion time based on ruck weight & fitness level
   - Calorie burn estimation
   - Difficulty assessment for rucking
   - Water/rest stop recommendations
   - Weather considerations
6. **User configures planned ruck:**
   - Sets planned date/time
   - Chooses ruck weight and gear
   - Adds personal notes
   - Sets safety preferences
7. **Saves to "My Rucks" section** for later execution

**Execution workflow (At Trailhead):**
1. **Open "My Rucks"** → Browse planned routes
2. **Select planned ruck** → "Cascade Falls - Planned for Today"
3. **Review route details** → Last-minute adjustments
4. **Start Guided Session** → Begin real-time tracking
5. **Real-time navigation** with dynamic progress tracking:
   - Current position on route map
   - **Live ETA calculation** based on current pace + remaining distance
   - **Adaptive time projection** accounting for elevation changes ahead
   - **Performance comparison** vs initial projection
   - **Dynamic difficulty adjustment** based on actual vs expected pace

---

## 1. iOS Share Extension Implementation

### 1.1 Create Share Extension Target

```bash
# In Xcode
File → New → Target → Share Extension
```

### 1.2 Share Extension Configuration

**Info.plist Configuration:**
```xml
<!-- ios/ShareExtension/Info.plist -->
<key>NSExtension</key>
<dict>
    <key>NSExtensionActivationRule</key>
    <dict>
        <key>NSExtensionActivationSupportsFileWithMaxCount</key>
        <integer>1</integer>
        <key>NSExtensionActivationSupportsFileWithMinCount</key>
        <integer>1</integer>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>ShareViewController</string>
</dict>

<!-- Supported file types -->
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.topografix.gpx</string>
        <key>UTTypeDescription</key>
        <string>GPX Route File</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.xml</string>
            <string>public.data</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>gpx</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>application/gpx+xml</string>
            </array>
        </dict>
    </dict>
</array>
```

### 1.3 Share Extension View Controller

```swift
// ios/ShareExtension/ShareViewController.swift
import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    
    override func isContentValid() -> Bool {
        return true
    }
    
    override func didSelectPost() {
        if let item = extensionContext?.inputItems.first as? NSExtensionItem {
            if let attachments = item.attachments {
                for attachment in attachments {
                    if attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                        attachment.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { (data, error) in
                            if let fileData = data as? Data {
                                self.processGPXFile(fileData)
                            }
                        }
                    }
                }
            }
        }
        
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func processGPXFile(_ data: Data) {
        // Save to shared container for main app to process
        let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.yourcompany.ruckingapp"
        )
        
        if let containerURL = sharedContainer {
            let fileURL = containerURL.appendingPathComponent("imported_route.gpx")
            
            do {
                try data.write(to: fileURL)
                
                // Notify main app via UserDefaults
                let userDefaults = UserDefaults(suiteName: "group.com.yourcompany.ruckingapp")
                userDefaults?.set(Date(), forKey: "lastRouteImport")
                userDefaults?.set(fileURL.path, forKey: "pendingRouteImport")
                
                // Open main app
                let url = URL(string: "ruckingapp://import-route")!
                _ = self.openURL(url)
            } catch {
                // Handle error
                print("Failed to save GPX file: \(error)")
            }
        }
    }
    
    @objc private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                return application.perform(#selector(openURL(_:)), with: url) != nil
            }
            responder = responder?.next
        }
        return false
    }
}
```

---

## 2. Main App Integration

### 2.1 App Group Configuration

**Entitlements:**
```xml
<!-- ios/Runner/Runner.entitlements -->
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.yourcompany.ruckingapp</string>
</array>
```

### 2.2 URL Scheme Handler

**Info.plist:**
```xml
<!-- ios/Runner/Info.plist -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourcompany.ruckingapp.import</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>ruckingapp</string>
        </array>
    </dict>
</array>

<!-- Document Types for "Open In" -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>GPX Route</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>gpx</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.topografix.gpx</string>
        </array>
    </dict>
</array>
```

### 2.3 Flutter Deep Link Handler

```dart
// lib/core/services/deep_link_service.dart
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();
  
  static Future<void> initialize() async {
    // Handle URL schemes
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
    
    // Check for initial link when app starts
    final initialUri = await _appLinks.getInitialAppLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }
  }
  
  static void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'ruckingapp') {
      switch (uri.host) {
        case 'import-route':
          RouteImportService.checkForPendingImport();
          break;
      }
    }
  }
}
```

### 2.4 Route Import Service

```dart
// lib/core/services/route_import_service.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class RouteImportService {
  static const String _groupIdentifier = 'group.com.yourcompany.ruckingapp';
  
  static Future<void> checkForPendingImport() async {
    final prefs = await SharedPreferences.getInstance();
    final lastImport = prefs.getString('lastRouteImport');
    final pendingPath = prefs.getString('pendingRouteImport');
    
    if (lastImport != null && pendingPath != null) {
      final file = File(pendingPath);
      if (await file.exists()) {
        final gpxData = await file.readAsString();
        await _showImportDialog(gpxData);
        
        // Clean up
        await file.delete();
        await prefs.remove('pendingRouteImport');
        await prefs.remove('lastRouteImport');
      }
    }
  }
  
  static Future<void> _showImportDialog(String gpxData) async {
    final gpxTrack = await GPXParser.parse(gpxData);
    
    // Determine if this is a completed activity or route-only
    final isCompletedActivity = gpxTrack.hasTimestamps;
    
    if (isCompletedActivity) {
      // Navigate to manual ruck creation with pre-populated data
      await _navigateToManualRuckCreation(gpxTrack);
    } else {
      // Navigate to route planning with trail data
      await _navigateToRoutePlanning(gpxTrack);
    }
  }
  
  static Future<void> _navigateToManualRuckCreation(GPXTrack track) async {
    // Extract performance data from completed activity
    final activityData = ActivityData(
      name: track.name ?? 'Imported from AllTrails',
      startTime: track.startTime!,
      endTime: track.endTime!,
      totalDistance: track.totalDistance,
      totalDuration: track.duration!,
      elevationGain: track.elevationGain,
      averagePace: track.averagePace,
      trackPoints: track.trackPoints,
      route: track.route,
    );
    
    // Navigate to existing manual ruck creation page with pre-populated data
    final context = NavigationService.navigatorKey.currentContext!;
    Navigator.pushNamed(
      context, 
      '/create-manual-ruck',
      arguments: ManualRuckCreationArgs(
        importedActivityData: activityData,
        isImport: true,
      ),
    );
  }
  
  static Future<void> _navigateToRoutePlanning(GPXTrack track) async {
    // Extract route data for future planning
    final routeData = RouteData(
      name: track.name ?? 'Imported Trail',
      distance: track.totalDistance,
      elevationGain: track.elevationGain,
      waypoints: track.waypoints,
      route: track.route,
      elevationProfile: track.elevationProfile,
      pointsOfInterest: track.pointsOfInterest,
      trailDifficulty: track.estimatedDifficulty,
    );
    
    // Navigate to planned ruck creation page
    final context = NavigationService.navigatorKey.currentContext!;
    Navigator.pushNamed(
      context,
      '/create-planned-ruck',
      arguments: PlannedRuckCreationArgs(
        importedRouteData: routeData,
        isImport: true,
        source: 'AllTrails',
      ),
    );
  }
}
```

---

## 3. Manual Ruck Creation Integration

### 3.1 Data Models for Import

```dart
// lib/core/models/import_data.dart
class ActivityData {
  final String name;
  final DateTime startTime;
  final DateTime endTime;
  final double totalDistance;
  final Duration totalDuration;
  final double elevationGain;
  final double averagePace;
  final List<TrackPoint> trackPoints;
  final List<LatLng> route;
  
  const ActivityData({
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.totalDistance,
    required this.totalDuration,
    required this.elevationGain,
    required this.averagePace,
    required this.trackPoints,
    required this.route,
  });
}

class RouteData {
  final String name;
  final double distance;
  final double elevationGain;
  final List<LatLng> waypoints;
  final List<LatLng> route;
  final List<ElevationPoint> elevationProfile;
  final List<PointOfInterest> pointsOfInterest;
  final TrailDifficulty trailDifficulty;
  
  const RouteData({
    required this.name,
    required this.distance,
    required this.elevationGain,
    required this.waypoints,
    required this.route,
    required this.elevationProfile,
    required this.pointsOfInterest,
    required this.trailDifficulty,
  });
}

class ElevationPoint {
  final double distance; // Distance along route
  final double elevation;
  final String? terrain; // Trail surface type
  
  const ElevationPoint({
    required this.distance,
    required this.elevation,
    this.terrain,
  });
}

class PointOfInterest {
  final LatLng location;
  final String name;
  final String type; // 'water', 'rest', 'viewpoint', 'hazard'
  final String? description;
  
  const PointOfInterest({
    required this.location,
    required this.name,
    required this.type,
    this.description,
  });
}

enum TrailDifficulty { easy, moderate, hard, extreme }

class ManualRuckCreationArgs {
  final ActivityData? importedActivityData;
  final bool isImport;
  
  const ManualRuckCreationArgs({
    this.importedActivityData,
    this.isImport = false,
  });
}

class PlannedRuckCreationArgs {
  final RouteData? importedRouteData;
  final bool isImport;
  final String? source; // 'AllTrails', 'manual', etc.
  
  const PlannedRuckCreationArgs({
    this.importedRouteData,
    this.isImport = false,
    this.source,
  });
}

class PlannedRuck {
  final String id;
  final String name;
  final String? description;
  final RouteData routeData;
  final DateTime? plannedDate;
  final double plannedRuckWeight;
  final RuckDifficulty plannedDifficulty;
  final bool safetyTrackingEnabled;
  final bool weatherAlertsEnabled;
  final String? notes;
  final DateTime createdAt;
  final String source; // 'AllTrails', 'manual', 'custom'
  final RuckStatus status; // planned, in_progress, completed, cancelled
  
  // Calculated fields
  final double estimatedDuration; // hours
  final double estimatedCalories;
  final String estimatedDifficultyDescription;
  
  const PlannedRuck({
    required this.id,
    required this.name,
    this.description,
    required this.routeData,
    this.plannedDate,
    required this.plannedRuckWeight,
    required this.plannedDifficulty,
    this.safetyTrackingEnabled = true,
    this.weatherAlertsEnabled = true,
    this.notes,
    required this.createdAt,
    required this.source,
    this.status = RuckStatus.planned,
    required this.estimatedDuration,
    required this.estimatedCalories,
    required this.estimatedDifficultyDescription,
  });
  
  bool get isPlannedForToday {
    if (plannedDate == null) return false;
    final today = DateTime.now();
    return plannedDate!.year == today.year &&
           plannedDate!.month == today.month &&
           plannedDate!.day == today.day;
  }
  
  bool get isOverdue {
    if (plannedDate == null || status != RuckStatus.planned) return false;
    return plannedDate!.isBefore(DateTime.now());
  }
}

enum RuckStatus { planned, in_progress, completed, cancelled }
```

### 3.2 My Rucks Section Implementation

```dart
// lib/features/planned_rucks/presentation/screens/my_rucks_screen.dart
class MyRucksScreen extends StatefulWidget {
  @override
  State<MyRucksScreen> createState() => _MyRucksScreenState();
}

class _MyRucksScreenState extends State<MyRucksScreen> {
  List<PlannedRuck> _plannedRucks = [];
  List<PlannedRuck> _completedRucks = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadRucks();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Rucks'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _createCustomRuck,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: 'Planned (${_plannedRucks.length})'),
                      Tab(text: 'Today'),
                      Tab(text: 'Completed'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPlannedRucksTab(),
                        _buildTodayTab(),
                        _buildCompletedRucksTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildPlannedRucksTab() {
    final plannedRucks = _plannedRucks.where((r) => r.status == RuckStatus.planned).toList();
    
    if (plannedRucks.isEmpty) {
      return _buildEmptyState(
        'No Planned Rucks',
        'Import routes from AllTrails or create custom routes to get started.',
        Icons.route,
        _showImportOptions,
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: plannedRucks.length,
      itemBuilder: (context, index) {
        final ruck = plannedRucks[index];
        return _buildPlannedRuckCard(ruck);
      },
    );
  }
  
  Widget _buildTodayTab() {
    final todayRucks = _plannedRucks.where((r) => r.isPlannedForToday).toList();
    
    if (todayRucks.isEmpty) {
      return _buildEmptyState(
        'No Rucks Planned for Today',
        'Schedule a ruck or start one of your planned routes.',
        Icons.today,
        _showPlannedRucks,
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: todayRucks.length,
      itemBuilder: (context, index) {
        final ruck = todayRucks[index];
        return _buildTodayRuckCard(ruck);
      },
    );
  }
  
  Widget _buildPlannedRuckCard(PlannedRuck ruck) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _viewRuckDetails(ruck),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with source badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ruck.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildSourceBadge(ruck.source),
                ],
              ),
              
              SizedBox(height: 8),
              
              // Stats row
              Row(
                children: [
                  _buildStatChip(
                    Icons.straighten,
                    '${ruck.routeData.distance.toStringAsFixed(1)} km',
                  ),
                  SizedBox(width: 8),
                  _buildStatChip(
                    Icons.schedule,
                    '${ruck.estimatedDuration.toStringAsFixed(1)}h',
                  ),
                  SizedBox(width: 8),
                  _buildStatChip(
                    Icons.trending_up,
                    '${ruck.routeData.elevationGain.toStringAsFixed(0)}m ↗',
                  ),
                ],
              ),
              
              SizedBox(height: 8),
              
              // Planned date and difficulty
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  SizedBox(width: 4),
                  Text(
                    ruck.plannedDate != null
                        ? DateFormat('MMM d, y').format(ruck.plannedDate!)
                        : 'No date set',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Spacer(),
                  _buildDifficultyChip(ruck.plannedDifficulty),
                ],
              ),
              
              if (ruck.isOverdue)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        'Overdue',
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTodayRuckCard(PlannedRuck ruck) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: Colors.green[50],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ruck.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildSourceBadge(ruck.source),
              ],
            ),
            
            SizedBox(height: 12),
            
            // Route preview with stats
            Row(
              children: [
                _buildStatChip(Icons.straighten, '${ruck.routeData.distance.toStringAsFixed(1)} km'),
                SizedBox(width: 8),
                _buildStatChip(Icons.schedule, '~${ruck.estimatedDuration.toStringAsFixed(1)}h'),
                SizedBox(width: 8),
                _buildStatChip(Icons.fitness_center, '${ruck.plannedRuckWeight.toStringAsFixed(0)}kg'),
              ],
            ),
            
            SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startGuidedRuck(ruck),
                    icon: Icon(Icons.play_arrow),
                    label: Text('Start Guided Ruck'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _viewRuckDetails(ruck),
                  child: Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatChip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSourceBadge(String source) {
    Color color;
    String label;
    
    switch (source) {
      case 'AllTrails':
        color = Colors.green;
        label = 'AllTrails';
        break;
      case 'custom':
        color = Colors.blue;
        label = 'Custom';
        break;
      default:
        color = Colors.grey;
        label = source;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  void _startGuidedRuck(PlannedRuck ruck) {
    Navigator.pushNamed(
      context,
      '/guided-ruck-session',
      arguments: GuidedRuckSessionArgs(
        plannedRuck: ruck,
        routeData: ruck.routeData,
      ),
    );
  }
  
  void _viewRuckDetails(PlannedRuck ruck) {
    Navigator.pushNamed(
      context,
      '/planned-ruck-details',
      arguments: ruck,
    );
  }
  
  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ImportOptionsSheet(),
    );
  }
}

class GuidedRuckSessionArgs {
  final PlannedRuck plannedRuck;
  final RouteData routeData;
  
  const GuidedRuckSessionArgs({
    required this.plannedRuck,
    required this.routeData,
  });
}
```

### 3.2 Enhanced Manual Ruck Creation Page

```dart
// lib/features/ruck_session/presentation/screens/manual_ruck_creation_screen.dart
class ManualRuckCreationScreen extends StatefulWidget {
  final ManualRuckCreationArgs? args;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getPageTitle()),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show import preview if applicable
              if (widget.args?.isImport == true && widget.args?.importedActivityData != null)
                _buildImportPreview(),
              
              // Existing manual ruck creation form fields
              _buildSessionDetailsSection(),
              _buildPerformanceSection(),
              _buildRuckingDetailsSection(),
              _buildNotesSection(),
              
              SizedBox(height: 32),
              
              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _createRuckSession,
                  child: Text(_getSubmitButtonText()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildImportPreview() {
    final data = widget.args!.importedActivityData!;
    
    return Card(
      margin: EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Imported from AllTrails',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              data.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 8),
            Row(
              children: [
                _buildStatChip('${data.totalDistance.toStringAsFixed(1)} km'),
                SizedBox(width: 8),
                _buildStatChip(_formatDuration(data.totalDuration)),
                SizedBox(width: 8),
                _buildStatChip('${data.elevationGain.toStringAsFixed(0)}m ↗'),
              ],
            ),
            SizedBox(height: 8),
            Text(
              '${DateFormat('MMM d, y \\at h:mm a').format(data.startTime)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Complete the rucking details below to convert this hike to a ruck session.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatChip(String text) {
    return Chip(
      label: Text(
        text,
        style: TextStyle(fontSize: 12),
      ),
      backgroundColor: Colors.grey[200],
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
  
  @override
  void initState() {
    super.initState();
    _initializeForm();
  }
  
  void _initializeForm() {
    final importData = widget.args?.importedActivityData;
    
    if (importData != null) {
      // Pre-populate form with imported data
      _sessionNameController.text = importData.name;
      _selectedDate = importData.startTime;
      _startTime = TimeOfDay.fromDateTime(importData.startTime);
      _endTime = TimeOfDay.fromDateTime(importData.endTime);
      _distanceController.text = importData.totalDistance.toStringAsFixed(2);
      _elevationGainController.text = importData.elevationGain.toStringAsFixed(0);
      
      // Calculate and set average pace
      final paceMinutes = (importData.totalDuration.inSeconds / 60) / importData.totalDistance;
      _paceController.text = _formatPace(paceMinutes);
      
      // Mark as completed session
      _isCompletedSession = true;
      
      // Store the full track data for saving
      _importedTrackPoints = importData.trackPoints;
      _importedRoute = importData.route;
    } else {
      // Load user defaults for new manual entry
      _loadUserDefaults();
    }
  }
  
  String _getPageTitle() {
    if (widget.args?.isImport == true) {
      return 'Convert to Ruck Session';
    }
    return 'Create Manual Ruck';
  }
  
  String _getSubmitButtonText() {
    if (widget.args?.isImport == true) {
      return 'Convert to Ruck Session';
    }
    return 'Create Ruck Session';
  }
  
  Future<void> _createRuckSession() async {
    if (!_formKey.currentState!.validate()) return;
    
    final session = RuckSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _sessionNameController.text,
      startTime: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      ),
      endTime: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _endTime.hour,
        _endTime.minute,
      ),
      distance: double.parse(_distanceController.text),
      elevationGain: double.parse(_elevationGainController.text),
      ruckWeight: _ruckWeight,
      bodyWeight: _bodyWeight,
      difficulty: _selectedDifficulty,
      notes: _notesController.text,
      isCompleted: _isCompletedSession,
      isImported: widget.args?.isImport == true,
      // Include imported track data if available
      trackPoints: _importedTrackPoints,
      route: _importedRoute,
      // Recalculate calories with ruck weight
      caloriesBurned: widget.args?.isImport == true
          ? _calculateRuckCalories()
          : null,
    );
    
    await RuckSessionRepository.save(session);
    
    Navigator.pop(context);
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.args?.isImport == true
              ? 'Hike converted to ruck session successfully!'
              : 'Manual ruck session created successfully!',
        ),
        action: SnackBarAction(
          label: 'View Details',
          onPressed: () => NavigationService.navigateTo('/session/${session.id}'),
        ),
      ),
    );
  }
  
  double _calculateRuckCalories() {
    final importData = widget.args!.importedActivityData!;
    
    return CalorieCalculator.calculateForRuck(
      duration: importData.totalDuration,
      distance: importData.totalDistance,
      bodyWeight: _bodyWeight,
      ruckWeight: _ruckWeight,
      elevationGain: importData.elevationGain,
    );
  }
}
```

### 3.3 Guided Ruck Session with Real-Time ETA

```dart
// lib/features/guided_ruck/presentation/screens/guided_ruck_session_screen.dart
class GuidedRuckSessionScreen extends StatefulWidget {
  final RouteData routeData;
  final RuckSession session;
  
  @override
  State<GuidedRuckSessionScreen> createState() => _GuidedRuckSessionScreenState();
}

class _GuidedRuckSessionScreenState extends State<GuidedRuckSessionScreen> {
  late GuidedRuckController _controller;
  RouteProgress? _progress;
  
  @override
  void initState() {
    super.initState();
    _controller = GuidedRuckController(
      routeData: widget.routeData,
      session: widget.session,
    );
    _controller.progressStream.listen((progress) {
      setState(() => _progress = progress);
    });
    _controller.startGuidedSession();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeData.name),
        actions: [
          IconButton(
            icon: Icon(Icons.map),
            onPressed: _showFullMap,
          ),
        ],
      ),
      body: Column(
        children: [
          // Real-time progress card
          _buildProgressCard(),
          
          // Map with route and current position
          Expanded(
            flex: 2,
            child: _buildRouteMap(),
          ),
          
          // Elevation profile with progress
          Container(
            height: 120,
            child: _buildElevationProfile(),
          ),
          
          // Navigation controls
          _buildNavigationControls(),
        ],
      ),
    );
  }
  
  Widget _buildProgressCard() {
    if (_progress == null) return SizedBox.shrink();
    
    return Card(
      margin: EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildProgressStat(
                  'Distance',
                  '${_progress!.distanceCompleted.toStringAsFixed(1)}km',
                  '${_progress!.distanceRemaining.toStringAsFixed(1)}km left',
                ),
                _buildProgressStat(
                  'ETA',
                  _formatETA(_progress!.estimatedTimeRemaining),
                  _getETAStatus(),
                ),
                _buildProgressStat(
                  'Pace',
                  _formatPace(_progress!.currentPace),
                  _getPaceStatus(),
                ),
              ],
            ),
            SizedBox(height: 12),
            
            // Progress bar with color coding
            LinearProgressIndicator(
              value: _progress!.percentComplete / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(_getProgressColor()),
            ),
            
            SizedBox(height: 8),
            
            Text(
              '${_progress!.percentComplete.toStringAsFixed(1)}% Complete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatETA(Duration eta) {
    final hours = eta.inHours;
    final minutes = eta.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
  
  String _getETAStatus() {
    if (_progress == null) return '';
    
    final difference = _progress!.estimatedTimeRemaining.inMinutes - 
                      _progress!.originalProjectedTime.inMinutes;
    
    if (difference > 5) {
      return '${difference}m slower';
    } else if (difference < -5) {
      return '${-difference}m faster';
    }
    return 'On track';
  }
  
  Color _getProgressColor() {
    if (_progress == null) return Colors.blue;
    
    final paceRatio = _progress!.currentPace / _progress!.targetPace;
    if (paceRatio > 1.2) return Colors.red; // Much slower than expected
    if (paceRatio > 1.1) return Colors.orange; // Slightly slower
    if (paceRatio < 0.9) return Colors.green; // Faster than expected
    return Colors.blue; // On track
  }
}
```

### 3.4 Dynamic ETA Calculator

```dart
// lib/core/services/route_progress_calculator.dart
class RouteProgressCalculator {
  static RouteProgress calculateProgress({
    required RouteData route,
    required LatLng currentPosition,
    required List<TrackPoint> sessionTrackPoints,
    required DateTime sessionStartTime,
    required double ruckWeight,
    required double bodyWeight,
  }) {
    // Find closest point on route
    final closestPoint = _findClosestPointOnRoute(currentPosition, route.route);
    final distanceCompleted = _calculateDistanceToPoint(route.route, closestPoint);
    final distanceRemaining = route.distance - distanceCompleted;
    
    // Calculate current pace from recent track points
    final currentPace = _calculateCurrentPace(sessionTrackPoints);
    
    // Get elevation profile for remaining route
    final remainingElevationProfile = _getRemainingElevationProfile(
      route.elevationProfile, 
      distanceCompleted,
    );
    
    // Calculate dynamic ETA based on:
    // 1. Current pace
    // 2. Remaining elevation changes
    // 3. Terrain adjustments
    // 4. Fatigue factor (longer sessions = slower pace)
    final estimatedTimeRemaining = _calculateDynamicETA(
      distanceRemaining: distanceRemaining,
      currentPace: currentPace,
      elevationProfile: remainingElevationProfile,
      sessionDuration: DateTime.now().difference(sessionStartTime),
      ruckWeight: ruckWeight,
      bodyWeight: bodyWeight,
    );
    
    return RouteProgress(
      distanceCompleted: distanceCompleted,
      distanceRemaining: distanceRemaining,
      percentComplete: (distanceCompleted / route.distance) * 100,
      currentPace: currentPace,
      targetPace: _calculateTargetPace(route, ruckWeight),
      estimatedTimeRemaining: estimatedTimeRemaining,
      originalProjectedTime: _calculateOriginalProjection(route, ruckWeight),
      nextPointOfInterest: _getNextPOI(route.pointsOfInterest, currentPosition),
    );
  }
  
  static Duration _calculateDynamicETA({
    required double distanceRemaining,
    required double currentPace, // minutes per km
    required List<ElevationPoint> elevationProfile,
    required Duration sessionDuration,
    required double ruckWeight,
    required double bodyWeight,
  }) {
    // Base time from current pace
    double baseTimeMinutes = distanceRemaining * currentPace;
    
    // Elevation adjustment using modified Naismith's rule for rucking
    double elevationAdjustment = 0;
    for (int i = 0; i < elevationProfile.length - 1; i++) {
      final current = elevationProfile[i];
      final next = elevationProfile[i + 1];
      final elevationGain = math.max(0, next.elevation - current.elevation);
      
      // +1 minute per 10m elevation gain, adjusted for ruck weight
      final weightMultiplier = 1 + (ruckWeight / 50); // 50kg ruck = 2x slower
      elevationAdjustment += (elevationGain / 10) * weightMultiplier;
    }
    
    // Fatigue factor (pace slows over time)
    double fatigueMultiplier = 1.0;
    final hoursInSession = sessionDuration.inMinutes / 60;
    if (hoursInSession > 2) {
      // After 2 hours, pace slows by 5% per additional hour
      fatigueMultiplier = 1 + ((hoursInSession - 2) * 0.05);
    }
    
    // Terrain adjustment based on trail difficulty
    double terrainMultiplier = 1.0;
    for (final point in elevationProfile) {
      if (point.terrain == 'rocky' || point.terrain == 'steep') {
        terrainMultiplier = math.max(terrainMultiplier, 1.2);
      } else if (point.terrain == 'technical') {
        terrainMultiplier = math.max(terrainMultiplier, 1.3);
      }
    }
    
    final totalMinutes = (baseTimeMinutes + elevationAdjustment) * 
                        fatigueMultiplier * 
                        terrainMultiplier;
    
    return Duration(minutes: totalMinutes.round());
  }
  
  static double _calculateCurrentPace(List<TrackPoint> trackPoints) {
    if (trackPoints.length < 2) return 10.0; // Default 10 min/km
    
    // Use last 10 points for moving average to smooth out GPS noise
    final recentPoints = trackPoints.length > 10 
        ? trackPoints.sublist(trackPoints.length - 10)
        : trackPoints;
    
    double totalDistance = 0;
    Duration totalTime = Duration.zero;
    
    for (int i = 1; i < recentPoints.length; i++) {
      final prev = recentPoints[i - 1];
      final curr = recentPoints[i];
      
      totalDistance += _calculateDistance(prev.latitude, prev.longitude, 
                                         curr.latitude, curr.longitude);
      totalTime += curr.timestamp.difference(prev.timestamp);
    }
    
    if (totalDistance == 0) return 10.0;
    
    // Return pace in minutes per kilometer
    return (totalTime.inSeconds / 60) / totalDistance;
  }
}

class RouteProgress {
  final double distanceCompleted;
  final double distanceRemaining;
  final double percentComplete;
  final double currentPace; // minutes per km
  final double targetPace;
  final Duration estimatedTimeRemaining;
  final Duration originalProjectedTime;
  final PointOfInterest? nextPointOfInterest;
  
  const RouteProgress({
    required this.distanceCompleted,
    required this.distanceRemaining,
    required this.percentComplete,
    required this.currentPace,
    required this.targetPace,
    required this.estimatedTimeRemaining,
    required this.originalProjectedTime,
    this.nextPointOfInterest,
  });
}
```

---

## 4. Database Schema for Shareable Routes

### 4.1 Table Structure Overview

```sql
-- Core route data (shareable between users)
CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    source VARCHAR(50) NOT NULL, -- 'alltrails', 'custom', 'community'
    external_id VARCHAR(255), -- AllTrails trail ID, etc.
    external_url TEXT, -- Link back to original source
    
    -- Geographic data
    start_latitude DECIMAL(10, 8) NOT NULL,
    start_longitude DECIMAL(11, 8) NOT NULL,
    end_latitude DECIMAL(10, 8),
    end_longitude DECIMAL(11, 8),
    route_polyline TEXT NOT NULL, -- Encoded polyline or GeoJSON
    
    -- Route metrics
    distance_km DECIMAL(6, 2) NOT NULL,
    elevation_gain_m DECIMAL(6, 1) NOT NULL,
    elevation_loss_m DECIMAL(6, 1),
    min_elevation_m DECIMAL(6, 1),
    max_elevation_m DECIMAL(6, 1),
    
    -- Difficulty and characteristics
    trail_difficulty VARCHAR(20), -- 'easy', 'moderate', 'hard', 'extreme'
    trail_type VARCHAR(50), -- 'loop', 'out_and_back', 'point_to_point'
    surface_type VARCHAR(50), -- 'trail', 'paved', 'gravel', 'mixed'
    
    -- Popularity metrics
    total_planned_count INTEGER DEFAULT 0,
    total_completed_count INTEGER DEFAULT 0,
    average_rating DECIMAL(3, 2),
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by_user_id UUID REFERENCES users(id),
    is_verified BOOLEAN DEFAULT FALSE, -- Verified routes for quality
    is_public BOOLEAN DEFAULT TRUE -- Can other users see this route?
);

-- Detailed elevation profile data
CREATE TABLE route_elevation_points (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    distance_km DECIMAL(6, 3) NOT NULL, -- Distance along route
    elevation_m DECIMAL(6, 1) NOT NULL,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    terrain_type VARCHAR(50), -- 'trail', 'rocky', 'steep', 'technical'
    grade_percent DECIMAL(4, 1), -- Slope percentage
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Points of interest along routes
CREATE TABLE route_points_of_interest (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    poi_type VARCHAR(50) NOT NULL, -- 'water', 'rest', 'viewpoint', 'hazard', 'parking'
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    distance_from_start_km DECIMAL(6, 3),
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User-specific planned rucks (references shareable routes)
CREATE TABLE planned_rucks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    
    -- User-specific planning data
    name VARCHAR(255), -- Custom name override
    planned_date TIMESTAMPTZ,
    planned_ruck_weight_kg DECIMAL(4, 1) NOT NULL,
    planned_difficulty VARCHAR(20) NOT NULL,
    
    -- User preferences for this ruck
    safety_tracking_enabled BOOLEAN DEFAULT TRUE,
    weather_alerts_enabled BOOLEAN DEFAULT TRUE,
    notes TEXT,
    
    -- Calculated projections based on user profile + route
    estimated_duration_hours DECIMAL(4, 2),
    estimated_calories INTEGER,
    estimated_difficulty_description TEXT,
    
    -- Status tracking
    status VARCHAR(20) DEFAULT 'planned', -- 'planned', 'in_progress', 'completed', 'cancelled'
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enhanced ruck sessions table (links to routes when available)
ALTER TABLE ruck_sessions ADD COLUMN route_id UUID REFERENCES routes(id);
ALTER TABLE ruck_sessions ADD COLUMN planned_ruck_id UUID REFERENCES planned_rucks(id);
ALTER TABLE ruck_sessions ADD COLUMN is_guided_session BOOLEAN DEFAULT FALSE;

-- Route usage analytics
CREATE TABLE route_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL, -- 'planned', 'started', 'completed', 'cancelled'
    
    -- Session-specific data (when applicable)
    actual_duration_hours DECIMAL(4, 2),
    actual_ruck_weight_kg DECIMAL(4, 1),
    user_rating INTEGER CHECK (user_rating >= 1 AND user_rating <= 5),
    user_feedback TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.2 Indexes for Performance

```sql
-- Route discovery and search
CREATE INDEX idx_routes_location ON routes USING GIST (
    ST_Point(start_longitude, start_latitude)
);
CREATE INDEX idx_routes_distance ON routes(distance_km);
CREATE INDEX idx_routes_difficulty ON routes(trail_difficulty);
CREATE INDEX idx_routes_popularity ON routes(total_completed_count DESC);
CREATE INDEX idx_routes_source_external ON routes(source, external_id);

-- User-specific queries
CREATE INDEX idx_planned_rucks_user_status ON planned_rucks(user_id, status);
CREATE INDEX idx_planned_rucks_user_date ON planned_rucks(user_id, planned_date);
CREATE INDEX idx_planned_rucks_route ON planned_rucks(route_id);

-- Route details
CREATE INDEX idx_elevation_points_route_distance ON route_elevation_points(route_id, distance_km);
CREATE INDEX idx_poi_route ON route_points_of_interest(route_id);

-- Analytics
CREATE INDEX idx_analytics_route_event ON route_analytics(route_id, event_type);
CREATE INDEX idx_analytics_user ON route_analytics(user_id, created_at);
```

### 4.3 Data Models

```dart
// lib/core/models/route.dart
class Route {
  final String id;
  final String name;
  final String? description;
  final String source; // 'alltrails', 'custom', 'community'
  final String? externalId;
  final String? externalUrl;
  
  // Geographic data
  final LatLng startLocation;
  final LatLng? endLocation;
  final String routePolyline; // Encoded or GeoJSON
  
  // Metrics
  final double distanceKm;
  final double elevationGainM;
  final double? elevationLossM;
  final double? minElevationM;
  final double? maxElevationM;
  
  // Characteristics
  final TrailDifficulty? trailDifficulty;
  final TrailType? trailType;
  final SurfaceType? surfaceType;
  
  // Popularity
  final int totalPlannedCount;
  final int totalCompletedCount;
  final double? averageRating;
  
  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByUserId;
  final bool isVerified;
  final bool isPublic;
  
  // Related data (loaded separately)
  final List<RouteElevationPoint>? elevationProfile;
  final List<RoutePointOfInterest>? pointsOfInterest;
  
  const Route({
    required this.id,
    required this.name,
    this.description,
    required this.source,
    this.externalId,
    this.externalUrl,
    required this.startLocation,
    this.endLocation,
    required this.routePolyline,
    required this.distanceKm,
    required this.elevationGainM,
    this.elevationLossM,
    this.minElevationM,
    this.maxElevationM,
    this.trailDifficulty,
    this.trailType,
    this.surfaceType,
    this.totalPlannedCount = 0,
    this.totalCompletedCount = 0,
    this.averageRating,
    required this.createdAt,
    required this.updatedAt,
    this.createdByUserId,
    this.isVerified = false,
    this.isPublic = true,
    this.elevationProfile,
    this.pointsOfInterest,
  });
}

class RouteElevationPoint {
  final String id;
  final String routeId;
  final double distanceKm;
  final double elevationM;
  final LatLng? location;
  final String? terrainType;
  final double? gradePercent;
  
  const RouteElevationPoint({
    required this.id,
    required this.routeId,
    required this.distanceKm,
    required this.elevationM,
    this.location,
    this.terrainType,
    this.gradePercent,
  });
}

class RoutePointOfInterest {
  final String id;
  final String routeId;
  final String name;
  final String? description;
  final POIType poiType;
  final LatLng location;
  final double? distanceFromStartKm;
  
  const RoutePointOfInterest({
    required this.id,
    required this.routeId,
    required this.name,
    this.description,
    required this.poiType,
    required this.location,
    this.distanceFromStartKm,
  });
}

enum TrailType { loop, outAndBack, pointToPoint }
enum SurfaceType { trail, paved, gravel, mixed }
enum POIType { water, rest, viewpoint, hazard, parking }

// Updated PlannedRuck model
class PlannedRuck {
  final String id;
  final String userId;
  final String routeId;
  
  // User-specific data
  final String? customName; // Override route name
  final DateTime? plannedDate;
  final double plannedRuckWeightKg;
  final RuckDifficulty plannedDifficulty;
  
  // Preferences
  final bool safetyTrackingEnabled;
  final bool weatherAlertsEnabled;
  final String? notes;
  
  // Calculated projections
  final double? estimatedDurationHours;
  final int? estimatedCalories;
  final String? estimatedDifficultyDescription;
  
  // Status
  final RuckStatus status;
  
  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Related data (loaded via joins)
  final Route? route;
  
  const PlannedRuck({
    required this.id,
    required this.userId,
    required this.routeId,
    this.customName,
    this.plannedDate,
    required this.plannedRuckWeightKg,
    required this.plannedDifficulty,
    this.safetyTrackingEnabled = true,
    this.weatherAlertsEnabled = true,
    this.notes,
    this.estimatedDurationHours,
    this.estimatedCalories,
    this.estimatedDifficultyDescription,
    this.status = RuckStatus.planned,
    required this.createdAt,
    required this.updatedAt,
    this.route,
  });
  
  String get displayName => customName ?? route?.name ?? 'Unnamed Route';
}
```

### 4.4 Future Community Features Enabled

With this structure, you can easily add:

1. **Route Discovery** - "Popular routes near you"
2. **Community Ratings** - User reviews and difficulty ratings
3. **Route Sharing** - Users can publish custom routes
4. **Leaderboards** - Fastest times on popular routes
5. **Route Recommendations** - ML-based suggestions
6. **Route Variants** - Different start points for same trail
7. **Seasonal Conditions** - Community-reported trail conditions

---

## 5. Export to AllTrails

### 4.1 Share Integration

```dart
// lib/core/services/share_service.dart
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ShareService {
  static Future<void> shareRouteToAllTrails(RuckSession session) async {
    // Generate GPX file
    final gpxContent = await GPXGenerator.generateFromSession(session);
    
    // Save to temporary file
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${session.name}.gpx');
    await file.writeAsString(gpxContent);
    
    // Share with system share sheet
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Check out my rucking route: ${session.name}',
      subject: 'Rucking Route from ${session.date.toShortString()}',
    );
  }
  
  static Future<void> shareToAllTrailsDirectly(RuckSession session) async {
    // Generate GPX
    final gpxContent = await GPXGenerator.generateFromSession(session);
    
    // Open AllTrails with route data (if they support URL schemes)
    final allTrailsUrl = 'alltrails://import?gpx=${Uri.encodeComponent(gpxContent)}';
    
    if (await canLaunchUrl(Uri.parse(allTrailsUrl))) {
      await launchUrl(Uri.parse(allTrailsUrl));
    } else {
      // Fallback to share sheet
      await shareRouteToAllTrails(session);
    }
  }
}
```

### 4.2 GPX Generator

```dart
// lib/core/services/gpx_generator.dart
class GPXGenerator {
  static Future<String> generateFromSession(RuckSession session) async {
    final buffer = StringBuffer();
    
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Rucking App">');
    
    // Metadata
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${session.name}</name>');
    buffer.writeln('    <desc>Rucking session with ${session.ruckWeight}kg pack</desc>');
    buffer.writeln('    <time>${session.startTime.toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    
    // Track
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${session.name}</name>');
    buffer.writeln('    <type>Rucking</type>');
    buffer.writeln('    <trkseg>');
    
    for (final point in session.trackPoints) {
      buffer.writeln('      <trkpt lat="${point.latitude}" lon="${point.longitude}">');
      buffer.writeln('        <ele>${point.elevation}</ele>');
      buffer.writeln('        <time>${point.timestamp.toIso8601String()}</time>');
      buffer.writeln('      </trkpt>');
    }
    
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');
    
    return buffer.toString();
  }
}
```

---

## 5. Dependencies

### 5.1 pubspec.yaml

```yaml
dependencies:
  app_links: ^3.4.5
  share_plus: ^7.2.1
  shared_preferences: ^2.2.2
  path_provider: ^2.1.1
  xml: ^6.4.2
  url_launcher: ^6.2.1
```

### 5.2 iOS Dependencies

```ruby
# ios/Podfile
target 'ShareExtension' do
  use_frameworks!
  use_modular_headers!
end
```

---

## 6. Testing Strategy

### 6.1 Integration Tests

```dart
// test/integration/alltrails_integration_test.dart
void main() {
  group('AllTrails Integration', () {
    testWidgets('imports GPX file successfully', (tester) async {
      // Mock GPX data
      const gpxData = '''<?xml version="1.0"?>
        <gpx version="1.1">
          <trk><name>Test Trail</name></trk>
        </gpx>''';
      
      // Simulate share extension
      await RouteImportService.processGPXData(gpxData);
      
      // Verify import dialog appears
      expect(find.byType(RouteImportSheet), findsOneWidget);
    });
    
    testWidgets('exports session as GPX', (tester) async {
      // Create test session
      final session = createTestRuckSession();
      
      // Generate GPX
      final gpx = await GPXGenerator.generateFromSession(session);
      
      // Verify GPX format
      expect(gpx, contains('<gpx'));
      expect(gpx, contains(session.name));
    });
  });
}
```

---

## 7. Implementation Timeline

### Phase 1 (Week 1-2)
- [ ] Create Share Extension target
- [ ] Implement basic GPX parsing
- [ ] Create route import UI

### Phase 2 (Week 3-4)  
- [ ] Add file association support
- [ ] Implement GPX export functionality
- [ ] Add system share sheet integration

### Phase 3 (Week 5-6)
- [ ] Polish UI/UX
- [ ] Add user preference defaults
- [ ] Comprehensive testing
- [ ] App Store submission

### Phase 4 (Future)
- [ ] Direct AllTrails API integration (if available)
- [ ] Advanced route planning features
- [ ] Community sharing features

---

## 8. Security Considerations

- All file transfers use iOS sandboxing
- GPX files contain no sensitive user data
- Share extension has limited system access
- User data stays within app boundaries
- Proper entitlements and permissions

## 9. App Store Guidelines

- Share extension follows Apple guidelines
- No private API usage
- Proper document type declarations
- User privacy respected
- Seamless integration without breaking app boundaries
