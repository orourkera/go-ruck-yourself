import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/met_calculator.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/services/memory_monitor_service.dart';
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
import 'models/manager_states.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_zone_service.dart';

/// Main coordinator that orchestrates all session managers
class ActiveSessionCoordinator extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  Type? _lastLoggedAggregatedStateType;
  // Services
  final SessionRepository _sessionRepository;
  final LocationService _locationService;
  final AuthService _authService;
  final WatchService _watchService;
  final StorageService _storageService;
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;
  final SplitTrackingService _splitTrackingService;
  final TerrainTracker _terrainTracker;
  final HeartRateService _heartRateService;
  final HealthService _healthService = GetIt.instance<HealthService>();
  
  // Managers
  late final SessionLifecycleManager _lifecycleManager;
  late final LocationTrackingManager _locationManager;
  late final HeartRateManager _heartRateManager;
  late final PhotoManager _photoManager;
  late final UploadManager _uploadManager;
  late final MemoryManager _memoryManager;
  late final DiagnosticsManager _diagnosticsManager;
  late final MemoryPressureManager _memoryPressureManager;
  
  // Additional managers can be added here when needed:
  // - RecoveryManager for session recovery
  // - TerrainManager for terrain analysis
  // - SessionPersistenceManager for local persistence
  
  // Manager state subscriptions
  final List<StreamSubscription> _managerSubscriptions = [];
  
  // Aggregated state
  ActiveSessionState _currentAggregatedState = const ActiveSessionInitial();
  
  // Store completion data to pass to lifecycle manager
  Map<String, dynamic>? _sessionCompletionData;
  String? _lastCalorieMethod;
  
  // Store planned route for navigation
  List<latlong.LatLng>? _plannedRoute;
  double? _plannedRouteDistance;
  int? _plannedRouteDuration;
  // Steps tracking
  StreamSubscription<int>? _stepsSub;
  int? _currentSteps;
  
  ActiveSessionCoordinator({
    required SessionRepository sessionRepository,
    required LocationService locationService,
    required AuthService authService,
    required WatchService watchService,
    required StorageService storageService,
    required ApiClient apiClient,
    required ConnectivityService connectivityService,
    required SplitTrackingService splitTrackingService,
    required TerrainTracker terrainTracker,
    required HeartRateService heartRateService,
  })  : _sessionRepository = sessionRepository,
        _locationService = locationService,
        _authService = authService,
        _watchService = watchService,
        _storageService = storageService,
        _apiClient = apiClient,
        _connectivityService = connectivityService,
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
    on<LoadSessionForViewing>(_onLoadSessionForViewing);
    on<TimerStarted>(_onTimerStarted);
    on<Tick>(_onTick);
    on<SessionRecoveryRequested>(_onSessionRecoveryRequested);
    on<SessionReset>(_onSessionReset);
    on<BatchLocationUpdated>(_onBatchLocationUpdated);
    on<HeartRateBatchUploadRequested>(_onHeartRateBatchUploadRequested);
    on<StateAggregationRequested>(_onStateAggregationRequested);
    on<MemoryPressureDetected>(_onMemoryPressureDetected);
    on<CheckForCrashedSession>(_onCheckForCrashedSession);
    
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
      connectivityService: _connectivityService,
    );
    
    // Set recovery callback to handle metric restoration
    _lifecycleManager.setRecoveryCallback(_handleRecoveredMetrics);
    
    // Set completion data callback to provide calculated metrics
    _lifecycleManager.setCompletionDataCallback(getSessionCompletionData);
    
    // Initialize location manager
    _locationManager = LocationTrackingManager(
      locationService: _locationService,
      splitTrackingService: _splitTrackingService,
      terrainTracker: _terrainTracker,
      apiClient: _apiClient,
      watchService: _watchService,
      authService: _authService,
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
    
    // Initialize memory pressure manager
    _memoryPressureManager = MemoryPressureManager(
      locationService: _locationService,
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
        final hasSession = state is MemoryState ? state.hasActiveSession : false;
        AppLogger.debug('[COORDINATOR] Memory state updated: hasSession=$hasSession');
        _aggregateAndEmitState();
      }),
    );
    
    AppLogger.info('[COORDINATOR] All managers initialized and subscribed');
  }
  
  /// Route events to appropriate managers
  Future<void> _routeEventToManagers(ActiveSessionEvent event) async {
    if (event is! Tick) {
      AppLogger.debug('[COORDINATOR] Routing ${event.runtimeType} to managers');
    }
    
    // Convert main bloc events to manager events
    final managerEvent = _convertToManagerEvent(event);
    if (managerEvent == null) {
      AppLogger.warning('[COORDINATOR] No manager event mapping for ${event.runtimeType}');
      return;
    }
    
    // Route to lifecycle manager (always gets events)
    await _lifecycleManager.handleEvent(managerEvent);
    
    // For SessionStartRequested events, use the actual session ID from lifecycle manager
    // after it has processed the event and generated the ID
    manager_events.ActiveSessionEvent finalManagerEvent = managerEvent;
    if (managerEvent is manager_events.SessionStartRequested) {
      final sessionId = _lifecycleManager.activeSessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        finalManagerEvent = manager_events.SessionStartRequested(
          sessionId: sessionId,
          ruckWeightKg: managerEvent.ruckWeightKg,
          userWeightKg: managerEvent.userWeightKg,
        );
        AppLogger.debug('[COORDINATOR] Using session ID from lifecycle manager: $sessionId');
      }
    }
    
    // Route to location manager
    if (finalManagerEvent is manager_events.SessionStartRequested ||
        finalManagerEvent is manager_events.SessionStopRequested ||
        finalManagerEvent is manager_events.SessionPaused ||
        finalManagerEvent is manager_events.SessionResumed ||
        finalManagerEvent is manager_events.SessionReset ||
        finalManagerEvent is manager_events.LocationUpdated ||
        finalManagerEvent is manager_events.BatchLocationUpdated) {
      await _locationManager.handleEvent(finalManagerEvent);
    }
    
    // Route to heart rate manager
    if (finalManagerEvent is manager_events.SessionStartRequested ||
        finalManagerEvent is manager_events.SessionStopRequested ||
        finalManagerEvent is manager_events.SessionPaused ||
        finalManagerEvent is manager_events.SessionResumed ||
        finalManagerEvent is manager_events.SessionReset ||
        finalManagerEvent is manager_events.HeartRateUpdated) {
      await _heartRateManager.handleEvent(finalManagerEvent);
    }
    
    // Route to photo manager
    if (finalManagerEvent is manager_events.SessionStartRequested ||
        finalManagerEvent is manager_events.SessionStopRequested ||
        finalManagerEvent is manager_events.SessionReset ||
        finalManagerEvent is manager_events.PhotoAdded ||
        finalManagerEvent is manager_events.PhotoDeleted) {
      await _photoManager.handleEvent(finalManagerEvent);
    }
    
    // Route to upload manager
    if (finalManagerEvent is manager_events.SessionStartRequested ||
        finalManagerEvent is manager_events.SessionStopRequested ||
        finalManagerEvent is manager_events.SessionReset ||
        finalManagerEvent is manager_events.BatchLocationUpdated) {
      await _uploadManager.handleEvent(finalManagerEvent);
    }
    
    // Route to memory manager
    if (finalManagerEvent is manager_events.SessionStartRequested ||
        finalManagerEvent is manager_events.SessionStopRequested ||
        finalManagerEvent is manager_events.SessionPaused ||
        finalManagerEvent is manager_events.SessionResumed ||
        finalManagerEvent is manager_events.SessionReset ||
        finalManagerEvent is manager_events.MemoryUpdated ||
        finalManagerEvent is manager_events.RestoreSessionRequested) {
      await _memoryManager.handleEvent(finalManagerEvent);
    }
  }
  
  /// Convert main bloc events to manager events
  manager_events.ActiveSessionEvent? _convertToManagerEvent(ActiveSessionEvent mainEvent) {
    // Map main bloc events to manager events
    if (mainEvent is SessionStarted) {
      return manager_events.SessionStartRequested(
        sessionId: null, // Let lifecycle manager generate the session ID
        ruckWeightKg: mainEvent.ruckWeightKg,
        userWeightKg: mainEvent.userWeightKg,
        plannedRoute: mainEvent.plannedRoute,
        plannedRouteDistance: mainEvent.plannedRouteDistance,
        plannedRouteDuration: mainEvent.plannedRouteDuration,
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
      // Generate a unique photo path based on timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final photoPath = 'photo_$timestamp.jpg';
      return manager_events.PhotoAdded(
        photoPath: photoPath,
      );
    } else if (mainEvent is DeleteSessionPhotoRequested) {
      return manager_events.PhotoDeleted(
        photoId: mainEvent.photo.toString(),
      );
    } else if (mainEvent is LoadSessionForViewing) {
      return manager_events.RestoreSessionRequested(
        sessionId: mainEvent.sessionId,
      );
    } else if (mainEvent is SessionRecoveryRequested) {
      final sessionId = _lifecycleManager.activeSessionId ?? '';
      return manager_events.RecoveryRequested(
        sessionId: sessionId,
      );
    } else if (mainEvent is SessionReset) {
      return const manager_events.SessionReset();
    }
    
    // Return null for unmapped events
    return null;
  }
  
  /// Aggregate state from all managers and emit combined state
  void _aggregateAndEmitState() {
    final lifecycleState = _lifecycleManager.currentState;
    final locationState = _locationManager.currentState;
    final heartRateState = _heartRateManager.currentState;
    
    AppLogger.info('[COORDINATOR] Aggregating state: lifecycle(isActive=${lifecycleState.isActive}, sessionId=${lifecycleState.sessionId}, error=${lifecycleState.errorMessage})');
    AppLogger.info('[COORDINATOR] Location state: ${locationState.totalDistance}km');
    
    // Map manager states to ActiveSessionState
    if (!lifecycleState.isActive && lifecycleState.sessionId == null) {
      AppLogger.info('[COORDINATOR] Path: Initial state (not active, no session)');
      _currentAggregatedState = const ActiveSessionInitial();
    } else if (lifecycleState.errorMessage != null) {
      AppLogger.info('[COORDINATOR] Path: Failure state (error: ${lifecycleState.errorMessage})');
      _currentAggregatedState = ActiveSessionFailure(
        errorMessage: lifecycleState.errorMessage!,
      );
    } else if (!lifecycleState.isActive && lifecycleState.sessionId != null && (!_lifecycleManager.isPaused || lifecycleState.isSaving)) {
      AppLogger.info('[COORDINATOR] Path: Completion state (not active, has session)');
      
      // Use values from the previous running state instead of recalculating
      double finalDistance = 0.0;
      int finalCalories = 0;
      double finalElevationGain = 0.0;
      double finalElevationLoss = 0.0;
      
      if (_currentAggregatedState is ActiveSessionRunning) {
        final runningState = _currentAggregatedState as ActiveSessionRunning;
        finalDistance = runningState.distanceKm;
        finalCalories = runningState.calories.round();
        finalElevationGain = runningState.elevationGain;
        finalElevationLoss = runningState.elevationLoss;
        AppLogger.info('[COORDINATOR] Using calculated values from running state: distance=${finalDistance}km, calories=${finalCalories}, elevation=${finalElevationGain}m gain/${finalElevationLoss}m loss');
      } else {
        // Fallback to location manager if no running state available
        finalDistance = _locationManager.currentState.totalDistance;
        finalElevationGain = _locationManager.elevationGain;
        finalElevationLoss = _locationManager.elevationLoss;
        
        final userWeightKg = lifecycleState.userWeightKg;
        final ruckWeightKg = lifecycleState.ruckWeightKg;
        final duration = lifecycleState.duration;
        
        finalCalories = _calculateCalories(
          distanceKm: finalDistance,
          duration: duration,
          userWeightKg: userWeightKg,
          ruckWeightKg: ruckWeightKg,
        ).round();
        
        AppLogger.warning('[COORDINATOR] Using fallback calculation: distance=${finalDistance}km, calories=${finalCalories}');
      }
      
      final route = _locationManager.locationPoints;
      final duration = lifecycleState.duration;
      AppLogger.info('[COORDINATOR] DEBUG: LocationManager state - totalDistance=${_locationManager.currentState.totalDistance}, elevationGain=${_locationManager.elevationGain}, elevationLoss=${_locationManager.elevationLoss}');
      AppLogger.info('[COORDINATOR] Building completion state: distance=${finalDistance}km, duration=${duration.inSeconds}s, routePoints=${route.length}, calories=${finalCalories}');

      _currentAggregatedState = ActiveSessionCompleted(
        sessionId: lifecycleState.sessionId!,
        finalDistanceKm: finalDistance,
        finalDurationSeconds: duration.inSeconds,
        finalCalories: finalCalories,
        elevationGain: finalElevationGain,
        elevationLoss: finalElevationLoss,
        averagePace: finalDistance > 0 ? duration.inSeconds / finalDistance : null,
        route: route,
        heartRateSamples: _heartRateManager.heartRateSampleObjects,
        averageHeartRate: _heartRateManager.currentState.averageHeartRate.toInt(),
        minHeartRate: _heartRateManager.currentState.minHeartRate,
        maxHeartRate: _heartRateManager.currentState.maxHeartRate,
        sessionPhotos: _photoManager.photos,
        splits: _locationManager.splits,
        completedAt: DateTime.now(),
        isOffline: false,
        ruckWeightKg: lifecycleState.ruckWeightKg,
        steps: _currentSteps,
      );
      AppLogger.info('[COORDINATOR] Completion state built successfully');
      
      // Store completion data for lifecycle manager
      _sessionCompletionData = {
        'distance_km': finalDistance,
        'calories_burned': finalCalories,
        if (_lastCalorieMethod != null) 'calorie_method': _lastCalorieMethod,
        'elevation_gain_m': finalElevationGain,
        'elevation_loss_m': finalElevationLoss,
        'duration_seconds': lifecycleState.duration.inSeconds,
        'ruck_weight_kg': lifecycleState.ruckWeightKg,
        'user_weight_kg': lifecycleState.userWeightKg,
        'session_id': lifecycleState.sessionId,
        'start_time': lifecycleState.startTime?.toIso8601String(),
        'completed_at': DateTime.now().toIso8601String(),
        'average_pace': finalDistance > 0 ? (lifecycleState.duration.inMinutes / finalDistance) : 0.0,
        if (_currentSteps != null) 'steps': _currentSteps,
        // Heart rate zones: snapshot thresholds and time in zones
        ..._computeHrZonesPayload(),
      };
      AppLogger.info('[COORDINATOR] Stored completion data: distance=${finalDistance}km, calories=${finalCalories}, elevation=${finalElevationGain}m');
    } else if (lifecycleState.sessionId != null && (lifecycleState.isActive || (_lifecycleManager.isPaused && !lifecycleState.isSaving))) {
      AppLogger.info('[COORDINATOR] Path: Running state (active, has session)');
      // Aggregate states from all managers into ActiveSessionRunning
      final locationPoints = _locationManager.locationPoints;
      // Get user and ruck weight from lifecycle state
      final userWeightKg = lifecycleState.userWeightKg;
      final ruckWeightKg = lifecycleState.ruckWeightKg;
      
      final calories = _calculateCalories(
        distanceKm: locationState.totalDistance,
        duration: lifecycleState.duration,
        userWeightKg: userWeightKg,
        ruckWeightKg: ruckWeightKg,
      );
      
      // Update watch with calculated values from coordinator
      _locationManager.updateWatchWithCalculatedValues(
        calories: calories.round(),
        elevationGain: _locationManager.elevationGain,
        elevationLoss: _locationManager.elevationLoss,
      );
      
      _currentAggregatedState = ActiveSessionRunning(
        sessionId: lifecycleState.sessionId!,
        locationPoints: locationPoints,
        elapsedSeconds: lifecycleState.duration.inSeconds,
        distanceKm: locationState.totalDistance,
        ruckWeightKg: ruckWeightKg,
        userWeightKg: userWeightKg,
        calories: calories,
        elevationGain: _locationManager.elevationGain,
        elevationLoss: _locationManager.elevationLoss,
        isPaused: _lifecycleManager.isPaused,
        pace: locationState.currentPace,
        originalSessionStartTimeUtc: lifecycleState.startTime ?? DateTime.now(),
        totalPausedDuration: _lifecycleManager.totalPausedDuration,
        heartRateSamples: _heartRateManager.heartRateSampleObjects,
        latestHeartRate: heartRateState.currentHeartRate,
        minHeartRate: heartRateState.minHeartRate,
        maxHeartRate: heartRateState.maxHeartRate,
        isGpsReady: _locationManager.isGpsReady,
        hasGpsAccess: locationState.isTracking,
        photos: _photoManager.photos,
        isPhotosLoading: _photoManager.isPhotosLoading,
        isUploading: _uploadManager.isUploading,
        splits: _locationManager.splits,
        terrainSegments: _locationManager.terrainSegments,
        plannedRoute: _plannedRoute, // Pass planned route for navigation
        plannedRouteDistance: _plannedRouteDistance, // Pass route distance
        plannedRouteDuration: _plannedRouteDuration, // Pass route duration
        steps: _currentSteps,
      );
    } else {
      AppLogger.warning('[COORDINATOR] Unmatched state combination: isActive=${lifecycleState.isActive}, sessionId=${lifecycleState.sessionId}, error=${lifecycleState.errorMessage}');
      // Default to initial state for unmatched combinations
      _currentAggregatedState = const ActiveSessionInitial();
    }
    
    // Log aggregated state only when the state TYPE changes
    if (_currentAggregatedState.runtimeType != _lastLoggedAggregatedStateType) {
      AppLogger.debug('[COORDINATOR] Aggregated state: ${_currentAggregatedState.runtimeType}');
      _lastLoggedAggregatedStateType = _currentAggregatedState.runtimeType;
    }
    // Trigger internal event to emit the aggregated state
    add(const StateAggregationRequested());
  }
  
  double _calculateCalories({
    required double distanceKm,
    required Duration duration,
    required double userWeightKg,
    required double ruckWeightKg,
  }) {
    if (distanceKm <= 0 || duration.inMinutes <= 0) return 0.0;
    
    // Get elevation data from location manager
    final elevationGain = _locationManager.elevationGain;
    final elevationLoss = _locationManager.elevationLoss;
    
    // Calculate terrain multiplier from terrain segments
    final terrainMultiplier = _calculateTerrainMultiplier();
    
    // Get user's profile fields for calorie calculation
    String? gender;
    String? dateOfBirth;
    int? restingHr;
    int? maxHr;
    String? calorieMethod;
    bool activeOnly = false;
    try {
      final authState = GetIt.instance<AuthBloc>().state;
      if (authState is Authenticated) {
        final user = authState.user;
        gender = user.gender;
        dateOfBirth = user.dateOfBirth;
        restingHr = user.restingHr;
        maxHr = user.maxHr;
        calorieMethod = user.calorieMethod;
        activeOnly = user.calorieActiveOnly ?? false;
      }
    } catch (e) {
      AppLogger.warning('[COORDINATOR] Could not get user profile for calorie calculation: $e');
    }

    // Derive age from birthdate if available
    int age = 30;
    if (dateOfBirth != null) {
      try {
        final dob = DateTime.tryParse(dateOfBirth);
        if (dob != null) {
          final now = DateTime.now();
          age = now.year - dob.year - ((now.month < dob.month || (now.month == dob.month && now.day < dob.day)) ? 1 : 0);
          if (age < 10 || age > 100) {
            age = 30; // sanity bounds
          }
        }
      } catch (_) {}
    }
    
    // Use MetCalculator for sophisticated calorie calculation
    _lastCalorieMethod = (calorieMethod ?? 'fusion');
    final calories = MetCalculator.calculateRuckingCalories(
      userWeightKg: userWeightKg,
      ruckWeightKg: ruckWeightKg,
      distanceKm: distanceKm,
      elapsedSeconds: duration.inSeconds,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      gender: gender,
      terrainMultiplier: terrainMultiplier,
      calorieMethod: _lastCalorieMethod!,
      heartRateSamples: _heartRateManager.heartRateSampleObjects,
      age: age,
      activeOnly: activeOnly,
    );
    
    AppLogger.debug('[COORDINATOR] CALORIE_CALCULATION: '
        'distance=${distanceKm.toStringAsFixed(2)}km, '
        'duration=${duration.inMinutes.toStringAsFixed(1)}min, '
        'userWeight=${userWeightKg.toStringAsFixed(1)}kg, '
        'ruckWeight=${ruckWeightKg.toStringAsFixed(1)}kg, '
        'elevationGain=${elevationGain.toStringAsFixed(1)}m, '
        'elevationLoss=${elevationLoss.toStringAsFixed(1)}m, '
        'terrainMultiplier=${terrainMultiplier.toStringAsFixed(2)}x, '
        'finalCalories=${calories.toStringAsFixed(0)}');
    
    return calories;
  }

  Map<String, dynamic> _computeHrZonesPayload() {
    try {
      // Pull user profile for resting/max HR
      int? restingHr;
      int? maxHr;
      final authState = GetIt.instance<AuthBloc>().state;
      if (authState is Authenticated) {
        restingHr = authState.user.restingHr;
        maxHr = authState.user.maxHr;
      }
      final samples = _heartRateManager.heartRateSampleObjects;
      if (samples.isEmpty || restingHr == null || maxHr == null) return {};
      if (maxHr <= restingHr) return {};

      final zones = HeartRateZoneService.zonesFromProfile(restingHr: restingHr, maxHr: maxHr);
      final timeIn = HeartRateZoneService.timeInZonesSeconds(samples: samples, zones: zones);
      final snapshot = zones
          .map((z) => {
                'name': z.name,
                'min_bpm': z.min,
                'max_bpm': z.max,
                'color': z.color.value,
              })
          .toList();
      return {
        'hr_zone_snapshot': snapshot,
        'time_in_zones': timeIn,
      };
    } catch (_) {
      return {};
    }
  }
  
  /// Calculates the aggregate terrain multiplier based on terrain segments
  /// Uses distance-weighted average of energy multipliers
  double _calculateTerrainMultiplier() {
    final terrainSegments = _locationManager.terrainSegments;
    
    if (terrainSegments.isEmpty) {
      // No terrain data available, use default multiplier
      return 1.0;
    }
    
    double totalDistance = 0.0;
    double weightedMultiplier = 0.0;
    
    for (final segment in terrainSegments) {
      final segmentDistance = segment.distanceKm;
      totalDistance += segmentDistance;
      weightedMultiplier += segment.energyMultiplier * segmentDistance;
    }
    
    if (totalDistance <= 0) {
      return 1.0;
    }
    
    final avgMultiplier = weightedMultiplier / totalDistance;
    
    AppLogger.debug('[COORDINATOR] TERRAIN_MULTIPLIER: '
        'segments=${terrainSegments.length}, '
        'totalDistance=${totalDistance.toStringAsFixed(2)}km, '
        'avgMultiplier=${avgMultiplier.toStringAsFixed(2)}x');
    
    return avgMultiplier;
  }
  
  // Event handlers that delegate to managers
  Future<void> _onSessionStarted(
    SessionStarted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session start requested');
    // Start live steps if enabled in preferences
    try {
      final prefs = GetIt.instance<SharedPreferences>();
      final enabled = prefs.getBool('live_step_tracking') ?? false;
      if (enabled) {
        final startTime = DateTime.now();
        _stepsSub?.cancel();
        _stepsSub = _healthService.startLiveSteps(startTime).listen((total) {
          _currentSteps = total;
          add(const StateAggregationRequested());
        });
      }
    } catch (_) {}
    
    // Store planned route data for navigation
    _plannedRoute = event.plannedRoute;
    _plannedRouteDistance = event.plannedRouteDistance;
    _plannedRouteDuration = event.plannedRouteDuration;
    
    if (_plannedRoute != null) {
      AppLogger.info('[COORDINATOR] Stored planned route: ${_plannedRoute!.length} points, ${_plannedRouteDistance}km, ${_plannedRouteDuration}min');
    }
    
    await _routeEventToManagers(event);
    add(const TimerStarted());
  }
  
  Future<void> _onSessionCompleted(
    SessionCompleted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session completion started');
    // Stop steps
    try { _stepsSub?.cancel(); } catch (_) {}
    try { _healthService.stopLiveSteps(); } catch (_) {}
    AppLogger.info('[COORDINATOR] Current aggregated state: ${_currentAggregatedState.runtimeType}');
    AppLogger.info('[COORDINATOR] Lifecycle state before: isActive=${_lifecycleManager.currentState.isActive}, sessionId=${_lifecycleManager.currentState.sessionId}');
    
    // Fallback: If live steps were not tracked, compute total steps once at completion
    try {
      if (_currentSteps == null) {
        final startTime = _lifecycleManager.currentState.startTime;
        if (startTime != null) {
          final computedSteps = await _healthService.getStepsBetween(startTime, DateTime.now());
          _currentSteps = computedSteps;
          AppLogger.info('[COORDINATOR] Computed steps at completion: $_currentSteps');
        } else {
          AppLogger.debug('[COORDINATOR] No startTime available to compute steps at completion');
        }
      } else {
        AppLogger.debug('[COORDINATOR] Skipping step recompute; live steps already present: $_currentSteps');
      }
    } catch (e) {
      AppLogger.warning('[COORDINATOR] Failed to compute steps at completion: $e');
    }

    // Stop the timer by pausing first
    AppLogger.info('[COORDINATOR] Pausing session first');
    add(const SessionPaused());
    
    try {
      AppLogger.info('[COORDINATOR] Routing event to managers');
      await _routeEventToManagers(event);
      
      AppLogger.info('[COORDINATOR] Lifecycle state after: isActive=${_lifecycleManager.currentState.isActive}, sessionId=${_lifecycleManager.currentState.sessionId}');
      
      // Aggregate and emit the completed state
      AppLogger.info('[COORDINATOR] Aggregating state');
      _aggregateAndEmitState();
      AppLogger.info('[COORDINATOR] New aggregated state: ${_currentAggregatedState.runtimeType}');
      
      if (_currentAggregatedState is ActiveSessionCompleted) {
        final completedState = _currentAggregatedState as ActiveSessionCompleted;
        AppLogger.info('[COORDINATOR] Session completed successfully: sessionId=${completedState.sessionId}, distance=${completedState.finalDistanceKm}km, duration=${completedState.finalDurationSeconds}s');
      }
      
      AppLogger.info('[COORDINATOR] Emitting completed state');
      emit(_currentAggregatedState);
      
      // DELAYED: Clear local storage after a delay to ensure UI navigation completes first
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await _storageService.remove('active_session_data');
          await _storageService.remove('active_session_last_save');
          AppLogger.info('[COORDINATOR] Local session storage cleared after completion (delayed)');
        } catch (clearError) {
          AppLogger.error('[COORDINATOR] Failed to clear local storage after completion: $clearError');
        }
      });
      
      AppLogger.info('[COORDINATOR] Session completion process finished');
      
    } catch (e) {
      // Handle session completion errors gracefully
      if (e.toString().contains('Session not in progress') || 
          e.toString().contains('BadRequestException')) {
        AppLogger.warning('[COORDINATOR] Session completion failed - session already completed or invalid state: $e');
        
        // Force completion state even if server-side completion failed
        _aggregateAndEmitState();
        
        // If we don't have a completed state, create one
        if (!(_currentAggregatedState is ActiveSessionCompleted)) {
          final sessionId = _lifecycleManager.currentState.sessionId ?? 'unknown';
          emit(ActiveSessionCompleted(
            sessionId: sessionId,
            finalDistanceKm: 0.0,
            finalDurationSeconds: 0,
            finalCalories: 0,
            elevationGain: 0.0,
            elevationLoss: 0.0,
            averagePace: 0.0,
            route: [],
            heartRateSamples: [],
            sessionPhotos: [],
            splits: [],
            completedAt: DateTime.now(),
            ruckWeightKg: 0.0,
          ));
        } else {
          emit(_currentAggregatedState);
        }
        
        AppLogger.info('[COORDINATOR] Session completion recovered from server sync error');
      } else if (e.toString().contains('NotFoundException') || 
                 e.toString().contains('Session not found') ||
                 e.toString().contains('failed to delete') ||
                 e.toString().contains('status code of 404') ||
                 e.toString().contains('DioException [bad response]') ||
                 e.toString().contains('session_delete failed') ||
                 (e.toString().contains('404') && e.toString().contains('session'))) {
        AppLogger.warning('[COORDINATOR] Session not found (404) - cleaning up and navigating to homepage: $e');
        
        // DELAYED: Clean up local storage for the orphaned session after UI navigation
        final sessionId = _lifecycleManager.currentState.sessionId ?? 'unknown';
        Future.delayed(const Duration(seconds: 3), () async {
          try {
            // Use storage service to clear session data
            await _storageService.remove('active_session_data');
            await _storageService.remove('active_session_last_save');
            AppLogger.info('[COORDINATOR] Local session storage cleared for session: $sessionId (delayed)');
          } catch (cleanupError) {
            AppLogger.error('[COORDINATOR] Failed to clean local storage: $cleanupError');
          }
        });
        
        // Reset coordinator state to clean state
        await _lifecycleManager.reset();
        
        // Navigate to homepage by emitting initial state
        // The UI listener will detect this transition and navigate accordingly
        emit(const ActiveSessionInitial());
        
        AppLogger.info('[COORDINATOR] Session not found - reset to initial state');
      } else {
        // Handle other errors by emitting failure state
        AppLogger.error('[COORDINATOR] Session completion failed with unexpected error: $e');
        emit(ActiveSessionFailure(errorMessage: 'Session completion failed: $e'));
      }
    }
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
    await _routeEventToManagers(event);
  }
  
  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
  }
  
  Future<void> _onTakePhotoRequested(
    TakePhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
  }
  
  Future<void> _onDeleteSessionPhotoRequested(
    DeleteSessionPhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
    _aggregateAndEmitState();
  }
  
  Future<void> _onLoadSessionForViewing(
    LoadSessionForViewing event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.debug('[COORDINATOR] Loading session for viewing');
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
    await _routeEventToManagers(event);
  }
  
  Future<void> _onSessionReset(
    SessionReset event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Session reset requested');
    await _routeEventToManagers(event);
    
    // Reset to initial state
    _currentAggregatedState = const ActiveSessionInitial();
    emit(_currentAggregatedState);
  }
  
  Future<void> _onBatchLocationUpdated(
    BatchLocationUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
  }
  
  Future<void> _onHeartRateBatchUploadRequested(
    HeartRateBatchUploadRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    await _routeEventToManagers(event);
  }
  
  Future<void> _onStateAggregationRequested(
    StateAggregationRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    emit(_currentAggregatedState);
  }
  
  /// Handle memory pressure detection
  Future<void> _onMemoryPressureDetected(
    MemoryPressureDetected event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.warning('[COORDINATOR] Memory pressure detected');
    
    // Create manager event with memory usage information
    final memoryInfo = MemoryMonitorService.getCurrentMemoryInfo();
    final actualMemoryUsageMb = memoryInfo['memory_usage_mb'] as double;
    
    final managerEvent = manager_events.MemoryPressureDetected(
      memoryUsageMb: actualMemoryUsageMb,
      timestamp: DateTime.now(),
    );
    
    // Delegate to memory pressure manager if available
    await _memoryPressureManager.handleEvent(managerEvent);
    
    // Trigger aggressive memory management in all managers
    await _locationManager.handleEvent(managerEvent);
    await _heartRateManager.handleEvent(managerEvent);
    await _uploadManager.handleEvent(managerEvent);
    
    // Log memory pressure for diagnostics
    AppLogger.error('[COORDINATOR] MEMORY_PRESSURE: ${managerEvent.memoryUsageMb}MB detected, triggering aggressive cleanup');
  }
  
  /// Handle crash recovery check on app startup
  Future<void> _onCheckForCrashedSession(
    CheckForCrashedSession event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Crash recovery check requested');
    
    try {
      // Delegate to lifecycle manager to check for crashed sessions
      await _lifecycleManager.checkForCrashedSession();
      if (_lifecycleManager.currentState.isRecovered) {
        add(SessionRecovered());
      }
      
      AppLogger.info('[COORDINATOR] Crash recovery check completed');
      
    } catch (e) {
      AppLogger.error('[COORDINATOR] Error during crash recovery check: $e');
      // Continue gracefully - not critical for app startup
    }
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
    await _memoryPressureManager.dispose();
    
    return super.close();
  }
  
  /// Handle recovered data from crash recovery
  void _handleRecoveredMetrics(Map<String, dynamic> recoveredData) {
    AppLogger.info('[COORDINATOR] Handling recovery data: $recoveredData');
    
    try {
      final isCrashRecovery = recoveredData['is_crash_recovery'] as bool? ?? false;
      
      if (isCrashRecovery) {
        // Actual crash recovery - restore accumulated metrics
        final distance = (recoveredData['distance_km'] as num?)?.toDouble() ?? 0.0;
        final elevationGain = (recoveredData['elevation_gain'] as num?)?.toDouble() ?? 0.0;
        final elevationLoss = (recoveredData['elevation_loss'] as num?)?.toDouble() ?? 0.0;
        final calories = (recoveredData['calories'] as num?)?.toDouble() ?? 0.0;
        final recoveryDuration = (recoveredData['recovery_duration_minutes'] as num?)?.toInt() ?? 0;
        
        AppLogger.info('[COORDINATOR] CRASH RECOVERY: Restoring ${distance}km, ${elevationGain}m gain, ${calories} cal after ${recoveryDuration} min gap');
        
        // Initialize location manager with recovered metrics
        _locationManager.restoreMetricsFromRecovery(
          totalDistanceKm: distance,
          elevationGainM: elevationGain,
          elevationLossM: elevationLoss,
        );
        
      } else {
        // Regular recovery callback - don't override live calculations
        AppLogger.info('[COORDINATOR] Regular recovery callback - letting live calculations continue');
      }
      
      // Force state aggregation
      Timer(const Duration(milliseconds: 500), () {
        _aggregateAndEmitState();
      });
      
    } catch (e) {
      AppLogger.error('[COORDINATOR] Error handling recovery data: $e');
    }
  }
  
  /// Get stored completion data for lifecycle manager
  Map<String, dynamic>? getSessionCompletionData() {
    return _sessionCompletionData;
  }
}
