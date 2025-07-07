# ActiveSessionBloc Refactoring Plan

## Overview
The ActiveSessionBloc is a monolithic 2825-line file handling multiple concerns. This plan breaks it down into 11 focused modules for improved maintainability, testability, and LLM processing efficiency.

## Current State Analysis
- **File**: `active_session_bloc.dart`
- **Total Lines**: 2825
- **Total Methods**: 60
- **Dependencies**: 44 imports
- **Concerns**: Session lifecycle, location tracking, heart rate monitoring, photo management, batch uploads, error handling, memory management, diagnostics, terrain tracking, persistence

## Target Architecture

### High-Level Module Structure
```
┌─────────────────────────────────────────────────────────────┐
│                   ActiveSessionCoordinator                   │
│                  (Main BLoC - ~300 lines)                   │
├─────────────────────────────────────────────────────────────┤
│  Event Routing │ State Management │ Module Coordination      │
└──────────────────┬──────────────────────────────────────────┘
                   │
    ┌──────────────┼──────────────────────────────────┐
    │              │                                  │
┌───▼────┐  ┌─────▼──────┐  ┌────────▼────────┐  ┌──▼──────┐
│Session │  │  Location   │  │   HeartRate     │  │ Photo   │
│Manager │  │  Manager    │  │   Manager       │  │ Manager │
│~400 ln │  │  ~500 ln    │  │   ~350 ln       │  │ ~400 ln │
└────────┘  └─────────────┘  └─────────────────┘  └─────────┘

┌─────────┐  ┌────────────┐  ┌─────────────────┐  ┌─────────┐
│ Upload  │  │   Memory   │  │  Diagnostics    │  │Recovery │
│ Manager │  │  Manager   │  │   Manager       │  │ Manager │
│ ~350 ln │  │  ~200 ln   │  │   ~250 ln       │  │ ~200 ln │
└─────────┘  └────────────┘  └─────────────────┘  └─────────┘

┌─────────────────────┐  ┌──────────────────────────────────┐
│  Terrain Manager    │  │    Session Persistence Manager   │
│     ~200 ln         │  │           ~250 ln                │
└─────────────────────┘  └──────────────────────────────────┘
```

## Detailed Module Specifications

### 1. ActiveSessionCoordinator (Main BLoC)
**File**: `lib/features/ruck_session/presentation/bloc/active_session_coordinator.dart`  
**Estimated Lines**: ~300  
**Purpose**: Central coordinator that routes events and aggregates state from all managers

**Responsibilities**:
- Event routing to appropriate managers
- State aggregation from all managers
- Dependency injection and initialization
- High-level lifecycle coordination
- Manager cleanup on close

**Key Components**:
```dart
class ActiveSessionCoordinator extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  final SessionLifecycleManager _sessionManager;
  final LocationTrackingManager _locationManager;
  final HeartRateManager _heartRateManager;
  final PhotoManager _photoManager;
  final UploadManager _uploadManager;
  final MemoryManager _memoryManager;
  final DiagnosticsManager _diagnosticsManager;
  final RecoveryManager _recoveryManager;
  final TerrainManager _terrainManager;
  final SessionPersistenceManager _persistenceManager;
  
  // Event routing logic
  // State aggregation logic
  // Lifecycle management
}
```

### 2. SessionLifecycleManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/session_lifecycle_manager.dart`  
**Estimated Lines**: ~400  
**Purpose**: Manages core session lifecycle events and state transitions

**Methods to Extract**:
- `_onSessionStarted()` (lines 266-458)
- `_onSessionPaused()` (lines 723-766)
- `_onSessionResumed()` (lines 768-814)
- `_onSessionCompleted()` (lines 816-1270)
- `_onTimerStarted()` (lines 460-471)
- `_onTick()` (lines 473-603)
- `_onSessionReset()` (lines 2105-2131)

**Dependencies**:
- SessionValidationService
- ActiveSessionStorage
- AuthService
- WatchService

### 3. LocationTrackingManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/location_tracking_manager.dart`  
**Estimated Lines**: ~500  
**Purpose**: Handles all location-related functionality

**Methods to Extract**:
- `_onLocationUpdated()` (lines 605-705)
- `_onBatchLocationUpdated()` (lines 707-721)
- `_calculateDistance()` (lines 2155-2166)
- `_calculateCurrentPace()` (lines 2133-2153)
- `_ensureLocationTrackingActive()` (lines 2439-2444)
- `_adjustLocationTrackingForMemoryPressure()` (lines 2781-2794)
- `_adjustLocationTrackingMode()` (lines 2800-2824)

