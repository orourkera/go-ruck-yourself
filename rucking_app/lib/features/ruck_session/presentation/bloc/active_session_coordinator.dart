import 'dart:async';
import 'dart:io';
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
import 'package:rucking_app/core/services/weather_service.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/events/session_events.dart'
    as manager_events;
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
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';

/// Main coordinator that orchestrates all session managers
class ActiveSessionCoordinator
    extends Bloc<ActiveSessionEvent, ActiveSessionState> {
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
  final OpenAIService _openAIService;

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

  // Current aggregated state
  ActiveSessionState _currentAggregatedState = const ActiveSessionInitial();

  // Store last known running state metrics to use during completion
  double _lastRunningDistance = 0.0;
  int _lastRunningCalories = 0;
  double _lastRunningElevationGain = 0.0;
  double _lastRunningElevationLoss = 0.0;
  Map<String, dynamic>? _sessionCompletionData;
  int? _currentSteps;
  StreamSubscription<int>? _stepsSub;
  String? _lastCalorieMethod;
  double? _recoveredCalories; // Calories from crash recovery
  // Diagnostics for emission tracing
  int _emitSeq = 0;
  double? _lastEmittedDistanceKm;
  DateTime? _lastEmitAt;

  // Store planned route for navigation
  List<latlong.LatLng>? _plannedRoute;
  double? _plannedRouteDistance;
  int? _plannedRouteDuration;

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
    required OpenAIService openAIService,
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
        _openAIService = openAIService,
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
    on<UploadSessionPhotosRequested>(_onUploadSessionPhotosRequested);
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

    // Set event emitter callback for heart rate manager
    _heartRateManager.setEventEmitter((event) {
      // Heart rate manager now emits main bloc events directly
      if (event is HeartRateBatchUploadRequested) {
        add(event);
      } else {
        add(event);
      }
    });

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
        AppLogger.debug(
            '[COORDINATOR] Lifecycle state updated: ${state.isActive}');
        _aggregateAndEmitState();
      }),
    );

    // Subscribe to location manager state changes
    _managerSubscriptions.add(
      _locationManager.stateStream.listen((state) {
        AppLogger.debug(
            '[COORDINATOR] Location state updated: distance=${state.totalDistance}');
        _aggregateAndEmitState();
      }),
    );

    // Subscribe to heart rate manager state changes
    _managerSubscriptions.add(
      _heartRateManager.stateStream.listen((state) {
        AppLogger.debug(
            '[COORDINATOR] Heart rate state updated: current=${state.currentHeartRate}');
        _aggregateAndEmitState();
      }),
    );

    // Subscribe to photo manager state changes
    _managerSubscriptions.add(
      _photoManager.stateStream.listen((state) {
        AppLogger.debug(
            '[COORDINATOR] Photo state updated: count=${state.photos.length}');
        _aggregateAndEmitState();
      }),
    );

    // Subscribe to upload manager state changes
    _managerSubscriptions.add(
      _uploadManager.stateStream.listen((state) {
        AppLogger.debug(
            '[COORDINATOR] Upload state updated: location=${state.pendingLocationPoints}, heartRate=${state.pendingHeartRateSamples}');
        _aggregateAndEmitState();
      }),
    );

    // Subscribe to memory manager state changes
    _managerSubscriptions.add(
      _memoryManager.stateStream.listen((state) {
        final hasSession =
            state is MemoryState ? state.hasActiveSession : false;
        AppLogger.debug(
            '[COORDINATOR] Memory state updated: hasSession=$hasSession');
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
      AppLogger.warning(
          '[COORDINATOR] No manager event mapping for ${event.runtimeType}');
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
        AppLogger.debug(
            '[COORDINATOR] Using session ID from lifecycle manager: $sessionId');
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
        finalManagerEvent is manager_events.BatchLocationUpdated ||
        finalManagerEvent is manager_events.HeartRateBatchUploadRequested) {
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
  manager_events.ActiveSessionEvent? _convertToManagerEvent(
      ActiveSessionEvent mainEvent) {
    // Map main bloc events to manager events
    if (mainEvent is SessionStarted) {
      return manager_events.SessionStartRequested(
        sessionId:
            mainEvent.sessionId, // Pass through sessionId from CreateScreen
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
    } else if (mainEvent is HeartRateBatchUploadRequested) {
      return manager_events.HeartRateBatchUploadRequested(
          samples: mainEvent.samples);
    }

    // Return null for unmapped events
    return null;
  }

  /// Aggregate state from all managers and emit combined state
  void _aggregateAndEmitState() {
    final lifecycleState = _lifecycleManager.currentState;
    final locationState = _locationManager.currentState;
    final heartRateState = _heartRateManager.currentState;

    AppLogger.info(
        '[COORDINATOR] Aggregating state: lifecycle(isActive=${lifecycleState.isActive}, sessionId=${lifecycleState.sessionId}, error=${lifecycleState.errorMessage})');
    AppLogger.info(
        '[COORDINATOR] Location state: ${locationState.totalDistance}km');

    // Map manager states to ActiveSessionState
    if (!lifecycleState.isActive && lifecycleState.sessionId == null) {
      AppLogger.info(
          '[COORDINATOR] Path: Initial state (not active, no session)');
      _currentAggregatedState = const ActiveSessionInitial();
    } else if (lifecycleState.errorMessage != null) {
      AppLogger.info(
          '[COORDINATOR] Path: Failure state (error: ${lifecycleState.errorMessage})');
      _currentAggregatedState = ActiveSessionFailure(
        errorMessage: lifecycleState.errorMessage!,
      );
    } else if (!lifecycleState.isActive && lifecycleState.sessionId != null) {
      AppLogger.info(
          '[COORDINATOR] Path: Completion state (not active, has session)');

      // Use values from the previous running state instead of recalculating
      double finalDistance = 0.0;
      int finalCalories = 0;
      double finalElevationGain = 0.0;
      double finalElevationLoss = 0.0;

      AppLogger.info(
          '[COORDINATOR] Current aggregated state type: ${_currentAggregatedState.runtimeType}');
      AppLogger.info(
          '[COORDINATOR] Location manager distance: ${_locationManager.totalDistance}km');
      AppLogger.info(
          '[COORDINATOR] Location manager elevation: ${_locationManager.elevationGain}m gain/${_locationManager.elevationLoss}m loss');

      if (_currentAggregatedState is ActiveSessionRunning) {
        final runningState = _currentAggregatedState as ActiveSessionRunning;
        finalDistance = runningState.distanceKm;
        finalCalories = runningState.calories.round();
        finalElevationGain = runningState.elevationGain;
        finalElevationLoss = runningState.elevationLoss;
        AppLogger.info(
            '[COORDINATOR] Using calculated values from running state: distance=${finalDistance}km, calories=${finalCalories}, elevation=${finalElevationGain}m gain/${finalElevationLoss}m loss');
      } else if (_lastRunningDistance > 0.0 ||
          _lastRunningCalories > 0 ||
          _lastRunningElevationGain > 0.0) {
        // Use preserved running state metrics from last known good state
        finalDistance = _lastRunningDistance;
        finalCalories = _lastRunningCalories;
        finalElevationGain = _lastRunningElevationGain;
        finalElevationLoss = _lastRunningElevationLoss;
        AppLogger.info(
            '[COORDINATOR] Using preserved running state metrics: distance=${finalDistance}km, calories=${finalCalories}, elevation=${finalElevationGain}m gain/${finalElevationLoss}m loss');
      } else {
        // Final fallback to location manager if no preserved state available
        // Use getter which returns preserved cumulative distance
        finalDistance = _locationManager.totalDistance;
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

        AppLogger.warning(
            '[COORDINATOR] Using fallback calculation: distance=${finalDistance}km, calories=${finalCalories}');
      }

      final route = _locationManager.locationPoints;
      final duration = lifecycleState.duration;
      AppLogger.info(
          '[COORDINATOR] DEBUG: LocationManager state - totalDistance=${_locationManager.totalDistance}, elevationGain=${_locationManager.elevationGain}, elevationLoss=${_locationManager.elevationLoss}');
      AppLogger.info(
          '[CALORIE_DEBUG] duration.inSeconds: ${duration.inSeconds}');
      AppLogger.info(
          '[CALORIE_DEBUG] duration.inMinutes: ${duration.inMinutes}');

      // CRITICAL FIX: Use actual movement time, not session duration which may include pauses
      final actualMovementSeconds = finalDistance > 0
          ? (finalDistance /
                  (finalDistance / (duration.inSeconds / 3600.0)) *
                  3600.0)
              .round()
          : duration.inSeconds;
      AppLogger.info(
          '[CALORIE_DEBUG] actualMovementSeconds (calculated): $actualMovementSeconds');
      AppLogger.info(
          '[COORDINATOR] Building completion state: distance=${finalDistance}km, duration=${actualMovementSeconds}s, routePoints=${route.length}, calories=${finalCalories}');

      _currentAggregatedState = ActiveSessionCompleted(
        sessionId: lifecycleState.sessionId!,
        finalDistanceKm: finalDistance,
        finalDurationSeconds: actualMovementSeconds,
        finalCalories: finalCalories,
        elevationGain: finalElevationGain,
        elevationLoss: finalElevationLoss,
        averagePace:
            finalDistance > 0 ? duration.inSeconds / finalDistance : null,
        route: route,
        heartRateSamples: _heartRateManager.heartRateSampleObjects,
        averageHeartRate:
            _heartRateManager.currentState.averageHeartRate?.toInt(),
        minHeartRate: _heartRateManager.currentState.minHeartRate,
        maxHeartRate: _heartRateManager.currentState.maxHeartRate,
        sessionPhotos: _photoManager.photos,
        splits: _locationManager.splits,
        completedAt: DateTime.now(),
        isOffline: false,
        ruckWeightKg: lifecycleState.ruckWeightKg,
        steps: _currentSteps ?? _estimateStepsFromDistance(finalDistance),
      );
      // Log steps in completed state for UI verification
      AppLogger.info(
          '[STEPS UI] [COORDINATOR] Completed state steps: ${_currentSteps ?? _estimateStepsFromDistance(finalDistance)} (${_currentSteps != null ? 'live tracked' : 'estimated from distance'})');
      AppLogger.info('[COORDINATOR] Completion state built successfully');

      // Calculate actual duration from timestamps to avoid corruption
      final actualDuration = lifecycleState.startTime != null
          ? DateTime.now().difference(lifecycleState.startTime!)
          : lifecycleState.duration;

      AppLogger.info(
          '[COORDINATOR] Duration calculation: lifecycle=${lifecycleState.duration.inSeconds}s, actual=${actualDuration.inSeconds}s');

      // Store completion data for lifecycle manager
      _sessionCompletionData = {
        // Send distance_km as fallback - backend will use this if GPS calculation fails
        'distance_km': finalDistance,
        'calories_burned': finalCalories,
        if (_lastCalorieMethod != null) 'calorie_method': _lastCalorieMethod,
        'elevation_gain_m': finalElevationGain,
        'elevation_loss_m': finalElevationLoss,
        'duration_seconds': actualDuration
            .inSeconds, // Use calculated duration instead of lifecycle state
        'ruck_weight_kg': lifecycleState.ruckWeightKg,
        'user_weight_kg': lifecycleState.userWeightKg,
        'session_id': lifecycleState.sessionId,
        'start_time': lifecycleState.startTime?.toIso8601String(),
        'completed_at': DateTime.now().toIso8601String(),
        'average_pace': finalDistance > 0
            ? (actualDuration.inMinutes / finalDistance)
            : 0.0,
        'steps': _currentSteps ?? _estimateStepsFromDistance(finalDistance),
        // Heart rate zones: snapshot thresholds and time in zones
        ..._computeHrZonesPayload(),
        // Heart rate aggregates expected by backend
        'avg_heart_rate':
            _heartRateManager.currentState.averageHeartRate?.round(),
        'min_heart_rate': _heartRateManager.currentState.minHeartRate,
        'max_heart_rate': _heartRateManager.currentState.maxHeartRate,
        // Don't send location_points - they're already uploaded during session via location-batch endpoint
        // Don't send heart_rate_samples - they're uploaded via heart-rate-chunk endpoint if needed
      };
      AppLogger.info(
          '[COORDINATOR] Stored completion data: distance=${finalDistance}km, calories=${finalCalories}, elevation=${finalElevationGain}m');
    } else if (lifecycleState.sessionId != null && lifecycleState.isActive) {
      AppLogger.info('[COORDINATOR] Path: Running state (active, has session)');
      // Aggregate states from all managers into ActiveSessionRunning
      final locationPoints = _locationManager.locationPoints;
      // Diagnostics: capture previous distance if we were already running
      double? prevDistance;
      if (_currentAggregatedState is ActiveSessionRunning) {
        prevDistance =
            (_currentAggregatedState as ActiveSessionRunning).distanceKm;
      }
      // Get user and ruck weight from lifecycle state
      final userWeightKg = lifecycleState.userWeightKg;
      final ruckWeightKg = lifecycleState.ruckWeightKg;

      final calories = _calculateCalories(
        distanceKm: locationState.totalDistance,
        duration: lifecycleState.duration,
        userWeightKg: userWeightKg,
        ruckWeightKg: ruckWeightKg,
      ).round();

      // Update watch with calculated values from coordinator
      _locationManager.updateWatchWithCalculatedValues(
        calories: calories.round(),
        elevationGain: _locationManager.elevationGain,
        elevationLoss: _locationManager.elevationLoss,
        steps: _currentSteps,
      );

      // Debug log elevation values
      if (locationState.elevationGain > 0 || locationState.elevationLoss > 0) {
        print(
            '[COORDINATOR] Sending elevation to UI: gain=${locationState.elevationGain.toStringAsFixed(1)}m, loss=${locationState.elevationLoss.toStringAsFixed(1)}m');
      }

      _currentAggregatedState = ActiveSessionRunning(
        sessionId: lifecycleState.sessionId!,
        userWeightKg: lifecycleState.userWeightKg,
        ruckWeightKg: lifecycleState.ruckWeightKg,
        locationPoints: locationPoints,
        elapsedSeconds: lifecycleState.duration.inSeconds,
        distanceKm: locationState.totalDistance,
        elevationGain: locationState.elevationGain,
        elevationLoss: locationState.elevationLoss,
        calories: calories.toDouble(),
        pace: locationState.currentPace,
        isPaused: _lifecycleManager.isPaused,
        originalSessionStartTimeUtc:
            lifecycleState.startTime ?? DateTime.now().toUtc(),
        totalPausedDuration:
            lifecycleState.totalPausedDuration ?? Duration.zero,
        latestHeartRate: heartRateState.currentHeartRate,
        minHeartRate: heartRateState.minHeartRate,
        maxHeartRate: heartRateState.maxHeartRate,
        heartRateSamples: _heartRateManager.heartRateSampleObjects,
        isGpsReady: _locationManager.isGpsReady,
        plannedRoute: null, // TODO: Get planned route from correct source
        plannedRouteDistance: null,
        plannedRouteDuration: null,
        photos: _photoManager.photos,
        isPhotosLoading: _photoManager.isPhotosLoading,
        isUploading: _uploadManager.isUploading,
        splits: _locationManager.splits,
        terrainSegments: _locationManager.terrainSegments,
        steps: _currentSteps,
      );

      // Preserve running state metrics for use during completion
      _lastRunningDistance = locationState.totalDistance;
      _lastRunningCalories = calories;
      _lastRunningElevationGain = locationState.elevationGain;
      _lastRunningElevationLoss = locationState.elevationLoss;

      // Log steps in running state for UI verification
      AppLogger.info(
          '[STEPS UI] [COORDINATOR] Running state steps: ${_currentSteps ?? 'null'}');
      // Diagnostics: log aggregation distance change
      if (prevDistance != null) {
        final delta = (locationState.totalDistance - prevDistance);
        AppLogger.debug(
            '[COORDINATOR][AGG] distanceKm: prev=${prevDistance.toStringAsFixed(3)} -> new=${locationState.totalDistance.toStringAsFixed(3)} (Δ=${delta.toStringAsFixed(3)} km), elapsed=${lifecycleState.duration.inSeconds}s, paused=${_lifecycleManager.isPaused}');
      } else {
        AppLogger.debug(
            '[COORDINATOR][AGG] distanceKm initialized: ${locationState.totalDistance.toStringAsFixed(3)} km, elapsed=${lifecycleState.duration.inSeconds}s, paused=${_lifecycleManager.isPaused}');
      }
    } else {
      AppLogger.warning(
          '[COORDINATOR] Unmatched state combination: isActive=${lifecycleState.isActive}, sessionId=${lifecycleState.sessionId}, error=${lifecycleState.errorMessage}');
      // Default to initial state for unmatched combinations
      _currentAggregatedState = const ActiveSessionInitial();
    }

    // Log aggregated state only when the state TYPE changes
    if (_currentAggregatedState.runtimeType != _lastLoggedAggregatedStateType) {
      AppLogger.debug(
          '[COORDINATOR] Aggregated state: ${_currentAggregatedState.runtimeType}');
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
      AppLogger.warning(
          '[COORDINATOR] Could not get user profile for calorie calculation: $e');
    }

    // Derive age from birthdate if available
    int age = 30;
    if (dateOfBirth != null) {
      try {
        final dob = DateTime.tryParse(dateOfBirth);
        if (dob != null) {
          final now = DateTime.now();
          age = now.year -
              dob.year -
              ((now.month < dob.month ||
                      (now.month == dob.month && now.day < dob.day))
                  ? 1
                  : 0);
          if (age < 10 || age > 100) {
            age = 30; // sanity bounds
          }
        }
      } catch (_) {}
    }

    // Skip weather data for now to keep method synchronous
    // Weather integration can be added later as an async enhancement
    double? temperature;
    double? windSpeed;
    double? humidity;
    bool isRaining = false;

    // Use MetCalculator with the user's preferred calorie method (fallback to 'fusion')
    _lastCalorieMethod = (calorieMethod ?? 'fusion');
    // CRITICAL FIX: Calculate actual movement time to exclude pauses
    // If we moved distance in duration, what would be reasonable active time?
    final avgSpeedKmh = distanceKm > 0 && duration.inSeconds > 0
        ? (distanceKm / (duration.inSeconds / 3600.0))
        : 0.0;
    final reasonableSpeedKmh =
        avgSpeedKmh.clamp(3.0, 8.0); // 3-8 km/h reasonable rucking speed
    final estimatedActiveSeconds = distanceKm > 0
        ? ((distanceKm / reasonableSpeedKmh) * 3600.0).round()
        : duration.inSeconds;

    // Use the shorter of actual duration or estimated active time to prevent inflation
    final activeSeconds = duration.inSeconds < estimatedActiveSeconds
        ? duration.inSeconds
        : estimatedActiveSeconds;

    // Calorie model note:
    // - MET path inside MetCalculator already accounts for ruck load via the MET value,
    //   so the MET calculation uses BODY WEIGHT ONLY to avoid double counting load.
    // - Mechanical path (Pandolf-style) handles load explicitly via mass/coefficients.
    // - Fusion blends HR with mechanical and applies safety caps.
    final calories = MetCalculator.calculateRuckingCalories(
      userWeightKg: userWeightKg,
      ruckWeightKg: ruckWeightKg,
      distanceKm: distanceKm,
      elapsedSeconds: activeSeconds,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      gender: gender,
      terrainMultiplier: terrainMultiplier,
      calorieMethod: _lastCalorieMethod!,
      heartRateSamples: _heartRateManager.heartRateSampleObjects,
      age: age,
      activeOnly: activeOnly,
      temperatureCelsius: temperature,
      windSpeedKmh: windSpeed,
      humidity: humidity,
      isRaining: isRaining,
    );

    // Add recovered calories as baseline for crash recovery sessions
    final totalCalories = calories + (_recoveredCalories ?? 0.0);

    AppLogger.debug('[COORDINATOR] CALORIE_CALCULATION: '
        'distance=${distanceKm.toStringAsFixed(2)}km, '
        'duration=${duration.inMinutes.toStringAsFixed(1)}min, '
        'userWeight=${userWeightKg.toStringAsFixed(1)}kg, '
        'ruckWeight=${ruckWeightKg.toStringAsFixed(1)}kg, '
        'elevationGain=${elevationGain.toStringAsFixed(1)}m, '
        'elevationLoss=${elevationLoss.toStringAsFixed(1)}m, '
        'terrainMultiplier=${terrainMultiplier.toStringAsFixed(2)}x, '
        'weather=[temp=${temperature?.toStringAsFixed(1)}°C, wind=${windSpeed?.toStringAsFixed(1)}kmh, humidity=${humidity?.toStringAsFixed(0)}%, rain=$isRaining], '
        'sessionCalories=${calories.toStringAsFixed(0)}, recoveredCalories=${(_recoveredCalories ?? 0.0).toStringAsFixed(0)}, totalCalories=${totalCalories.toStringAsFixed(0)}');

    return totalCalories;
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

      final zones = HeartRateZoneService.zonesFromProfile(
          restingHr: restingHr, maxHr: maxHr);
      final timeIn = HeartRateZoneService.timeInZonesSeconds(
          samples: samples, zones: zones);
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

  /// Estimate steps from distance when live tracking is unavailable
  /// Uses average step length of 0.75m (reasonable for rucking with weight)
  int _estimateStepsFromDistance(double distanceKm) {
    if (distanceKm <= 0) return 0;
    const double stepLengthM =
        0.75; // Conservative estimate for rucking with weight
    final int estimatedSteps = ((distanceKm * 1000) / stepLengthM).round();
    AppLogger.info(
        '[STEPS] Estimated $estimatedSteps steps from ${distanceKm.toStringAsFixed(2)}km distance');
    return estimatedSteps;
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
    print('[STEPS DEBUG] ============ SESSION STARTED ============');
    AppLogger.info('[COORDINATOR] Session start requested');
    // Start live steps if enabled in preferences
    try {
      final prefs = GetIt.instance<SharedPreferences>();
      final enabled = prefs.getBool('live_step_tracking') ??
          true; // Default to true - steps enabled by default
      print(
          '[STEPS DEBUG] [COORDINATOR] Live step tracking preference: $enabled');

      if (enabled) {
        final startTime = DateTime.now();
        print(
            '[STEPS DEBUG] [COORDINATOR] Starting live step tracking from: $startTime');
        // Initialize steps to 0 immediately so widget shows, will update with live values
        _currentSteps = 0;
        add(const StateAggregationRequested());

        // Delay step tracking to allow Watch session to initialize
        print(
            '[STEPS DEBUG] [COORDINATOR] Delaying step tracking by 3 seconds for Watch session startup');
        Future.delayed(const Duration(seconds: 3), () {
          print(
              '[STEPS DEBUG] [COORDINATOR] Starting delayed step tracking NOW');
          _stepsSub?.cancel();
          _stepsSub = _healthService.startLiveSteps(startTime).listen(
            (total) {
              print(
                  '[STEPS DEBUG] [COORDINATOR] ✅ Received step update: $total');
              _currentSteps = total;
              add(const StateAggregationRequested());
            },
            onError: (error) {
              print('[STEPS DEBUG] [COORDINATOR] ❌ Steps stream error: $error');
            },
            onDone: () {
              print(
                  '[STEPS DEBUG] [COORDINATOR] ⚠️  Steps stream ended unexpectedly');
            },
          );
          print(
              '[STEPS DEBUG] [COORDINATOR] Live step tracking subscription created');
        }); // Close the Future.delayed block
      } else {
        print(
            '[STEPS DEBUG] [COORDINATOR] Live step tracking DISABLED - initializing steps to 0 for UI display');
        // Initialize steps to 0 so the widget appears, will be estimated at session end
        _currentSteps = 0;
        add(const StateAggregationRequested());
      }
    } catch (e) {
      AppLogger.error('[COORDINATOR] Error setting up live step tracking: $e');
    }

    // Store planned route data for navigation
    _plannedRoute = event.plannedRoute;
    _plannedRouteDistance = event.plannedRouteDistance;
    _plannedRouteDuration = event.plannedRouteDuration;

    if (_plannedRoute != null) {
      AppLogger.info(
          '[COORDINATOR] Stored planned route: ${_plannedRoute!.length} points, ${_plannedRouteDistance}km, ${_plannedRouteDuration}min');
    }

    await _routeEventToManagers(event);
    add(const TimerStarted());
  }

  Future<void> _onSessionCompleted(
    SessionCompleted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.error('[COORDINATOR] ===== SESSION COMPLETION STARTED =====');
    AppLogger.info('[COORDINATOR] Session completion started');

    // Log current paused state to debug watch completion
    if (_currentAggregatedState is ActiveSessionRunning) {
      final runningState = _currentAggregatedState as ActiveSessionRunning;
      AppLogger.info(
          '[COORDINATOR] Session was ${runningState.isPaused ? "PAUSED" : "RUNNING"} when completion triggered');
    }

    // Stop steps
    try {
      _stepsSub?.cancel();
    } catch (_) {}
    try {
      _healthService.stopLiveSteps();
    } catch (_) {}
    AppLogger.info(
        '[COORDINATOR] Current aggregated state: ${_currentAggregatedState.runtimeType}');
    AppLogger.info(
        '[COORDINATOR] Lifecycle state before: isActive=${_lifecycleManager.currentState.isActive}, sessionId=${_lifecycleManager.currentState.sessionId}, pausedAt=${_lifecycleManager.currentState.pausedAt}');

    // Steps computation: Ensure we capture final step count before completion
    await _captureFinalStepsSync();

    // Stop the timer by pausing first
    AppLogger.info('[COORDINATOR] Pausing session first');
    add(const SessionPaused());

    try {
      AppLogger.info('[COORDINATOR] Routing event to managers');
      await _routeEventToManagers(event);

      AppLogger.info(
          '[COORDINATOR] Lifecycle state after: isActive=${_lifecycleManager.currentState.isActive}, sessionId=${_lifecycleManager.currentState.sessionId}');

      // Aggregate and emit the completed state
      AppLogger.info('[COORDINATOR] Aggregating state after stop request');
      _aggregateAndEmitState();
      AppLogger.info(
          '[COORDINATOR] New aggregated state: ${_currentAggregatedState.runtimeType}');

      // Debug: Check if we're showing paused state incorrectly
      if (_currentAggregatedState is ActiveSessionRunning) {
        final runningState = _currentAggregatedState as ActiveSessionRunning;
        if (runningState.isPaused) {
          AppLogger.warning(
              '[COORDINATOR] WARNING: Still showing paused state after stop request!');
        }
      }

      AppLogger.info(
          '[COORDINATOR] Checking if current state is ActiveSessionCompleted: ${_currentAggregatedState is ActiveSessionCompleted}');
      if (_currentAggregatedState is ActiveSessionCompleted) {
        final completedState =
            _currentAggregatedState as ActiveSessionCompleted;
        AppLogger.info(
            '[COORDINATOR] Session completed successfully: sessionId=${completedState.sessionId}, distance=${completedState.finalDistanceKm}km, duration=${completedState.finalDurationSeconds}s');

        // Emit completion state immediately and let SessionCompleteScreen generate AI summary on-page
        emit(completedState);
        AppLogger.info(
            '[COORDINATOR] Emitted completion state (AI summary handled on page)');
        return;
      }

      // If not completed, emit current state normally
      emit(_currentAggregatedState);

      // Clear local storage soon after completion (no UX pause required here)
      Future.delayed(const Duration(milliseconds: 200), () async {
        try {
          await _storageService.remove('active_session_data');
          await _storageService.remove('active_session_last_save');
          AppLogger.info(
              '[COORDINATOR] Local session storage cleared after completion (delayed)');
        } catch (clearError) {
          AppLogger.error(
              '[COORDINATOR] Failed to clear local storage after completion: $clearError');
        }
      });

      AppLogger.info('[COORDINATOR] Session completion process finished');
    } catch (e) {
      // Handle session completion errors gracefully
      if (e.toString().contains('Session not in progress') ||
          e.toString().contains('BadRequestException')) {
        AppLogger.warning(
            '[COORDINATOR] Session completion failed - session already completed or invalid state: $e');

        // Force completion state even if server-side completion failed
        _aggregateAndEmitState();

        // If we don't have a completed state, create one
        if (!(_currentAggregatedState is ActiveSessionCompleted)) {
          final sessionId =
              _lifecycleManager.currentState.sessionId ?? 'unknown';
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
      } else {
        AppLogger.error(
            '[COORDINATOR] Unexpected error during session completion: $e');
      }
    }
  }

  Future<void> _onSessionPaused(
    SessionPaused event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // CRITICAL FIX: Ignore pause events if session is already being saved/completed
    final lifecycleState = _lifecycleManager.currentState;
    if (lifecycleState.isSaving || !lifecycleState.isActive) {
      AppLogger.info(
          '[COORDINATOR] Ignoring pause event - session is completing (isSaving=${lifecycleState.isSaving}, isActive=${lifecycleState.isActive})');
      return;
    }

    AppLogger.info('[COORDINATOR] Session paused');
    await _routeEventToManagers(event);
  }

  Future<void> _onSessionResumed(
    SessionResumed event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // CRITICAL FIX: Ignore resume events if session is already being saved/completed
    final lifecycleState = _lifecycleManager.currentState;
    if (lifecycleState.isSaving || !lifecycleState.isActive) {
      AppLogger.info(
          '[COORDINATOR] Ignoring resume event - session is completing (isSaving=${lifecycleState.isSaving}, isActive=${lifecycleState.isActive})');
      return;
    }

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
    _aggregateAndEmitState(); // CRITICAL FIX: Aggregate state to update UI with latest heart rate
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

  Future<void> _onUploadSessionPhotosRequested(
    UploadSessionPhotosRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('[COORDINATOR] Uploading ${event.photos.length} photos for session ${event.sessionId}');

    try {
      // Upload photos directly via session repository
      final sessionRepository = GetIt.I<SessionRepository>();
      await sessionRepository.uploadSessionPhotos(event.sessionId, event.photos);

      AppLogger.info('[COORDINATOR] Photos uploaded successfully');

      // Refresh session photos
      final activeSessionBloc = GetIt.I<ActiveSessionBloc>();
      activeSessionBloc.add(FetchSessionPhotosRequested(event.sessionId));

    } catch (e) {
      AppLogger.error('[COORDINATOR] Failed to upload photos: $e');
    }

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
    // Diagnostics: log emission details for running state
    if (_currentAggregatedState is ActiveSessionRunning) {
      final rs = _currentAggregatedState as ActiveSessionRunning;
      final now = DateTime.now();
      final last = _lastEmitAt;
      final dtMs = last != null ? now.difference(last).inMilliseconds : null;
      final prev = _lastEmittedDistanceKm;
      final delta = prev != null ? (rs.distanceKm - prev) : null;
      _emitSeq += 1;
      AppLogger.info(
          '[COORDINATOR][EMIT] seq=$_emitSeq distance=${rs.distanceKm.toStringAsFixed(3)} km${delta != null ? ' (Δ=' + delta.toStringAsFixed(3) + ' km)' : ''}, elapsed=${rs.elapsedSeconds}s, paused=${rs.isPaused}, dt=${dtMs != null ? dtMs.toString() + 'ms' : 'n/a'}');
      _lastEmittedDistanceKm = rs.distanceKm;
      _lastEmitAt = now;
    } else {
      AppLogger.debug(
          '[COORDINATOR][EMIT] seq=${_emitSeq + 1} state=${_currentAggregatedState.runtimeType}');
      _emitSeq += 1;
      _lastEmitAt = DateTime.now();
    }
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
    AppLogger.error(
        '[COORDINATOR] MEMORY_PRESSURE: ${managerEvent.memoryUsageMb}MB detected, triggering aggressive cleanup');
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

  /// Capture final steps synchronously before completion
  Future<void> _captureFinalStepsSync() async {
    try {
      final startTime = _lifecycleManager.currentState.startTime;
      if (startTime != null && _currentSteps == null) {
        AppLogger.info(
            '[COORDINATOR] Capturing final step count before completion...');
        final computedSteps =
            await _healthService.getStepsBetween(startTime, DateTime.now());
        _currentSteps = computedSteps;
        AppLogger.info(
            '[COORDINATOR] Final step count captured: $_currentSteps');

        // Fallback to estimation if no steps from health kit
        if (computedSteps == 0) {
          final double distance =
              (_currentAggregatedState is ActiveSessionRunning)
                  ? (_currentAggregatedState as ActiveSessionRunning).distanceKm
                  : _locationManager.totalDistance;

          double? heightCm;
          final authState = GetIt.instance<AuthBloc>().state;
          if (authState is Authenticated && authState.user.heightCm != null) {
            heightCm = authState.user.heightCm;
          }
          _currentSteps = _healthService.estimateStepsFromDistance(distance,
              userHeightCm: heightCm);
          AppLogger.info('[COORDINATOR] Estimated final steps: $_currentSteps');
        }
      } else {
        AppLogger.info(
            '[COORDINATOR] Steps already captured: $_currentSteps or no startTime available');
      }
    } catch (e) {
      AppLogger.warning('[COORDINATOR] Failed to capture final steps: $e');

      // Fallback to distance estimation
      final double distance = (_currentAggregatedState is ActiveSessionRunning)
          ? (_currentAggregatedState as ActiveSessionRunning).distanceKm
          : _locationManager.totalDistance;

      double? heightCm;
      final authState = GetIt.instance<AuthBloc>().state;
      if (authState is Authenticated && authState.user.heightCm != null) {
        heightCm = authState.user.heightCm;
      }
      _currentSteps = _healthService.estimateStepsFromDistance(distance,
          userHeightCm: heightCm);
      AppLogger.warning(
          '[COORDINATOR] Using estimated steps as fallback: $_currentSteps');
    }
  }

  /// Compute steps asynchronously without blocking completion
  void _computeStepsAsync() async {
    try {
      final startTime = _lifecycleManager.currentState.startTime;
      if (startTime != null) {
        final computedSteps =
            await _healthService.getStepsBetween(startTime, DateTime.now());
        _currentSteps = computedSteps;
        AppLogger.info(
            '[COORDINATOR] Computed steps asynchronously: $_currentSteps');
        // Fallback to estimation if no steps from health kit
        if (computedSteps == 0) {
          final double distance =
              (_currentAggregatedState is ActiveSessionRunning)
                  ? (_currentAggregatedState as ActiveSessionRunning).distanceKm
                  : _locationManager.currentState.totalDistance;
          double? heightCm;
          final authState = GetIt.instance<AuthBloc>().state;
          if (authState is Authenticated && authState.user.heightCm != null) {
            heightCm = authState.user.heightCm;
          }
          _currentSteps = _healthService.estimateStepsFromDistance(distance,
              userHeightCm: heightCm);
          AppLogger.info(
              '[COORDINATOR] Estimated steps asynchronously: $_currentSteps');
        }
        // Re-emit state with updated steps if session is completed
        if (_currentAggregatedState is ActiveSessionCompleted) {
          final currentState =
              _currentAggregatedState as ActiveSessionCompleted;
          final updatedState = ActiveSessionCompleted(
            sessionId: currentState.sessionId,
            finalDistanceKm: currentState.finalDistanceKm,
            finalDurationSeconds: currentState.finalDurationSeconds,
            finalCalories: currentState.finalCalories,
            elevationGain: currentState.elevationGain,
            elevationLoss: currentState.elevationLoss,
            averagePace: currentState.averagePace,
            route: currentState.route,
            heartRateSamples: currentState.heartRateSamples,
            averageHeartRate: currentState.averageHeartRate,
            minHeartRate: currentState.minHeartRate,
            maxHeartRate: currentState.maxHeartRate,
            sessionPhotos: currentState.sessionPhotos,
            splits: currentState.splits,
            completedAt: currentState.completedAt,
            isOffline: currentState.isOffline,
            ruckWeightKg: currentState.ruckWeightKg,
            steps: _currentSteps,
            aiCompletionInsight: currentState.aiCompletionInsight,
          );
          _currentAggregatedState = updatedState;
          emit(updatedState);
          AppLogger.info('[COORDINATOR] Re-emitted state with updated steps');
        }
      } else {
        AppLogger.debug(
            '[COORDINATOR] No startTime available to compute steps');
      }
    } catch (e) {
      AppLogger.warning(
          '[COORDINATOR] Failed to compute steps asynchronously: $e');
    }
  }

  /// Generate AI summary asynchronously and update state when ready
  void _generateAndUpdateAISummaryAsync(ActiveSessionCompleted state) async {
    try {
      AppLogger.info(
          '[COORDINATOR] Generating OpenAI session summary asynchronously...');
      final aiSummary = await _generateSessionSummary(state);
      AppLogger.info(
          '[COORDINATOR] OpenAI session summary generated asynchronously: $aiSummary');

      // Update state with AI summary
      final updatedState = ActiveSessionCompleted(
        sessionId: state.sessionId,
        finalDistanceKm: state.finalDistanceKm,
        finalDurationSeconds: state.finalDurationSeconds,
        finalCalories: state.finalCalories,
        elevationGain: state.elevationGain,
        elevationLoss: state.elevationLoss,
        averagePace: state.averagePace,
        route: state.route,
        heartRateSamples: state.heartRateSamples,
        averageHeartRate: state.averageHeartRate,
        minHeartRate: state.minHeartRate,
        maxHeartRate: state.maxHeartRate,
        sessionPhotos: state.sessionPhotos,
        splits: state.splits,
        completedAt: state.completedAt,
        isOffline: state.isOffline,
        ruckWeightKg: state.ruckWeightKg,
        steps: state.steps,
        aiCompletionInsight: aiSummary,
      );
      _currentAggregatedState = updatedState;
      emit(updatedState);
      AppLogger.info('[COORDINATOR] Re-emitted state with AI summary');
    } catch (e) {
      AppLogger.error(
          '[COORDINATOR] Failed to generate AI summary asynchronously: $e');
    }
  }

  /// Generate OpenAI session summary based on session data
  Future<String?> _generateSessionSummary(ActiveSessionCompleted state) async {
    try {
      // Get user information for context
      final authState = GetIt.instance<AuthBloc>().state;
      Map<String, dynamic> userContext = {};
      if (authState is Authenticated) {
        userContext = {
          'user_info': {
            'user_id': authState.user.userId,
            'username': authState.user.username,
            'prefers_metric': authState.user.preferMetric,
          },
          'unit_preference':
              authState.user.preferMetric ? 'metric' : 'imperial',
        };
      }

      // Build session context for OpenAI
      final sessionContext = {
        'session_id': state.sessionId,
        'distance_km': state.finalDistanceKm,
        'distance_miles': state.finalDistanceKm * 0.621371,
        'duration_minutes': (state.finalDurationSeconds / 60.0).round(),
        'duration_seconds': state.finalDurationSeconds,
        'calories_burned': state.finalCalories,
        'elevation_gain_m': state.elevationGain,
        'elevation_gain_ft': state.elevationGain * 3.28084,
        'elevation_loss_m': state.elevationLoss,
        'elevation_loss_ft': state.elevationLoss * 3.28084,
        'ruck_weight_kg': state.ruckWeightKg,
        'ruck_weight_lbs': state.ruckWeightKg * 2.20462,
        'steps': state.steps,
        'completed_at': state.completedAt.toIso8601String(),
      };

      // Add heart rate data if available
      if (state.averageHeartRate != null) {
        sessionContext['avg_heart_rate'] = state.averageHeartRate;
        sessionContext['min_heart_rate'] = state.minHeartRate;
        sessionContext['max_heart_rate'] = state.maxHeartRate;
      }

      // Add pace data if available
      if (state.averagePace != null && state.averagePace! > 0) {
        final paceMinPerKm = state.averagePace! / 60.0;
        final paceMinPerMile = paceMinPerKm * 1.60934;
        sessionContext['pace_min_per_km'] = paceMinPerKm;
        sessionContext['pace_min_per_mile'] = paceMinPerMile;
      }

      // Fetch weather data for the session location
      Map<String, dynamic> weatherContext = {};
      try {
        final route = state.route;
        if (route.isNotEmpty) {
          final startLocation = route.first;
          final weatherData = await _fetchWeatherData(
              startLocation.latitude, startLocation.longitude);
          if (weatherData != null) {
            weatherContext = weatherData;
          }
        }
      } catch (e) {
        AppLogger.warning('[COORDINATOR] Failed to fetch weather data: $e');
      }

      // Fetch recent session history for context
      Map<String, dynamic> historyContext = {};
      try {
        final recentSessions = await _fetchRecentUserHistory(limit: 5);
        if (recentSessions.isNotEmpty) {
          historyContext = {
            'recent_rucks': recentSessions
                .map((session) => {
                      'distance_km': session['distance_km'] ?? 0.0,
                      'duration_seconds': session['duration_seconds'] ?? 0,
                      'calories_burned': session['calories_burned'] ?? 0,
                      'completed_at': session['completed_at'],
                      'ruck_weight_kg': session['ruck_weight_kg'] ?? 0.0,
                    })
                .toList(),
          };
        }
      } catch (e) {
        AppLogger.warning('[COORDINATOR] Failed to fetch user history: $e');
      }

      // Fetch coaching plan data for session summary context
      Map<String, dynamic>? coachingPlan;
      try {
        final coachingResponse = await _apiClient.get('/user-coaching-plans');
        if (coachingResponse != null &&
            coachingResponse is Map<String, dynamic>) {
          coachingPlan = coachingResponse;
          AppLogger.info(
              '[COORDINATOR] Fetched coaching plan for summary: ${coachingPlan['plan_name']}');
        }
      } catch (e) {
        AppLogger.info('[COORDINATOR] No coaching plan for summary: $e');
      }

      // Build full context for OpenAI
      final context = {
        'trigger': {'type': 'session_completion'},
        'session': sessionContext,
        'user': userContext,
        'environment': weatherContext,
        'history': historyContext,
      };

      AppLogger.info(
          '[COORDINATOR] Calling OpenAI with session summary context: $context');

      // Generate summary using enhanced method with coaching context
      final summary =
          await _openAIService.generateSessionSummaryWithCoachingContext(
        context: context,
        coachingPlan: coachingPlan,
      );

      if (summary != null && summary.isNotEmpty) {
        AppLogger.info(
            '[COORDINATOR] OpenAI session summary generated successfully: $summary');
        return summary;
      } else {
        AppLogger.warning(
            '[COORDINATOR] OpenAI returned empty session summary');
        return null;
      }
    } catch (e) {
      AppLogger.error(
          '[COORDINATOR] Error generating OpenAI session summary: $e');
      return null;
    }
  }

  /// Fetch weather data for the given coordinates
  Future<Map<String, dynamic>?> _fetchWeatherData(
      double latitude, double longitude) async {
    try {
      final response = await _apiClient.get('/weather', queryParams: {
        'lat': latitude,
        'lon': longitude,
      });

      if (response != null) {
        final weatherData = response as Map<String, dynamic>;

        // Transform to expected format for OpenAI context
        return {
          'temperature_f': weatherData['temp_f'],
          'temperature_c': weatherData['temp_c'],
          'condition': weatherData['condition'] ?? weatherData['description'],
          'humidity': weatherData['humidity'],
          'wind_speed': weatherData['wind_speed'],
          'visibility': weatherData['visibility'],
        };
      }
    } catch (e) {
      AppLogger.error('[COORDINATOR] Weather API error: $e');
    }
    return null;
  }

  /// Fetch recent user session history
  Future<List<Map<String, dynamic>>> _fetchRecentUserHistory(
      {int limit = 5}) async {
    try {
      final response = await _apiClient.get('/rucks', queryParams: {
        'limit': limit,
        'offset': 0,
      });

      if (response != null) {
        final sessions = response as List<dynamic>;
        return sessions
            .cast<Map<String, dynamic>>()
            .where((session) => session['status'] == 'completed')
            .toList();
      }
    } catch (e) {
      AppLogger.error('[COORDINATOR] User history API error: $e');
    }
    return [];
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
      final isCrashRecovery =
          recoveredData['is_crash_recovery'] as bool? ?? false;

      if (isCrashRecovery) {
        // Actual crash recovery - restore accumulated metrics
        final distance =
            (recoveredData['distance_km'] as num?)?.toDouble() ?? 0.0;
        final elevationGain =
            (recoveredData['elevation_gain'] as num?)?.toDouble() ?? 0.0;
        final elevationLoss =
            (recoveredData['elevation_loss'] as num?)?.toDouble() ?? 0.0;
        final calories = (recoveredData['calories'] as num?)?.toDouble() ?? 0.0;
        final recoveryDuration =
            (recoveredData['recovery_duration_minutes'] as num?)?.toInt() ?? 0;

        AppLogger.info(
            '[COORDINATOR] CRASH RECOVERY: Restoring ${distance}km, ${elevationGain}m gain, ${calories} cal after ${recoveryDuration} min gap');

        // Initialize location manager with recovered metrics
        _locationManager.restoreMetricsFromRecovery(
          totalDistanceKm: distance,
          elevationGainM: elevationGain,
          elevationLossM: elevationLoss,
        );

        // Store recovered calories so they persist through session completion
        _recoveredCalories = calories;
        AppLogger.info(
            '[COORDINATOR] Stored recovered calories: ${calories} for session completion');
      } else {
        // Regular recovery callback - don't override live calculations
        AppLogger.info(
            '[COORDINATOR] Regular recovery callback - letting live calculations continue');
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

  /// Helper function to check if weather condition code indicates rain
  bool _isRainyWeather(int conditionCode) {
    // OpenWeatherMap condition codes for rain/drizzle
    return (conditionCode >= 200 &&
        conditionCode < 600); // Thunderstorm, drizzle, rain
  }
}
