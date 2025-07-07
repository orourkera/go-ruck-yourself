import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/events/session_events.dart' as manager_events;
import 'managers/session_lifecycle_manager.dart';
import 'managers/location_tracking_manager.dart';
import 'managers/heart_rate_manager.dart';
import 'managers/photo_manager.dart';
import 'managers/upload_manager.dart';
import 'managers/memory_manager.dart';
import 'managers/diagnostics_manager.dart';
import 'managers/memory_pressure_manager.dart';

/// Main coordinator that orchestrates all session managers
class ActiveSessionCoordinator extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  // Services
  final SessionRepository _sessionRepository;
  final LocationService _locationService;
  final AuthService _authService;
  final WatchService _watchService;
  final StorageService _storageService;
  final ApiClient _apiClient;
  final SplitTrackingService _splitTrackingService;
  final TerrainTracker _terrainTracker;
  final HeartRateService _heartRateService;
  
  // Managers
  late final SessionLifecycleManager _lifecycleManager;
  late final LocationTrackingManager _locationManager;
  late final HeartRateManager _heartRateManager;
  late final PhotoManager _photoManager;
  late final UploadManager _uploadManager;
  late final MemoryManager _memoryManager;
  late final DiagnosticsManager _diagnosticsManager;
  late final MemoryPressureManager _memoryPressureManager;
  // late final RecoveryManager _recoveryManager;  // TODO: Implement when needed
  // late final TerrainManager _terrainManager;  // TODO: Implement when needed
  // late final SessionPersistenceManager _persistenceManager;  // TODO: Implement when needed
  
  // Manager state subscriptions
  final List<StreamSubscription> _managerSubscriptions = [];
  
  // Aggregated state
  ActiveSessionState _currentAggregatedState = const ActiveSessionInitial();
  
  ActiveSessionCoordinator({
    required SessionRepository sessionRepository,
    required LocationService locationService,
    required AuthService authService,
    required WatchService watchService,
    required StorageService storageService,
    required ApiClient apiClient,
    required SplitTrackingService splitTrackingService,
    required TerrainTracker terrainTracker,
    required HeartRateService heartRateService,
  })  : _sessionRepository = sessionRepository,
        _locationService = locationService,
        _authService = authService,
        _watchService = watchService,
        _storageService = storageService,
        _apiClient = apiClient,
        _splitTrackingService = splitTrackingService,
        _terrainTracker = terrainTracker,
        _heartRateService = heartRateService,
        super(const ActiveSessionInitial()) {
    
    // Initialize managers
    _initializeManagers();
    
    // Register event handlers for main bloc events
    on<SessionStarted>(_onSessionStarted);
    on<SessionCompleted>(_onSessionCompleted);
    on<SessionPaused>(_onSessionPaused);
    on<SessionResumed>(_onSessionResumed);
    on<LocationUpdated>(_onLocationUpdated);
    on<HeartRateUpdated>(_onHeartRateUpdated);
    on<TakePhotoRequested>(_onTakePhotoRequested);
    on<DeleteSessionPhotoRequested>(_onDeleteSessionPhotoRequested);
    on<TimerStarted>(_onTimerStarted);
    on<Tick>(_onTick);
    on<SessionRecoveryRequested>(_onSessionRecoveryRequested);
    on<BatchLocationUpdated>(_onBatchLocationUpdated);
    
    AppLogger.info('[COORDINATOR] ActiveSessionCoordinator initialized');
  }
  
  void _initializeManagers() {
    // Initialize lifecycle manager
    _lifecycleManager = SessionLifecycleManager(
      sessionRepository: _sessionRepository,
      authService: _authService,
      watchService: _watchService,
      storageService: _storageService,
      apiClient: _apiClient,
    );
    
    // Initialize location manager
    _locationManager = LocationTrackingManager(
      locationService: _locationService,
      splitTrackingService: _splitTrackingService,
      terrainTracker: _terrainTracker,
      apiClient: _apiClient,
    );
    
    // Initialize heart rate manager
    _heartRateManager = HeartRateManager(
      heartRateService: _heartRateService,
      watchService: _watchService,
    );
    
    // Initialize photo manager
    _photoManager = PhotoManager(
      sessionRepository: _sessionRepository,
      storageService: _storageService,
    );
    
    // Initialize upload manager
    _uploadManager = UploadManager(
      sessionRepository: _sessionRepository,
      apiClient: _apiClient,
      storageService: _storageService,
    );
    
    // Initialize memory manager
    _memoryManager = MemoryManager(
      storageService: _storageService,
    );
    
    // Subscribe to lifecycle manager state changes
    _managerSubscriptions.add(
      _lifecycleManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Lifecycle state updated: ${state.isActive}');
        _aggregateAndEmitState();
      }),
    );
    
    // Subscribe to location manager state changes
    _managerSubscriptions.add(
      _locationManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Location state updated: distance=${state.totalDistance}');
        _aggregateAndEmitState();
      }),
    );
    
    // Subscribe to heart rate manager state changes
    _managerSubscriptions.add(
      _heartRateManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Heart rate state updated: current=${state.currentHeartRate}');
        _aggregateAndEmitState();
      }),
    );
    
    // Subscribe to photo manager state changes
    _managerSubscriptions.add(
      _photoManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Photo state updated: count=${state.photos.length}');
        _aggregateAndEmitState();
      }),
    );
    
    // Subscribe to upload manager state changes
    _managerSubscriptions.add(
      _uploadManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Upload state updated: location=${state.pendingLocationPoints}, heartRate=${state.pendingHeartRateSamples}');
        _aggregateAndEmitState();
      }),
    );
    
    // Subscribe to memory manager state changes
    _managerSubscriptions.add(
      _memoryManager.stateStream.listen((state) {
        AppLogger.debug('[COORDINATOR] Memory state updated: hasSession=${state.hasActiveSession}');
        _aggregateAndEmitState();
      }),
    );
    
    // TODO: Initialize and subscribe to other managers as they are implemented
  }
  
  /// Route events to appropriate managers
  Future<void> _routeEventToManagers(ActiveSessionEvent event) async {
    AppLogger.debug('[COORDINATOR] Routing ${event.runtimeType} to managers');
    
    // Convert main bloc events to manager events
    final managerEvent = _convertToManagerEvent(event);
    if (managerEvent == null) {
      AppLogger.warning('[COORDINATOR] No manager event mapping for ${event.runtimeType}');
      return;
    }
    
    // Route to lifecycle manager (always gets events)
    await _lifecycleManager.handleEvent(managerEvent);
    
    // Route to location manager
    if (managerEvent is manager_events.SessionStartRequested ||
        managerEvent is manager_events.SessionStopRequested ||
        managerEvent is manager_events.SessionPaused ||
        managerEvent is manager_events.SessionResumed ||
        managerEvent is manager_events.LocationUpdated ||
        managerEvent is manager_events.BatchLocationUpdated) {
      await _locationManager.handleEvent(managerEvent);
    }
    
    // Route to heart rate manager
    if (managerEvent is manager_events.SessionStartRequested ||
        managerEvent is manager_events.SessionStopRequested ||
        managerEvent is manager_events.SessionPaused ||
        managerEvent is manager_events.SessionResumed ||
        managerEvent is manager_events.HeartRateUpdated) {
      await _heartRateManager.handleEvent(managerEvent);
    }
    
    // Route to photo manager
    if (managerEvent is manager_events.SessionStartRequested ||
        managerEvent is manager_events.SessionStopRequested ||
        managerEvent is manager_events.PhotoAdded ||
        managerEvent is manager_events.PhotoDeleted) {
      await _photoManager.handleEvent(managerEvent);
    }
    
    // Route to upload manager
    if (managerEvent is manager_events.SessionStartRequested ||
        managerEvent is manager_events.SessionStopRequested ||
        managerEvent is manager_events.BatchLocationUpdated) {
      await _uploadManager.handleEvent(managerEvent);
    }
    
    // Route to memory manager
    if (managerEvent is manager_events.SessionStartRequested ||
        managerEvent is manager_events.SessionStopRequested ||
        managerEvent is manager_events.SessionPaused ||
        managerEvent is manager_events.SessionResumed ||
        managerEvent is manager_events.MemoryUpdated ||
        managerEvent is manager_events.RestoreSessionRequested) {
      await _memoryManager.handleEvent(managerEvent);
    }
  }
  
  /// Convert main bloc events to manager events
  manager_events.ActiveSessionEvent? _convertToManagerEvent(ActiveSessionEvent mainEvent) {
    // Map main bloc events to manager events
    if (mainEvent is SessionStarted) {
      return manager_events.SessionStartRequested(
        ruckWeightKg: mainEvent.ruckWeightKg,
        userWeightKg: mainEvent.userWeightKg,
      );
    } else if (mainEvent is SessionCompleted) {
      return const manager_events.SessionStopRequested();
    } else if (mainEvent is SessionPaused) {
      return const manager_events.SessionPaused();
    } else if (mainEvent is SessionResumed) {
      return const manager_events.SessionResumed();
    } else if (mainEvent is TimerStarted) {
      return const manager_events.TimerStarted();
    } else if (mainEvent is Tick) {
      return const manager_events.Tick();
    } else if (mainEvent is LocationUpdated) {
      return manager_events.LocationUpdated(
        position: Position(
          latitude: mainEvent.locationPoint.latitude,
          longitude: mainEvent.locationPoint.longitude,
          accuracy: mainEvent.locationPoint.accuracy,
          altitude: mainEvent.locationPoint.elevation,
          heading: 0.0, // LocationPoint doesn't have bearing
          speed: mainEvent.locationPoint.speed ?? 0.0,
          speedAccuracy: 0.0,
          timestamp: mainEvent.locationPoint.timestamp,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        ),
      );
    } else if (mainEvent is HeartRateUpdated) {
      return manager_events.HeartRateUpdated(
        heartRate: mainEvent.sample.bpm,
        timestamp: mainEvent.sample.timestamp,
      );
    } else if (mainEvent is TakePhotoRequested) {
      return manager_events.PhotoAdded(
        photoPath: '', // TODO: Generate path for new photo
      );
    } else if (mainEvent is DeleteSessionPhotoRequested) {
      return manager_events.PhotoDeleted(
        photoId: mainEvent.photo.toString(), // TODO: Extract proper ID
      );
    } else if (mainEvent is SessionRecoveryRequested) {
      return const manager_events.RecoveryRequested(
        sessionId: '', // TODO: Extract session ID from state
      );
    }
    
    // Return null for unmapped events
    return null;
  }
  
  /// Aggregate state from all managers and emit combined state
  void _aggregateAndEmitState() {
    final lifecycleState = _lifecycleManager.currentState;
    final locationState = _locationManager.currentState;
    final heartRateState = _heartRateManager.currentState;
    
    // Map manager states to ActiveSessionState
    if (!lifecycleState.isActive && lifecycleState.sessionId == null) {
      _currentAggregatedState = const ActiveSessionInitial();
    } else if (lifecycleState.errorMessage != null) {
      _currentAggregatedState = ActiveSessionFailure(
        errorMessage: lifecycleState.errorMessage!,
      );
    } else if (lifecycleState.isActive && lifecycleState.sessionId != null) {
      // Aggregate states from all managers into ActiveSessionRunning
      final locationPoints = _locationManager.locationPoints;
      final calories = _calculateCalories(
        distanceKm: locationState.totalDistance,
        duration: lifecycleState.duration,
        userWeightKg: 75.0, // TODO: Store in lifecycle state
        ruckWeightKg: 0.0, // TODO: Store in lifecycle state
      );
      
      _currentAggregatedState = ActiveSessionRunning(
        sessionId: lifecycleState.sessionId!,
        locationPoints: locationPoints,
        elapsedSeconds: lifecycleState.duration.inSeconds,
        distanceKm: locationState.totalDistance,
        ruckWeightKg: 0.0, // TODO: Store in lifecycle state
        userWeightKg: 75.0, // TODO: Store in lifecycle state
        calories: calories,
        elevationGain: _locationManager.elevationGain,
        elevationLoss: _locationManager.elevationLoss,
        isPaused: _lifecycleManager.isPaused,
        pace: locationState.currentPace,
        originalSessionStartTimeUtc: DateTime.now(), // TODO: Store in lifecycle state
        totalPausedDuration: Duration.zero, // TODO: Calculate from lifecycle state
        heartRateSamples: _heartRateManager.heartRateSampleObjects,
        latestHeartRate: heartRateState.currentHeartRate,
        minHeartRate: heartRateState.minHeartRate,
        maxHeartRate: heartRateState.maxHeartRate,
        isGpsReady: _locationManager.isGpsReady,
        hasGpsAccess: locationState.isTracking,
        photos: _photoManager.photos,
        isPhotosLoading: _photoManager.isPhotosLoading,
        isUploading: _uploadManager.isUploading,
        splits: const [], // TODO: Get from split service
        terrainSegments: const [], // TODO: Get from terrain manager
      );
    }
    
    emit(_currentAggregatedState);
  }
  
  double _calculateCalories({
    required double distanceKm,
    required Duration duration,
    required double userWeightKg,
    required double ruckWeightKg,
  }) {
    if (distanceKm <= 0 || duration.inMinutes <= 0) return 0.0;
    
    // MET value for rucking (approximation)
    const baseMET = 8.0;
    final totalWeightKg = userWeightKg + ruckWeightKg;
    
    // Calories = MET * weight(kg) * time(hours)
    final hours = duration.inMinutes / 60.0;
    return baseMET * totalWeightKg * hours;
  }
  
  // Event handlers that delegate to managers
  Future<void> _onSessionStarted(
    SessionStarted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session start requested');
    await _routeEventToManagers(event);
    add(const TimerStarted());
  }
  
  Future<void> _onSessionCompleted(
    SessionCompleted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session completed');
    // Stop the timer by pausing first
    add(const SessionPaused());
    await _routeEventToManagers(event);
  }
  
  Future<void> _onSessionPaused(
    SessionPaused event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session paused');
    await _routeEventToManagers(event);
  }
  
  Future<void> _onSessionResumed(
    SessionResumed event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session resumed');
    await _routeEventToManagers(event);
  }
  
  Future<void> _onLocationUpdated(
    LocationUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when LocationTrackingManager is ready
    await _routeEventToManagers(event);
  }
  
  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when HeartRateManager is ready
    await _routeEventToManagers(event);
  }
  
  Future<void> _onTakePhotoRequested(
    TakePhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when PhotoManager is ready
    await _routeEventToManagers(event);
  }
  
  Future<void> _onDeleteSessionPhotoRequested(
    DeleteSessionPhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when PhotoManager is ready
    await _routeEventToManagers(event);
    _aggregateAndEmitState();
  }
  
  Future<void> _onTimerStarted(
    TimerStarted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
  }
  
  Future<void> _onTick(
    Tick event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
    _aggregateAndEmitState();
  }
  
  // Note: This method is now handled by _onSessionStopRequested
  
  Future<void> _onSessionRecoveryRequested(
    SessionRecoveryRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when RecoveryManager is ready
    await _routeEventToManagers(event);
  }
  
  Future<void> _onBatchLocationUpdated(
    BatchLocationUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // TODO: Implement when LocationTrackingManager is ready
    await _routeEventToManagers(event);
  }
  
  @override
  Future<void> close() async {
    AppLogger.info('[COORDINATOR] Closing ActiveSessionCoordinator');
    
    // Cancel all subscriptions
    for (final subscription in _managerSubscriptions) {
      await subscription.cancel();
    }
    
    // Dispose all managers
    await _lifecycleManager.dispose();
    await _locationManager.dispose();
    await _heartRateManager.dispose();
    await _photoManager.dispose();
    await _uploadManager.dispose();
    await _memoryManager.dispose();
    
    return super.close();
  }
}