**Dependencies**:
- LocationService
- SplitTrackingService
- TerrainTracker

### 4. HeartRateManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/heart_rate_manager.dart`  
**Estimated Lines**: ~350  
**Purpose**: Manages heart rate monitoring and data processing

**Methods to Extract**:
- `_onHeartRateUpdated()` (lines 1345-1424)
- `_onHeartRateBufferProcessed()` (lines 1426-1467)
- `_emergencyUploadHeartRateSamples()` (lines 2664-2692)
- Heart rate statistics calculation logic
- Heart rate throttling logic

**Dependencies**:
- HeartRateService
- HealthService

### 5. PhotoManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/photo_manager.dart`  
**Estimated Lines**: ~400  
**Purpose**: Handles session photo management

**Methods to Extract**:
- `_onFetchSessionPhotosRequested()` (lines 1597-1641)
- `_onUploadSessionPhotosRequested()` (lines 1643-1732)
- `_onDeleteSessionPhotoRequested()` (lines 1734-1800)
- `_onClearSessionPhotos()` (lines 1802-1807)
- `_onTakePhotoRequested()` (lines 1809-1826)
- `_onPickPhotoRequested()` (lines 1828-1845)
- `_onUpdateStateWithSessionPhotos()` (lines 1969-1982)

**Dependencies**:
- ApiClient
- ImagePicker
- StorageService

### 6. UploadManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/upload_manager.dart`  
**Estimated Lines**: ~350  
**Purpose**: Manages batch uploads and data synchronization

**Methods to Extract**:
- `_batchUploadLocationPoints()` (lines 1469-1522)
- `_batchUploadHeartRateSamples()` (lines 1524-1567)
- `_emergencyUploadLocationPoints()` (lines 2634-2662)
- `_syncOfflineSessions()` (lines 2299-2345)
- `_syncOfflineSessionsInBackground()` (lines 2285-2297)
- `_increaseUploadFrequency()` (lines 2694-2713)

**Dependencies**:
- ApiClient
- ConnectivityService
- ActiveSessionStorage

### 7. MemoryManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/memory_manager.dart`  
**Estimated Lines**: ~200  
**Purpose**: Handles memory pressure and optimization

**Methods to Extract**:
- `_onMemoryPressureDetected()` (lines 2228-2283)
- `_checkMemoryPressure()` (lines 2715-2762)
- `_forceGarbageCollection()` (lines 2764-2779)
- `_getMemoryInfo()` (lines 2614-2632)

**Dependencies**:
- Platform APIs
- System monitoring

### 8. DiagnosticsManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/diagnostics_manager.dart`  
**Estimated Lines**: ~250  
**Purpose**: Tracks and reports session diagnostics

**Methods to Extract**:
- `_reportSessionDiagnostics()` (lines 2506-2607)
- `_startDiagnosticsTimer()` (lines 2498-2504)
- `_stopDiagnosticsTimer()` (lines 2609-2612)
- `_resetSessionDiagnostics()` (lines 2482-2496)

**Dependencies**:
- Sentry/Crashlytics
- AppLogger

### 9. RecoveryManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/recovery_manager.dart`  
**Estimated Lines**: ~200  
**Purpose**: Handles session recovery and error states

**Methods to Extract**:
- `_onSessionRecoveryRequested()` (lines 1999-2103)
- `_onSessionErrorCleared()` (lines 1984-1997)
- `_onSessionCleanupRequested()` (lines 2194-2226)
- `_attemptOfflineSessionSync()` (lines 2446-2480)

**Dependencies**:
- ActiveSessionStorage
- ErrorHandler

### 10. TerrainManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/terrain_manager.dart`  
**Estimated Lines**: ~200  
**Purpose**: Manages terrain tracking and analysis

**Methods to Extract**:
- Terrain segment tracking logic
- Terrain statistics calculation
- Integration with TerrainTracker service

**Dependencies**:
- TerrainTracker
- TerrainService

### 11. SessionPersistenceManager
**File**: `lib/features/ruck_session/presentation/bloc/managers/session_persistence_manager.dart`  
**Estimated Lines**: ~250  
**Purpose**: Handles session state persistence and offline storage

**Methods to Extract**:
- `_onLoadSessionForViewing()` (lines 1847-1967)
- `_buildCompletionPayloadInBackground()` (lines 2347-2383)
- Offline session storage logic
- Session state recovery logic

**Dependencies**:
- ActiveSessionStorage
- SharedPreferences
- SessionRepository

## Implementation Strategy

### Phase 1: Create Manager Interfaces (Day 1)
1. Define abstract base classes for each manager
2. Create event and state interfaces for inter-manager communication
3. Set up directory structure

### Phase 2: Extract Core Managers (Days 2-3)
1. **SessionLifecycleManager** - Core functionality first
2. **LocationTrackingManager** - Critical for session tracking
3. **HeartRateManager** - Important health data

### Phase 3: Extract Supporting Managers (Days 4-5)
1. **PhotoManager** - UI feature, can be isolated
2. **UploadManager** - Background functionality
3. **MemoryManager** - System optimization

### Phase 4: Extract Auxiliary Managers (Day 6)
1. **DiagnosticsManager** - Monitoring
2. **RecoveryManager** - Error handling
3. **TerrainManager** - Feature-specific
4. **SessionPersistenceManager** - Storage

### Phase 5: Implement Coordinator (Day 7)
1. Create ActiveSessionCoordinator
2. Wire up all managers
3. Implement event routing
4. Implement state aggregation

### Phase 6: Testing & Migration (Days 8-9)
1. Unit test each manager
2. Integration tests for coordinator
3. Update all references in the app
4. Gradual rollout with feature flags

## Benefits of This Refactoring

### For Development:
- **Maintainability**: Each manager is focused on a single concern
- **Testability**: Smaller units are easier to test in isolation
- **Readability**: ~200-500 line files vs 3000 lines
- **Collaboration**: Multiple developers can work on different managers

### For LLM Processing:
- **Context Window**: Each file fits comfortably in LLM context
- **Focused Analysis**: LLM can understand entire module at once
- **Better Suggestions**: More accurate code generation with full context
- **Efficient Updates**: Changes isolated to specific managers

### For Performance:
- **Memory**: Managers can be optimized independently
- **Lazy Loading**: Managers can be initialized as needed
- **Parallel Processing**: Independent managers can run concurrently

## Migration Guidelines

### Step 1: Create New Structure
```bash
lib/features/ruck_session/presentation/bloc/
├── active_session_coordinator.dart
├── active_session_event.dart (existing)
├── active_session_state.dart (existing)
├── managers/
│   ├── session_lifecycle_manager.dart
│   ├── location_tracking_manager.dart
│   ├── heart_rate_manager.dart
│   ├── photo_manager.dart
│   ├── upload_manager.dart
│   ├── memory_manager.dart
│   ├── diagnostics_manager.dart
│   ├── recovery_manager.dart
│   ├── terrain_manager.dart
│   └── session_persistence_manager.dart
└── models/
    └── manager_states.dart
```

### Step 2: Extract Method by Method
1. Copy method to new manager
2. Update imports
3. Create unit test
4. Mark original as deprecated
5. Update coordinator routing

### Step 3: Gradual Migration
1. Keep old bloc functional during migration
2. Use feature flags to switch between old/new
3. Monitor metrics during rollout
4. Remove old bloc after stability confirmed

## Code Templates

### Manager Base Class
```dart
abstract class SessionManager {
  Stream<SessionManagerState> get stateStream;
  SessionManagerState get currentState;
  Future<void> handleEvent(ActiveSessionEvent event);
  Future<void> dispose();
}
```

### Manager Implementation
```dart
class LocationTrackingManager implements SessionManager {
  final LocationService _locationService;
  final StreamController<LocationManagerState> _stateController;
  
  LocationTrackingManager({required LocationService locationService})
      : _locationService = locationService,
        _stateController = StreamController<LocationManagerState>.broadcast();
  
  @override
  Stream<LocationManagerState> get stateStream => _stateController.stream;
  
  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is LocationUpdated) {
      await _handleLocationUpdate(event);
    } else if (event is BatchLocationUpdated) {
      await _handleBatchLocationUpdate(event);
    }
  }
  
  // Implementation details...
}
```

## Success Metrics
- [ ] All tests passing
- [ ] No regression in functionality
- [ ] Improved app performance metrics
- [ ] Reduced crash rate
- [ ] Faster build times
- [ ] Easier onboarding for new developers

## Notes
- Preserve all existing functionality
- Maintain backward compatibility during migration
- Document all inter-manager dependencies
- Consider using event bus for loose coupling
- Add comprehensive logging for debugging
