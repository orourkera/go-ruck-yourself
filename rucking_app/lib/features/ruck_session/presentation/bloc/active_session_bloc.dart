library active_session_bloc;

import 'dart:async';
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:io';
import 'dart:math' as math;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/models/api_exception.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/core/services/android_optimization_service.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'package:rucking_app/core/utils/met_calculator.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';

part 'active_session_event.dart';
part 'active_session_state.dart';

enum PhotoLoadingStatus { initial, loading, success, failure }

class ActiveSessionBloc extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  int _paceTickCounter = 0;
  final ApiClient _apiClient;
  final LocationService _locationService;
  final HealthService _healthService;
  final WatchService _watchService;
  final HeartRateService _heartRateService;
  final SessionValidationService _validationService;
  final SessionRepository _sessionRepository;
  final SplitTrackingService _splitTrackingService;
  final ActiveSessionStorage _activeSessionStorage;
  final TerrainTracker _terrainTracker;
  final ConnectivityService _connectivityService;

  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<List<LocationPoint>>? _batchLocationSubscription;
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  StreamSubscription<List<HeartRateSample>>? _heartRateBufferSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _ticker;
  Timer? _watchdogTimer;
  Timer? _sessionPersistenceTimer;
  DateTime _lastTickTime = DateTime.now();
  LocationPoint? _lastValidLocation;
  int _validLocationCount = 0;
  int _elapsedCounter = 0;
  int _ticksSinceTruth = 0;
  DateTime _lastLocationTimestamp = DateTime.now();

  bool _isHeartRateMonitoringStarted = false;
  final List<HeartRateSample> _allHeartRateSamples = [];
  int? _latestHeartRate;
  int? _minHeartRate;
  int? _maxHeartRate;
  
  /// Heart rate throttling - only save one sample every 30 seconds
  DateTime? _lastSavedHeartRateTime;
  
  /// Heart rate API throttling - only send to API every 30 seconds
  DateTime? _lastApiHeartRateTime;

  int? _authRetryCounter;

  ActiveSessionBloc({
    required ApiClient apiClient,
    required LocationService locationService,
    required HealthService healthService,
    required WatchService watchService,
    required HeartRateService heartRateService,
    required SplitTrackingService splitTrackingService,
    required SessionRepository sessionRepository,
    required ActiveSessionStorage activeSessionStorage,
    required TerrainTracker terrainTracker,
    required ConnectivityService connectivityService,
    SessionValidationService? validationService,
  })  : _apiClient = apiClient,
        _locationService = locationService,
        _healthService = healthService,
        _watchService = watchService,
        _heartRateService = heartRateService,
        _splitTrackingService = splitTrackingService,
        _sessionRepository = sessionRepository,
        _activeSessionStorage = activeSessionStorage,
        _terrainTracker = terrainTracker,
        _connectivityService = connectivityService,
        _validationService = validationService ?? SessionValidationService(),
        super(ActiveSessionInitial()) {
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      GetIt.I.unregister<ActiveSessionBloc>();
    }
    GetIt.I.registerSingleton<ActiveSessionBloc>(this);

    on<SessionStarted>(_onSessionStarted);
    on<LocationUpdated>(_onLocationUpdated);
    on<BatchLocationUpdated>(_onBatchLocationUpdated);
    on<SessionPaused>(_onSessionPaused);
    on<SessionResumed>(_onSessionResumed);
    on<SessionCompleted>(_onSessionCompleted);
    on<SessionFailed>(_onSessionFailed);
    on<Tick>(_onTick);
    on<SessionErrorCleared>(_onSessionErrorCleared);
    on<TimerStarted>(_onTimerStarted);
    on<SessionRecoveryRequested>(_onSessionRecoveryRequested);
    on<FetchSessionPhotosRequested>(_onFetchSessionPhotosRequested);
    on<UploadSessionPhotosRequested>(_onUploadSessionPhotosRequested);
    on<DeleteSessionPhotoRequested>(_onDeleteSessionPhotoRequested);
    on<ClearSessionPhotos>(_onClearSessionPhotos);
    on<TakePhotoRequested>(_onTakePhotoRequested);
    on<PickPhotoRequested>(_onPickPhotoRequested);
    on<LoadSessionForViewing>(_onLoadSessionForViewing);
    on<UpdateStateWithSessionPhotos>(_onUpdateStateWithSessionPhotos);
    on<HeartRateUpdated>(_onHeartRateUpdated);
    on<HeartRateBufferProcessed>(_onHeartRateBufferProcessed);
    on<SessionReset>(_onSessionReset);
    on<SessionCleanupRequested>(_onSessionCleanupRequested);
  }

  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    _splitTrackingService.reset();
    _allHeartRateSamples.clear();
    _minHeartRate = null;
    _maxHeartRate = null;
    _latestHeartRate = null;
    _lastSavedHeartRateTime = null; // Reset heart rate throttling
    _lastApiHeartRateTime = null; // Reset API heart rate throttling
    _isHeartRateMonitoringStarted = false;
    _elapsedCounter = 0;
    _ticksSinceTruth = 0;
    _lastTickTime = DateTime.now();
    _lastValidLocation = null;
    _validLocationCount = 0;
    _paceTickCounter = 0;

    AppLogger.debug('SessionStarted event. Weight: ${event.ruckWeightKg}kg, Notes: ${event.notes}');
    AppLogger.sessionCompletion('SessionStarted - Event ID tracking', context: {
      'event_id': event.eventId,
      'has_event_id': event.eventId != null,
      'event_id_type': event.eventId.runtimeType.toString(),
    });
    emit(ActiveSessionLoading());
    String? sessionId;

    try {
      bool hasPermission = await _locationService.hasLocationPermission();
      if (!hasPermission) hasPermission = await _locationService.requestLocationPermission();
      
      bool hasLocationAccess = hasPermission;
      if (!hasPermission) {
        AppLogger.warning('Location permission denied - starting session in offline mode (no GPS tracking)');
        // Don't fail the session - allow offline mode for indoor rucks, airplanes, etc.
      }

      // Android: Enhanced optimization checks for reliable background GPS tracking
      if (Platform.isAndroid) {
        AppLogger.info('[SESSION_START] Checking Android optimization status...');
        
        // Use new comprehensive Android optimization service
        final androidOptimizationService = AndroidOptimizationService.instance;
        await androidOptimizationService.logOptimizationStatus();
        
        final hasAllPermissions = await androidOptimizationService.hasAllCriticalPermissions();
        if (!hasAllPermissions) {
          AppLogger.warning('[SESSION_START] Missing critical Android permissions - GPS may be throttled');
          
          // Show OEM-specific tips if on problematic device
          if (androidOptimizationService.isProblematiOEMDevice()) {
            AppLogger.warning('[SESSION_START] Problematic OEM device detected');
            AppLogger.info('[SESSION_START] Tip: ${androidOptimizationService.getOEMSpecificTips()}');
          }
        } else {
          AppLogger.info('[SESSION_START] All critical Android permissions granted');
        }
      }

      // Legacy battery optimization check (keep for backward compatibility)
      AppLogger.info('[SESSION_START] Logging battery optimization status...');
      await BatteryOptimizationService.logPowerManagementState();
      
      final backgroundPermissions = await BatteryOptimizationService.checkBackgroundLocationPermissions();
      if (!backgroundPermissions['all_granted']!) {
        AppLogger.warning('[SESSION_START] Some background permissions missing - session may be interrupted');
        AppLogger.warning('[SESSION_START] Permission status: $backgroundPermissions');
        // Don't request permissions here anymore - they should be handled at app startup
      } else {
        AppLogger.info('[SESSION_START] All background permissions granted');
      }

      // Try to create session on backend, but allow offline mode if it fails
      try {
        // Check connectivity first before making API call
        final connectivityService = GetIt.I<ConnectivityService>();
        final isConnected = await connectivityService.isConnected();
        
        if (!isConnected) {
          // Immediately go offline if no connection
          throw NetworkException('No internet connection - starting offline mode');
        }
        
        // Use a very short timeout for session creation to fail fast into offline mode
        final sessionCreatePayload = {
          'ruck_weight_kg': event.ruckWeightKg,
          'notes': event.notes,
          'event_id': event.eventId, // Pass event ID if creating session from event
        };
        
        AppLogger.sessionCompletion('Creating session with payload', context: {
          'payload': sessionCreatePayload,
          'endpoint': '/rucks',
          'event_id_in_payload': sessionCreatePayload['event_id'],
        });
        
        final createResponse = await _apiClient.post('/rucks', sessionCreatePayload).timeout(Duration(seconds: 1)); // Reduced from 3 to 1 second for faster offline detection
        
        sessionId = createResponse['id']?.toString();
        if (sessionId == null || sessionId.isEmpty) throw Exception('Failed to create session: No ID.');
        AppLogger.debug('Created new session with ID: $sessionId');

        // Start the session on the backend
        // Removed commented out API call lines

      } catch (apiError) {
        // If API calls fail, create offline session with local ID
        sessionId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
        AppLogger.info(' Creating offline session: $sessionId - all data will be stored locally and synced when connection is restored');
        AppLogger.warning('API Error: $apiError');
      }
      final initialSessionState = ActiveSessionRunning(
        sessionId: sessionId,
        locationPoints: const [],
        elapsedSeconds: 0,
        distanceKm: 0.0,
        ruckWeightKg: event.ruckWeightKg,
        userWeightKg: event.userWeightKg,
        notes: event.notes,
        calories: 0.0,
        elevationGain: 0.0,
        elevationLoss: 0.0,
        isPaused: false,
        pace: 0.0,
        latestHeartRate: null,
        plannedDuration: event.plannedDuration,
        originalSessionStartTimeUtc: DateTime.now().toUtc(),
        totalPausedDuration: Duration.zero,
        currentPauseStartTimeUtc: null,
        heartRateSamples: const [],
        minHeartRate: null,
        maxHeartRate: null,
        isGpsReady: false,
        hasGpsAccess: hasLocationAccess,
        photos: const [],
        isPhotosLoading: false,
        splits: const [],
        terrainSegments: const [],
        eventId: event.eventId, // Add eventId to initial state
      );
      emit(initialSessionState);
      AppLogger.debug('ActiveSessionRunning emitted for $sessionId.');

      // Get user's metric preference
      bool preferMetric = false; // Default to imperial (standard) instead of metric
      final authState = GetIt.I<AuthBloc>().state;
      AppLogger.info('[ACTIVE_SESSION] AuthBloc state type: ${authState.runtimeType}');
      AppLogger.info('[ACTIVE_SESSION] AuthBloc state: $authState');
      
      if (authState is Authenticated) {
        preferMetric = authState.user.preferMetric;
        AppLogger.info('[ACTIVE_SESSION] User from AuthBloc: ${authState.user.toJson()}');
        AppLogger.info('[ACTIVE_SESSION] User preferMetric: ${authState.user.preferMetric}');
      } else {
        AppLogger.warning('[ACTIVE_SESSION] User not authenticated, checking storage for preference');
        
        // Fallback: Try to get user preference from storage
        try {
          final storageService = GetIt.I<StorageService>();
          final storedUserData = await storageService.getObject(AppConfig.userProfileKey);
          if (storedUserData != null && storedUserData.containsKey('preferMetric')) {
            preferMetric = storedUserData['preferMetric'] as bool;
            AppLogger.info('[ACTIVE_SESSION] Found stored user preference: $preferMetric');
          } else {
            AppLogger.warning('[ACTIVE_SESSION] No stored user preference found, defaulting to imperial (false)');
          }
        } catch (e) {
          AppLogger.error('[ACTIVE_SESSION] Error reading stored user preference: $e');
          AppLogger.warning('[ACTIVE_SESSION] Defaulting to imperial (false)');
        }
      }
      
      AppLogger.info('[ACTIVE_SESSION] Final preferMetric value: $preferMetric');
      AppLogger.info('[ACTIVE_SESSION] Sending isMetric to watch: $preferMetric');
      
      await _watchService.startSessionOnWatch(event.ruckWeightKg, isMetric: preferMetric);
      await _watchService.sendSessionIdToWatch(sessionId);

      _validationService.reset();
      if (hasLocationAccess) {
        _startLocationUpdates(sessionId);
      }
      _startHeartRateMonitoring(sessionId); 
      _startConnectivityMonitoring(sessionId);
      add(TimerStarted());

    } catch (e, stackTrace) {
      String errorMessage = ErrorHandler.getUserFriendlyMessage(e, 'Session Start');
      AppLogger.error('Error starting session: $errorMessage\nError: $e\n$stackTrace');
      emit(ActiveSessionFailure(errorMessage: errorMessage));
    }
  }

  void _startLocationUpdates(String sessionId) {
    _locationSubscription?.cancel();
    _batchLocationSubscription?.cancel();
    _locationSubscription = _locationService.startLocationTracking().listen(
      (location) {
        add(LocationUpdated(location));
      },
      onError: (error) {
        AppLogger.warning('Location tracking error (continuing session without GPS): $error');
        // Don't stop the session - continue in offline mode without location updates
        // This allows users to ruck indoors, on airplanes, or in poor GPS areas
      },
    );
    _batchLocationSubscription = _locationService.batchedLocationUpdates.listen(
      (batch) {
        add(BatchLocationUpdated(batch));
      },
      onError: (error) {
        AppLogger.warning('Batch location tracking error (continuing session without GPS): $error');
        // Don't stop the session - continue in offline mode without location updates
        // This allows users to ruck indoors, on airplanes, or in poor GPS areas
      },
    );
    AppLogger.debug('Location tracking started for session $sessionId.');
  }

  Future<void> _onLocationUpdated(
    LocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (currentState.isPaused) return;

      final LocationPoint newPoint = event.locationPoint;
      _lastLocationTimestamp = DateTime.now();
      
      final validationResult = _validationService.validateLocationPoint(newPoint, _lastValidLocation);
      if (!(validationResult['isValid'] as bool? ?? false)) {
        final String message = validationResult['message'] as String? ?? 'Validation failed, no specific message';
        AppLogger.warning('Invalid location point: $message');
        return;
      }

      _lastValidLocation = newPoint;
      _validLocationCount++;
      
      final newLocationPoints = [...currentState.locationPoints, newPoint];
      
      // Calculate distance
      double newDistanceKm = currentState.distanceKm;
      if (currentState.locationPoints.isNotEmpty) {
        final lastPoint = currentState.locationPoints.last;
        final segmentDistance = _locationService.calculateDistance(lastPoint, newPoint);
        newDistanceKm += segmentDistance;
      }
      
      // Calculate elevation changes
      double newElevationGain = currentState.elevationGain;
      double newElevationLoss = currentState.elevationLoss;
      
      if (currentState.locationPoints.isNotEmpty && newPoint.elevation != null) {
        final lastPoint = currentState.locationPoints.last;
        if (lastPoint.elevation != null) {
          final elevationChange = newPoint.elevation! - lastPoint.elevation!;
          if (elevationChange > 0) {
            newElevationGain += elevationChange;
          } else {
            newElevationLoss += elevationChange.abs();
          }
        }
      }
      
      // Update terrain data periodically (throttled)
      List<TerrainSegment> newTerrainSegments = currentState.terrainSegments;
      if (currentState.locationPoints.isNotEmpty) {
        final lastPoint = currentState.locationPoints.last;
        
        // Track terrain for this segment using existing terrain tracker
        if (_terrainTracker.shouldQueryTerrain(newPoint)) {
          AppLogger.debug('[TERRAIN] Attempting to track terrain segment...');
          try {
            final terrainSegment = await _terrainTracker.trackTerrainSegment(
              startLocation: lastPoint,
              endLocation: newPoint,
            );
            
            if (terrainSegment != null) {
              newTerrainSegments = [...newTerrainSegments, terrainSegment];
              AppLogger.debug('[TERRAIN] Added terrain segment: ${terrainSegment.surfaceType} (${terrainSegment.energyMultiplier}x) - Total segments: ${newTerrainSegments.length}');
            } else {
              AppLogger.warning('[TERRAIN] Terrain segment was null');
            }
          } catch (e) {
            AppLogger.warning('[TERRAIN] Failed to track terrain segment: $e');
            // Continue without terrain data - session continues normally
          }
        } else {
          AppLogger.debug('[TERRAIN] Terrain query skipped (throttled)');
        }
      }
      
      _splitTrackingService.checkForMilestone(
        currentDistanceKm: newDistanceKm,
        sessionStartTime: currentState.originalSessionStartTimeUtc,
        elapsedSeconds: currentState.elapsedSeconds,
        isPaused: currentState.isPaused,
      );

      // Note: Individual location points are no longer sent immediately
      // They are batched and sent via _processBatchLocationUpload

      emit(currentState.copyWith(
        locationPoints: newLocationPoints,
        distanceKm: newDistanceKm,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
        isGpsReady: _validLocationCount > 5,
        splits: _splitTrackingService.getSplits(),
        terrainSegments: newTerrainSegments,
      ));
    }
  }
  
  /// Process batch upload of location points
  void _processBatchLocationUpload(String sessionId, List<LocationPoint> locationPoints) {
    AppLogger.info('Uploading batch of ${locationPoints.length} location points');
    
    final locationData = locationPoints.map((point) => point.toJson()).toList();
    
    _apiClient.addLocationPoints(sessionId, locationData)
      .then((_) {
        AppLogger.info('Successfully uploaded ${locationPoints.length} location points');
      })
      .catchError((e) {
        if (e.toString().contains('401') || e.toString().contains('Already Used')) {
          AppLogger.warning('[SESSION_RECOVERY] Location batch sync failed due to auth issue, will retry: $e');
          // Don't kill the session - continue tracking locally
        } else {
          AppLogger.warning('Failed to send location batch to backend: $e');
        }
      });
  }
  
  Future<void> _onBatchLocationUpdated(
    BatchLocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (currentState.isPaused) return;

      final batch = event.locationPoints;
      _lastLocationTimestamp = DateTime.now();
      
      AppLogger.info('Processing batch of ${batch.length} location points for API upload');
      
      // Send batch to API (don't process individual points for UI updates)
      if (batch.isNotEmpty && !currentState.sessionId.startsWith('offline_')) {
        _processBatchLocationUpload(currentState.sessionId, batch);
      }
    }
  }
  
  Future<void> _onTimerStarted(TimerStarted event, Emitter<ActiveSessionState> emit) async {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) => add(const Tick()));

    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (DateTime.now().difference(_lastLocationTimestamp).inSeconds > 60 && _validLocationCount > 0) {
        AppLogger.warning('Watchdog: No valid location for 60s. Restarting location service.');
        _locationService.stopLocationTracking();
        if (state is ActiveSessionRunning) {
           _startLocationUpdates((state as ActiveSessionRunning).sessionId);
        }
        _lastLocationTimestamp = DateTime.now();
      }
    });

    _sessionPersistenceTimer?.cancel();
    _sessionPersistenceTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        await _activeSessionStorage.saveActiveSession(currentState);
      }
    });
  }

  void _stopTickerAndWatchdog() {
    _ticker?.cancel(); _ticker = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    _sessionPersistenceTimer?.cancel(); _sessionPersistenceTimer = null;
    AppLogger.debug('Master timer, watchdog, and session persistence timer stopped.');
  }

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    _lastTickTime = DateTime.now();
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (currentState.isPaused) return;

      _elapsedCounter++;
      _ticksSinceTruth++;
      int newElapsed = _elapsedCounter;

      if (_ticksSinceTruth >= 60) {
        final Duration wallClockElapsed = DateTime.now().toUtc().difference(currentState.originalSessionStartTimeUtc);
        final int trueElapsed = wallClockElapsed.inSeconds - currentState.totalPausedDuration.inSeconds;
        if ((trueElapsed - _elapsedCounter).abs() > 2) {
          _elapsedCounter = trueElapsed; newElapsed = trueElapsed;
          AppLogger.debug('Elapsed counter synced (diff ${(trueElapsed - _elapsedCounter).abs()}s)');
        }
        _ticksSinceTruth = 0;
      }
      
      double? newPace = currentState.pace;
      _paceTickCounter++;
      if (_paceTickCounter >= 15) {
         _paceTickCounter = 0;
        if (currentState.distanceKm > 0.05 && newElapsed > 0) {
            // Calculate pace in minutes per km, then convert to seconds per km for the formatter
            double minutesPerKm = (newElapsed / 60.0) / currentState.distanceKm;
            newPace = minutesPerKm * 60.0; // Convert minutes per km to seconds per km
        } else { newPace = null; }
      }

      // Check if auth state is Authenticated before accessing user property
      double userWeightKg = currentState.userWeightKg;

      // Calculate terrain multiplier for more accurate calorie calculation
      double terrainMultiplier = TerrainSegment.calculateWeightedTerrainMultiplier(currentState.terrainSegments);

      // Enhanced MET calculation with elevation data
      double avgGrade = 0.0;
      if (currentState.distanceKm > 0) {
        avgGrade = MetCalculator.calculateGrade(
          elevationChangeMeters: currentState.elevationGain - currentState.elevationLoss,
          distanceMeters: currentState.distanceKm * 1000,
        );
      }

      // Convert pace (seconds per km) to speed (km/h), then to mph for MetCalculator
      // Speed (km/h) = 60 / pace (seconds per km)
      double speedKmh = newPace != null && newPace > 0 ? (60 / newPace) : 0;
      double speedMph = MetCalculator.kmhToMph(speedKmh);
      // Convert kg to lbs for rucksack weight
      double ruckWeightLbs = currentState.ruckWeightKg * 2.20462;

      double metValue = MetCalculator.calculateRuckingMetByGrade(
        speedMph: speedMph,
        grade: avgGrade, // Use calculated grade instead of assuming flat ground
        ruckWeightLbs: ruckWeightLbs,
      );

      // Calculate calories per minute using enhanced MET formula with terrain
      // MET formula: Calories = MET value × Weight (kg) × Duration (hours) × Terrain Multiplier
      // For calories per minute: Calories = MET value × Weight (kg) × Terrain Multiplier / 60
      double caloriesPerMinute = metValue * (userWeightKg + currentState.ruckWeightKg) * terrainMultiplier / 60;
      double newCalories = currentState.calories + (caloriesPerMinute / 60.0);

      // Duration is now tracked via checkForMilestone instead of updateDuration
      _splitTrackingService.checkForMilestone(
        currentDistanceKm: currentState.distanceKm,
        sessionStartTime: currentState.originalSessionStartTimeUtc,
        elapsedSeconds: newElapsed,
        isPaused: currentState.isPaused,
      );

      emit(currentState.copyWith(
        elapsedSeconds: newElapsed,
        pace: newPace,
        calories: newCalories,
        latestHeartRate: _latestHeartRate,
        minHeartRate: _minHeartRate,
        maxHeartRate: _maxHeartRate,
        heartRateSamples: _allHeartRateSamples.toList(),
        splits: _splitTrackingService.getSplits(),
      ));
      
      // Update metrics on watch
      try {
        // Get the user's metric preference
        bool preferMetric = false; // Default to imperial (standard) instead of metric
        final authState = GetIt.I<AuthBloc>().state;
        AppLogger.info('[ACTIVE_SESSION] AuthBloc state type: ${authState.runtimeType}');
        AppLogger.info('[ACTIVE_SESSION] AuthBloc state: $authState');
        
        if (authState is Authenticated) {
          preferMetric = authState.user.preferMetric;
          AppLogger.info('[ACTIVE_SESSION] User from AuthBloc: ${authState.user.toJson()}');
          AppLogger.info('[ACTIVE_SESSION] User preferMetric: ${authState.user.preferMetric}');
        } else {
          AppLogger.warning('[ACTIVE_SESSION] User not authenticated, checking storage for preference');
          
          // Fallback: Try to get user preference from storage
          try {
            final storageService = GetIt.I<StorageService>();
            final storedUserData = await storageService.getObject(AppConfig.userProfileKey);
            if (storedUserData != null && storedUserData.containsKey('preferMetric')) {
              preferMetric = storedUserData['preferMetric'] as bool;
              AppLogger.info('[ACTIVE_SESSION] Found stored user preference: $preferMetric');
            } else {
              AppLogger.warning('[ACTIVE_SESSION] No stored user preference found, defaulting to imperial (false)');
            }
          } catch (e) {
            AppLogger.error('[ACTIVE_SESSION] Error reading stored user preference: $e');
            AppLogger.warning('[ACTIVE_SESSION] Defaulting to imperial (false)');
          }
        }
        
        AppLogger.info('[ACTIVE_SESSION] Final preferMetric value: $preferMetric');
        AppLogger.info('[ACTIVE_SESSION] Sending isMetric to watch: $preferMetric');
        
        await _watchService.updateMetricsOnWatch(
          distance: currentState.distanceKm, // Always send in km - watch handles unit conversion internally
          duration: Duration(seconds: newElapsed),
          pace: newPace ?? 0.0,
          isPaused: currentState.isPaused,
          calories: newCalories.round(),
          elevation: currentState.elevationGain,
          elevationLoss: currentState.elevationLoss,
          isMetric: preferMetric, // Pass the user's unit preference
        );
      } catch (e) {
        AppLogger.error('Failed to update metrics on watch: $e');
      }
      
      // Retry authentication and location syncing if not currently active
      // Check every minute (60 ticks) to see if we can restore API functionality
      _authRetryCounter = (_authRetryCounter ?? 0) + 1;
      if (_authRetryCounter! >= 60) {
        _authRetryCounter = 0;
        if (_locationSubscription == null) {
          AppLogger.info('[SESSION_RECOVERY] Attempting to restore location syncing...');
          try {
            // Test if auth is working now
            await GetIt.I<AuthService>().isAuthenticated();
            AppLogger.info('[SESSION_RECOVERY] Authentication restored, restarting location updates');
            _startLocationUpdates(currentState.sessionId);
          } catch (authError) {
            AppLogger.debug('[SESSION_RECOVERY] Authentication still not ready: $authError');
          }
        }
      }
    }
  }

  Future<void> _onSessionPaused(
    SessionPaused event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      _heartRateService.stopHeartRateMonitoring(); // Stop HR monitoring during pause
      // Send any buffered heart rate samples before pausing
      if (_heartRateService.heartRateBuffer.isNotEmpty) {
         await _sendHeartRateSamplesToApi(currentState.sessionId, _heartRateService.heartRateBuffer);
        _heartRateService.clearHeartRateBuffer();
      }
      
      if (!currentState.sessionId.startsWith('offline_')) {
        await _apiClient.post('/rucks/${currentState.sessionId}/pause', {});
      }
      AppLogger.debug('Session ${currentState.sessionId} paused.');
      
      emit(currentState.copyWith(
        isPaused: true,
        currentPauseStartTimeUtc: DateTime.now().toUtc(),
      ));
      await _watchService.pauseSessionOnWatch();
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (!currentState.isPaused || currentState.currentPauseStartTimeUtc == null) return;

      final pauseEndTime = DateTime.now().toUtc();
      final Duration currentPauseDuration = pauseEndTime.difference(currentState.currentPauseStartTimeUtc!);
      final Duration newTotalPausedDuration = currentState.totalPausedDuration + currentPauseDuration;
      
      _heartRateService.startHeartRateMonitoring(); // Restart HR monitoring after pause
      
      if (!currentState.sessionId.startsWith('offline_')) {
        await _apiClient.post('/rucks/${currentState.sessionId}/resume', {});
      }
      AppLogger.debug('Session ${currentState.sessionId} resumed.');

      emit(currentState.copyWith(
        isPaused: false,
        totalPausedDuration: newTotalPausedDuration,
        currentPauseStartTimeUtc: null,
      ));
      await _watchService.resumeSessionOnWatch();
      _lastTickTime = DateTime.now(); // Reset last tick time to avoid large jump in elapsed time
    }
  }

  Future<void> _onSessionCompleted(
    SessionCompleted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    final startTime = DateTime.now();
    
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      
      // Start tracking session completion flow
      AppLogger.sessionCompletion('Session completion started', context: {
        'session_id': currentState.sessionId,
        'distance_km': currentState.distanceKm,
        'duration_seconds': _elapsedCounter,
      });
      
      try {
        AppLogger.sessionCompletion('Stopping services', context: {
          'session_id': currentState.sessionId,
        });
        
        _stopTickerAndWatchdog();
        _locationService.stopLocationTracking();
        await _stopHeartRateMonitoring();

        AppLogger.sessionCompletion('Services stopped, calculating final stats', context: {
          'session_id': currentState.sessionId,
        });

        Duration finalTotalPausedDuration = currentState.totalPausedDuration;
        if (currentState.isPaused && currentState.currentPauseStartTimeUtc != null) {
          finalTotalPausedDuration += DateTime.now().toUtc().difference(currentState.currentPauseStartTimeUtc!);
        }
        final int finalDurationSeconds = _elapsedCounter; // Use the BLoC's tracked elapsed time

        final double finalDistanceKm = currentState.distanceKm;
        // Check if auth state is Authenticated before accessing user property
        final authState = GetIt.I<AuthBloc>().state;
        final User? currentUser = authState is Authenticated ? authState.user : null;
        final double userWeightKg = currentUser?.weightKg ?? 70.0;
        
        // Calculate final terrain multiplier and stats
        final double terrainMultiplier = TerrainSegment.calculateWeightedTerrainMultiplier(currentState.terrainSegments);
        final Map<String, dynamic> terrainStats = TerrainSegment.getTerrainStats(currentState.terrainSegments);
        
        // Enhanced calorie calculation using the MetCalculator with terrain support
        final double finalCalories = MetCalculator.calculateRuckingCalories(
          userWeightKg: userWeightKg,
          ruckWeightKg: currentState.ruckWeightKg,
          distanceKm: finalDistanceKm,
          elapsedSeconds: finalDurationSeconds,
          elevationGain: currentState.elevationGain,
          elevationLoss: currentState.elevationLoss,
          gender: currentUser?.gender,
          terrainMultiplier: terrainMultiplier,
        );

        int? avgHeartRate;
        if (_allHeartRateSamples.isNotEmpty) {
          avgHeartRate = _allHeartRateSamples.map((s) => s.bpm).reduce((a, b) => a + b) ~/ _allHeartRateSamples.length;
        }

        AppLogger.sessionCompletion('Stats calculated, building payload', context: {
          'session_id': currentState.sessionId,
        });

        // Build payload in background to prevent UI blocking for large datasets
        final Map<String, dynamic> payload = await _buildCompletionPayloadInBackground(
          currentState,
          terrainStats,
          currentState.locationPoints,
          _allHeartRateSamples,
        );

        AppLogger.sessionCompletion('Session completion payload built', context: {
          'session_id': currentState.sessionId,
          'payload_size_bytes': payload.toString().length,
        });
        
        // Check if this is an offline session
        final bool isOfflineSession = currentState.sessionId.startsWith('offline_');
        
        if (isOfflineSession) {
          AppLogger.sessionCompletion('Handling offline session', context: {
            'session_id': currentState.sessionId,
          });
          
          // Store completed session data locally for later sync
          await _activeSessionStorage.saveCompletedOfflineSession(currentState, payload);
          
          // Emit completed state immediately for offline sessions
          emit(ActiveSessionCompleted(
            sessionId: currentState.sessionId,
            finalDistanceKm: currentState.distanceKm,
            finalDurationSeconds: currentState.elapsedSeconds,
            finalCalories: currentState.calories.round(),
            elevationGain: currentState.elevationGain,
            elevationLoss: currentState.elevationLoss,
            averagePace: currentState.pace,
            route: currentState.locationPoints,
            heartRateSamples: _allHeartRateSamples,
            averageHeartRate: currentState.latestHeartRate,
            minHeartRate: currentState.minHeartRate,
            maxHeartRate: currentState.maxHeartRate,
            sessionPhotos: currentState.photos,
            splits: _splitTrackingService.getSplits(),
            completedAt: DateTime.now().toUtc(),
            isOffline: true,
          ));
          
          // Clear active session data
          await _activeSessionStorage.clearSessionData();
          
          AppLogger.sessionCompletion('Offline session completed successfully', context: {
            'session_id': currentState.sessionId,
            'total_time_ms': DateTime.now().difference(startTime).inMilliseconds,
          });
          
          // Try to sync offline sessions in background
          _syncOfflineSessionsInBackground();
          return;
        }
        
        // For online sessions, proceed with API calls
        AppLogger.sessionCompletion('Starting online session completion', context: {
          'session_id': currentState.sessionId,
        });

        try {
          // Set a timeout for the entire session completion API flow
          final completionTimeout = Duration(seconds: 30);
          
          // First, check if the session is still valid by trying to get its current status
          try {
            AppLogger.sessionCompletion('Checking session status', context: {
              'session_id': currentState.sessionId,
            });
            
            final statusResponse = await _apiClient.get('/rucks/${currentState.sessionId}')
                .timeout(Duration(seconds: 10));
            AppLogger.debug('Session status: $statusResponse');
            
            AppLogger.sessionCompletion('Session status check completed', context: {
              'session_id': currentState.sessionId,
            });
          } catch (e) {
            AppLogger.sessionCompletion('Session status check failed', context: {
              'session_id': currentState.sessionId,
              'error': e.toString(),
            });
            AppLogger.warning('Could not check session status: $e');
          }
          
          AppLogger.sessionCompletion('Starting completion timeout monitoring', context: {
            'session_id': currentState.sessionId,
            'timeout_seconds': completionTimeout.inSeconds,
          });
          
          AppLogger.sessionCompletion('Starting session completion API call', context: {
            'session_id': currentState.sessionId,
            'payload_size': payload.toString().length,
          });

          final response = await _apiClient.postSessionCompletion(
            '/rucks/${currentState.sessionId}/complete', 
            payload
          ).timeout(completionTimeout, onTimeout: () {
            AppLogger.sessionCompletion('Session completion API call timed out', context: {
              'session_id': currentState.sessionId,
              'timeout_duration_seconds': completionTimeout.inSeconds,
            });
            throw TimeoutException('Session completion timed out');
          });

          AppLogger.sessionCompletion('Session completion API call succeeded', context: {
            'session_id': currentState.sessionId,
            'response_data': response,
          });

          // Handle response and check for errors...
          if (response is Map<String, dynamic> && response.containsKey('message')) {
            final errorMessage = response['message'] as String;
            AppLogger.error('Session completion failed: $errorMessage');
            
            AppLogger.sessionCompletion('API returned error message', context: {
              'session_id': currentState.sessionId,
              'error_message': errorMessage,
            });
            
            // Handle session not found (404) - clear local cache and go to homepage
            if (errorMessage.contains('Session not found') || errorMessage.contains('not found')) {
              AppLogger.sessionCompletion('Session not found, clearing local storage', context: {
                'session_id': currentState.sessionId,
              });
              
              AppLogger.warning('Session ${currentState.sessionId} not found on server, clearing local storage and returning to homepage');
              await _activeSessionStorage.clearSessionData();
              emit(ActiveSessionInitial());
              return;
            }
            
            // If session is not in progress, it might already be completed
            if (errorMessage.contains('not in progress')) {
              AppLogger.sessionCompletion('Session already completed, fetching data', context: {
                'session_id': currentState.sessionId,
              });
              
              // Try to fetch the completed session data
              try {
                AppLogger.debug('Attempting to fetch already completed session ${currentState.sessionId}...');
                final completedResponse = await _apiClient.get('/rucks/${currentState.sessionId}')
                    .timeout(Duration(seconds: 15));
                final completedSession = RuckSession.fromJson(completedResponse);
                
                AppLogger.sessionCompletion('Fetched completed session data', context: {
                  'session_id': currentState.sessionId,
                });
                
                AppLogger.debug('Found completed session, proceeding with summary...');
                final RuckSession enrichedSession = completedSession.copyWith(
                  heartRateSamples: completedSession.heartRateSamples ?? _allHeartRateSamples,
                  avgHeartRate: completedSession.avgHeartRate ?? avgHeartRate,
                  maxHeartRate: completedSession.maxHeartRate ?? _maxHeartRate,
                  minHeartRate: completedSession.minHeartRate ?? _minHeartRate
                );
                
                emit(SessionSummaryGenerated(session: enrichedSession, photos: currentState.photos, isPhotosLoading: false));
                await _activeSessionStorage.clearSessionData();
                
                AppLogger.sessionCompletion('Session completion flow finished successfully (already completed)', context: {
                  'session_id': currentState.sessionId,
                  'total_time_ms': DateTime.now().difference(startTime).inMilliseconds,
                });
                return;
              } catch (fetchError) {
                AppLogger.sessionCompletion('Failed to fetch completed session', context: {
                  'session_id': currentState.sessionId,
                  'fetch_error': fetchError.toString(),
                });
                
                AppLogger.error('Could not fetch completed session: $fetchError');
                // If fetch also fails with 404, clear local storage and go to homepage
                if (fetchError.toString().contains('404') || fetchError.toString().contains('not found')) {
                  AppLogger.warning('Session ${currentState.sessionId} definitely not found, clearing local storage and returning to homepage');
                  await _activeSessionStorage.clearSessionData();
                  emit(ActiveSessionInitial());
                  return;
                }
              }
            }
            
            throw Exception('Session completion failed: $errorMessage');
          }
          
          AppLogger.sessionCompletion('Parsing completion response', context: {
            'session_id': currentState.sessionId,
          });
          
          final RuckSession completedSession = RuckSession.fromJson(response);
          
          AppLogger.debug('Session ${currentState.sessionId} completed successfully.');
          AppLogger.sessionCompletion('Session marked as completed', context: {
            'session_id': currentState.sessionId,
          });
        
        // Create a modified session that includes heart rate data if not present in the API response
        final RuckSession enrichedSession = completedSession.copyWith(
          heartRateSamples: completedSession.heartRateSamples ?? _allHeartRateSamples,
          avgHeartRate: completedSession.avgHeartRate ?? avgHeartRate,
          maxHeartRate: completedSession.maxHeartRate ?? _maxHeartRate,
          minHeartRate: completedSession.minHeartRate ?? _minHeartRate
        );
        
        AppLogger.sessionCompletion('Emitting session summary', context: {
          'session_id': currentState.sessionId,
        });
        
        emit(SessionSummaryGenerated(session: enrichedSession, photos: currentState.photos, isPhotosLoading: false));
        await _activeSessionStorage.clearSessionData();
        AppLogger.debug('Session data cleared from local storage (newly completed)');
        
        AppLogger.sessionCompletion('Session completion flow finished successfully', context: {
          'session_id': currentState.sessionId,
          'total_time_ms': DateTime.now().difference(startTime).inMilliseconds,
        });
        
        // Log heart rate data for debugging
        AppLogger.debug('Heart rate samples count: ${_allHeartRateSamples.length}');
        AppLogger.debug('Avg HR: $avgHeartRate, Min HR: $_minHeartRate, Max HR: $_maxHeartRate');
        
        _watchService.endSessionOnWatch().catchError((e) {
          // Just log the error but don't block UI progression
          AppLogger.error('Error ending session on watch (non-blocking): $e');
        });
        
        // Health service integration should continue regardless of watch status
        await _healthService.saveWorkout(
              startDate: completedSession.startTime ?? currentState.originalSessionStartTimeUtc.subtract(finalTotalPausedDuration),
              endDate: completedSession.endTime ?? DateTime.now().toUtc(),
              distanceKm: completedSession.distance,
              caloriesBurned: completedSession.caloriesBurned,
              heartRate: completedSession.avgHeartRate?.toDouble(), // Convert int? to double?
              ruckWeightKg: completedSession.ruckWeightKg,
              elevationGainMeters: completedSession.elevationGain,
              elevationLossMeters: completedSession.elevationLoss,
        );

      } catch (e, stackTrace) {
        final completionDuration = DateTime.now().difference(startTime).inMilliseconds;
        
        // Check if this is a timeout/hang issue
        if (e.toString().contains('TimeoutException') || completionDuration > 45000) {
          AppLogger.sessionCompletion('Session completion timed out or hung', context: {
            'session_id': currentState.sessionId,
            'duration_seconds': completionDuration ~/ 1000,
          });
        } else {
          AppLogger.sessionCompletion('Session completion failed with error', context: {
            'session_id': currentState.sessionId,
            'error': e.toString(),
            'duration_ms': completionDuration,
          });
        }
        
        String errorMessage = ErrorHandler.getUserFriendlyMessage(e, 'Session Complete');
        AppLogger.error('Error completing session: $errorMessage\nError: $e\n$stackTrace');
        // Pass the current state directly instead of trying to convert it
        emit(ActiveSessionFailure(errorMessage: errorMessage, sessionDetails: currentState));
      }
      } catch (e, stackTrace) { // CATCH FOR OUTER TRY (started on line 566)
        final completionDuration = DateTime.now().difference(startTime).inMilliseconds;
        
        AppLogger.sessionCompletion('Session completion failed at high level', context: {
          'session_id': state is ActiveSessionRunning ? (state as ActiveSessionRunning).sessionId : 'unknown',
          'duration_seconds': completionDuration ~/ 1000,
        });
        
        AppLogger.error(
          'Unhandled error in _onSessionCompleted main processing: $e',
          exception: e,
          stackTrace: stackTrace,
        );
        // currentState is defined at the start of the 'if (state is ActiveSessionRunning)' block
        emit(ActiveSessionFailure(
          errorMessage: 'An unexpected error occurred while completing the session.',
          sessionDetails: currentState, 
        ));
      } 
    } else {
      emit(ActiveSessionInitial());
    }
  }

  Future<void> _onSessionFailed(
    SessionFailed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.error('SessionFailed event: ${event.errorMessage}, Session ID: ${event.sessionId}');
    _stopTickerAndWatchdog();
    _locationService.stopLocationTracking();
    await _stopHeartRateMonitoring();

    ActiveSessionRunning? sessionDetails;
    if (state is ActiveSessionRunning) {
        sessionDetails = state as ActiveSessionRunning;
    }

    try {
      AppLogger.debug('Session ${event.sessionId} failed with error: ${event.errorMessage}');
    } catch (e) {
      AppLogger.error('Error handling session failure for session ${event.sessionId}: $e');
    }
    
    emit(ActiveSessionFailure(errorMessage: event.errorMessage, sessionDetails: sessionDetails));
    // End the session on the watch (discardSessionOnWatch no longer exists)
    await _watchService.endSessionOnWatch();
  }

  Future<void> _startHeartRateMonitoring(String sessionId) async {
    if (_isHeartRateMonitoringStarted) return;
    _heartRateSubscription?.cancel();
    _heartRateSubscription = _heartRateService.heartRateStream.listen((sample) {
      if (!isClosed) add(HeartRateUpdated(sample));
    }, onError: (error) {
      AppLogger.error('Error in heart rate sample stream: $error');
    });

    _heartRateBufferSubscription?.cancel();
    _heartRateBufferSubscription = _heartRateService.heartRateBufferStream.listen((samples) {
      if (!isClosed && samples.isNotEmpty) add(HeartRateBufferProcessed(samples));
    }, onError: (error) {
      AppLogger.error('Error in heart rate buffer stream: $error');
    });

    await _heartRateService.startHeartRateMonitoring();
    _isHeartRateMonitoringStarted = true;
    AppLogger.debug('Heart rate monitoring started for session $sessionId.');
  }

  Future<void> _stopHeartRateMonitoring() async {
    if (!_isHeartRateMonitoringStarted) return;
    _heartRateSubscription?.cancel(); _heartRateSubscription = null;
    _heartRateBufferSubscription?.cancel(); _heartRateBufferSubscription = null;
    // Send any final buffered samples before stopping the service
    if (state is ActiveSessionRunning && _heartRateService.heartRateBuffer.isNotEmpty) {
        await _sendHeartRateSamplesToApi((state as ActiveSessionRunning).sessionId, _heartRateService.heartRateBuffer);
    }
    _heartRateService.stopHeartRateMonitoring();
    _isHeartRateMonitoringStarted = false;
    AppLogger.debug('Heart rate monitoring stopped.');
  }

  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning && !(state as ActiveSessionRunning).isPaused) {
      final currentState = state as ActiveSessionRunning;
      final bpm = event.sample.bpm;
      _latestHeartRate = bpm;

      if (_minHeartRate == null || bpm < _minHeartRate!) _minHeartRate = bpm;
      if (_maxHeartRate == null || bpm > _maxHeartRate!) _maxHeartRate = bpm;
      
      // Throttle heart rate sample storage - only save every 30 seconds
      final now = DateTime.now();
      final shouldSaveSample = _lastSavedHeartRateTime == null || 
          now.difference(_lastSavedHeartRateTime!).inSeconds >= 30;
      
      if (shouldSaveSample) {
        _allHeartRateSamples.add(event.sample);
        _lastSavedHeartRateTime = now;
        AppLogger.debug('[HR_THROTTLE] Saved heart rate sample: ${bpm}bpm (${_allHeartRateSamples.length} total saved)');
      } else {
        AppLogger.debug('[HR_THROTTLE] Skipped heart rate sample: ${bpm}bpm (throttled)');
      }
      
      // The main _onTick handler will emit state with updated HR lists and values.
      // Emitting here might be too frequent if samples come rapidly.
      // However, if live HR display needs sub-second updates, emit here:
      // emit(currentState.copyWith(latestHeartRate: _latestHeartRate, minHeartRate: _minHeartRate, maxHeartRate: _maxHeartRate, heartRateSamples: _allHeartRateSamples.toList()));
    }
  }

  Future<void> _onHeartRateBufferProcessed(
    HeartRateBufferProcessed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      
      // Apply the same 30-second throttling to API uploads as we do for local storage
      final now = DateTime.now();
      final shouldSendToApi = _lastApiHeartRateTime == null || 
          now.difference(_lastApiHeartRateTime!).inSeconds >= 30;
      
      if (shouldSendToApi) {
        await _sendHeartRateSamplesToApi(currentState.sessionId, event.samples);
        AppLogger.debug('[HR_API_THROTTLE] Sent ${event.samples.length} heart rate samples to API');
        _lastApiHeartRateTime = now;
      } else {
        AppLogger.debug('[HR_API_THROTTLE] Skipped sending ${event.samples.length} heart rate samples to API (throttled)');
      }
      // Optionally emit state if UI needs to reflect that a batch was sent, though usually not needed.
    }
  }

  Future<void> _sendHeartRateSamplesToApi(String sessionId, List<HeartRateSample> samples) async {
    if (samples.isEmpty || sessionId.isEmpty) return;
    
    // Skip API calls for offline sessions
    if (sessionId.startsWith('offline_')) {
      AppLogger.debug('Skipping heart rate API call for offline session: $sessionId');
      return;
    }
    
    try {
      final List<Map<String, dynamic>> samplesJson = samples.map((s) => s.toJsonForApi()).toList();
      // Use path without /api prefix since baseUrl already includes it
      await _apiClient.post('/rucks/$sessionId/heartrate', {'samples': samplesJson});
      AppLogger.debug('Sent ${samples.length} heart rate samples to API for $sessionId.');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to send heart rate samples to API: $e\n$stackTrace');
    }
  }

  Future<void> _onFetchSessionPhotosRequested(
    FetchSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
  String? sessionId;
  bool isLoading = false;
  
  // Handle different states to fetch photos
  if (state is ActiveSessionRunning) {
    final currentState = state as ActiveSessionRunning;
    emit(currentState.copyWith(isPhotosLoading: true));
    sessionId = currentState.sessionId;
    isLoading = true;
  } else if (state is SessionSummaryGenerated) {
    final currentState = state as SessionSummaryGenerated;
    emit(currentState.copyWith(isPhotosLoading: true));
    sessionId = currentState.session.id;
    isLoading = true;
  } else {
    // If we have a session ID from the event, use that
    sessionId = event.ruckId;
  }
  
  // If we have a session ID, fetch photos
  if (sessionId != null && sessionId.isNotEmpty) {
    try {
      final photos = await _sessionRepository.getSessionPhotos(sessionId);
      
      // Update the state based on the current state type
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(photos: photos, isPhotosLoading: false));
      } else if (state is SessionSummaryGenerated) {
        final currentState = state as SessionSummaryGenerated;
        emit(currentState.copyWith(photos: photos, isPhotosLoading: false));
      }
      
      // Always emit SessionPhotosLoadedForId state to ensure photos are accessible
      // by components listening specifically for this state
      emit(SessionPhotosLoadedForId(sessionId: sessionId, photos: photos));
    } catch (e) {
      AppLogger.error('Failed to fetch session photos: $e');
      
      // Update the error state based on the current state type
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Failed to load photos'));
      } else if (state is SessionSummaryGenerated) {
        final currentState = state as SessionSummaryGenerated;
        emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Failed to load photos'));
      }
    }
  } else if (isLoading) {
    // Handle missing session ID only for states that were set to loading
    if (state is SessionSummaryGenerated) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Session ID is missing'));
    } else if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Session ID is missing'));
    }
  }
    }

  Future<void> _onUploadSessionPhotosRequested(
      UploadSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.info('[PHOTO_DEBUG] _onUploadSessionPhotosRequested called with ${event.photos.length} photos');
    AppLogger.info('[PHOTO_DEBUG] Current state: ${state.runtimeType}');
    AppLogger.info('[PHOTO_DEBUG] Session ID: ${event.sessionId}');
    
    // Extract sessionId from event, not state (works in all states)
    final sessionId = event.sessionId;
    
    // For any state, we can upload photos and then fetch them again
    try {
      AppLogger.info('[PHOTO_DEBUG] About to call _sessionRepository.uploadSessionPhotos with sessionId: $sessionId');
      
      // Upload the photos
      final uploadedPhotos = await _sessionRepository.uploadSessionPhotos(sessionId, event.photos);
      AppLogger.info('[PHOTO_DEBUG] Upload successful! Got ${uploadedPhotos.length} photos back from server');
      
      // Fetch the updated photos to refresh the UI
      AppLogger.info('[PHOTO_DEBUG] Fetching all photos for session after successful upload');
      final allSessionPhotos = await _sessionRepository.getSessionPhotos(sessionId);
      AppLogger.info('[PHOTO_DEBUG] Fetched ${allSessionPhotos.length} total photos for session');
      
      // Update state based on current state type
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(photos: allSessionPhotos, isPhotosLoading: false));
        AppLogger.info('[PHOTO_DEBUG] Updated ActiveSessionRunning state with photos');
      } else if (state is SessionSummaryGenerated) {
        final savedState = state as SessionSummaryGenerated;
        // The photos are stored separately in the SessionSummaryGenerated state, not in the session object
        emit(SessionSummaryGenerated(
          session: savedState.session,
          photos: allSessionPhotos,
          isPhotosLoading: false
        ));
        AppLogger.info('[PHOTO_DEBUG] Updated SessionSummaryGenerated state with photos');
      } else {
        AppLogger.info('[PHOTO_DEBUG] State type not supported for photo updates: ${state.runtimeType}');
      }
    } catch (e) {
      AppLogger.error('[PHOTO_DEBUG] Failed to upload session photos: $e');
      
      // Maintain state with error message
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Failed to upload photos'));
      }
    }
  }

  Future<void> _onDeleteSessionPhotoRequested(
      DeleteSessionPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    // Common code for extracting the photo ID
    String photoId = '';
    if (event.photo is RuckPhoto) {
      photoId = (event.photo as RuckPhoto).id;
    } else if (event.photo is String) {
      photoId = event.photo as String;
    } else if (event.photo is Map && event.photo['id'] != null) {
      photoId = event.photo['id'].toString();
    }
    
    if (photoId.isEmpty) {
      AppLogger.error('Invalid photo ID for deletion');
      return;
    }
    
    // Create a RuckPhoto object to pass to the deletePhoto method
    final photo = RuckPhoto(
      id: photoId,
      ruckId: event.sessionId,
      userId: '', // Required field
      filename: '', // Required field
      createdAt: DateTime.now(), // Required field
    );
    
    AppLogger.debug('[PHOTO_DEBUG] Deleting photo with ID: $photoId for session ${event.sessionId}');
    
    // Handle both active session and completed session states
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(isPhotosLoading: true));
      
      try {
        final success = await _sessionRepository.deletePhoto(photo);
        if (success) {
          final updatedPhotos = currentState.photos.where((p) => p.id != photoId).toList();
          emit(currentState.copyWith(photos: updatedPhotos, isPhotosLoading: false));
          AppLogger.info('[PHOTO_DEBUG] Successfully deleted photo from ActiveSessionRunning state');
        } else {
          throw Exception('Failed to delete photo from repository');
        }
      } catch (e) {
        AppLogger.error('[PHOTO_DEBUG] Failed to delete session photo: $e');
        emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Failed to delete photo'));
      }
    } else if (state is SessionSummaryGenerated) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(isPhotosLoading: true));
      
      try {
        final success = await _sessionRepository.deletePhoto(photo);
        if (success) {
          final updatedPhotos = currentState.photos.where((p) => p.id != photoId).toList();
          emit(currentState.copyWith(photos: updatedPhotos, isPhotosLoading: false));
          AppLogger.info('[PHOTO_DEBUG] Successfully deleted photo from SessionSummaryGenerated state');
        } else {
          throw Exception('Failed to delete photo from repository');
        }
      } catch (e) {
        AppLogger.error('[PHOTO_DEBUG] Failed to delete session photo: $e');
        emit(currentState.copyWith(isPhotosLoading: false, photosError: 'Failed to delete photo'));
      }
    } else {
      AppLogger.error('[PHOTO_DEBUG] Cannot delete photo - unsupported state: ${state.runtimeType}');
    }
  }

  void _onClearSessionPhotos(ClearSessionPhotos event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photos: []));
    }
  }

  Future<void> _onTakePhotoRequested(TakePhotoRequested event, Emitter<ActiveSessionState> emit) async {
    if (state is! ActiveSessionRunning) return;
    final currentState = state as ActiveSessionRunning;
    
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        add(UploadSessionPhotosRequested(
          sessionId: currentState.sessionId,
          photos: [File(photo.path)]
        ));
      }
    } catch (e) {
      AppLogger.error('Error taking photo: $e');
      emit(currentState.copyWith(photosError: 'Failed to take photo'));
    }
  }

  Future<void> _onPickPhotoRequested(PickPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    if (state is! ActiveSessionRunning) return;
    final currentState = state as ActiveSessionRunning;
    
    final ImagePicker picker = ImagePicker();
    try {
      final List<XFile> photos = await picker.pickMultiImage();
      if (photos.isNotEmpty) {
        add(UploadSessionPhotosRequested(
          sessionId: currentState.sessionId,
          photos: photos.map((p) => File(p.path)).toList()
        ));
      }
    } catch (e) {
      AppLogger.error('Error picking photos: $e');
      emit(currentState.copyWith(photosError: 'Failed to pick photos'));
    }
  }
  
  Future<void> _onLoadSessionForViewing(LoadSessionForViewing event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Loading session for viewing: ${event.session.id}');
  
    // Initialize session and photos as provided
    RuckSession session = event.session;
    List<RuckPhoto> photos = [];
    bool isLoading = true;
    String? photosError;
    String? heartRateError;

    // Initial emit with loading state to show activity to the user
    if (session.id != null && session.id!.isNotEmpty) {
      emit(SessionSummaryGenerated(session: session, photos: photos, isPhotosLoading: true));
      
      try {
        // IMPROVED: Always try to fetch heart rate samples for better user experience
        // This will fetch samples even if we don't have avgHeartRate/maxHeartRate/minHeartRate indicators
        String? heartRateError;
        try {
          AppLogger.debug('[HEARTRATE DEBUG] Fetching heart rate samples for session ${session.id}');
          final heartRateSamples = await _sessionRepository.fetchHeartRateSamples(session.id!);
          
          if (heartRateSamples.isEmpty) {
            AppLogger.debug('[HEARTRATE DEBUG] No heart rate samples found for session ${session.id}');
            // If we have existing heart rate stats in the session but no samples, use those
            if (session.avgHeartRate != null || session.maxHeartRate != null) {
              AppLogger.debug('[HEARTRATE DEBUG] Using existing heart rate stats from session data');
            }
          } else {
            AppLogger.debug('[HEARTRATE DEBUG] Found ${heartRateSamples.length} heart rate samples for session ${session.id}');
            
            // Calculate heart rate statistics if needed
            if (session.avgHeartRate == null || session.maxHeartRate == null) {
              AppLogger.debug('[HEARTRATE DEBUG] Calculating heart rate statistics for session ${session.id}');
              
              // Find average heart rate
              final avgHeartRate = heartRateSamples.isNotEmpty
                ? heartRateSamples.map((s) => s.bpm).reduce((a, b) => a + b) / heartRateSamples.length
                : 0;
                
              // Find max heart rate
              final maxHeartRate = heartRateSamples.isNotEmpty
                ? heartRateSamples.map((s) => s.bpm).reduce((a, b) => a > b ? a : b)
                : 0;
                
              // Find min heart rate
              final minHeartRate = heartRateSamples.isNotEmpty
                ? heartRateSamples.map((s) => s.bpm).reduce((a, b) => a < b ? a : b)
                : 0;
              
              AppLogger.debug('[HEARTRATE DEBUG] Calculated avg: $avgHeartRate, max: $maxHeartRate, min: $minHeartRate');
              
              // Update session with calculated values
              session = session.copyWith(
                heartRateSamples: heartRateSamples,
                avgHeartRate: avgHeartRate.round(),
                maxHeartRate: maxHeartRate.round(),
                minHeartRate: minHeartRate.round()
              );
            } else {
              // Just attach the samples to the session
              session = session.copyWith(heartRateSamples: heartRateSamples);
            }
          }
        } catch (e) {
          AppLogger.error('Error fetching heart rate samples: $e');
          heartRateError = 'Failed to load heart rate data';
        }
        
        // Fetch photos
        try {
          photos = await _sessionRepository.getSessionPhotos(session.id!);
        } catch (e) {
          AppLogger.error('Failed to fetch photos for viewed session ${session.id}: $e');
          photosError = 'Failed to load photos';
        }
        
        // Final emit with all loaded data
        emit(SessionSummaryGenerated(
          session: session, 
          photos: photos, 
          isPhotosLoading: false, 
          photosError: photosError
        ));
        await _activeSessionStorage.clearSessionData();
        
      } catch (e) {
        AppLogger.error('Error loading session for viewing: $e');
        emit(SessionSummaryGenerated(
          session: session, 
          photos: photos, 
          isPhotosLoading: false, 
          photosError: 'Failed to load session data'
        ));
      }
    } else {
      // No session ID, just emit what we have
      emit(SessionSummaryGenerated(session: session, photos: photos, isPhotosLoading: false));
    }
  }

  void _onUpdateStateWithSessionPhotos(UpdateStateWithSessionPhotos event, Emitter<ActiveSessionState> emit) {
      // Cast List<dynamic> to List<RuckPhoto> to fix type mismatch
      final List<RuckPhoto> typedPhotos = event.photos.map((photo) => 
          photo is RuckPhoto ? photo : RuckPhoto.fromJson(photo as Map<String, dynamic>)
      ).toList();
      
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(photos: typedPhotos, isPhotosLoading: false));
      } else if (state is SessionSummaryGenerated) {
        final currentState = state as SessionSummaryGenerated;
        emit(currentState.copyWith(photos: typedPhotos, isPhotosLoading: false));
      }
  }

  void _onSessionErrorCleared(SessionErrorCleared event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionFailure) {
      // Potentially transition to a more stable state, e.g., ActiveSessionInitial
      // or back to the previous running state if details are available and make sense.
      // For simplicity, transitioning to initial.
      emit(ActiveSessionInitial()); 
    } else if (state is ActiveSessionRunning && (state as ActiveSessionRunning).errorMessage != null) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(clearErrorMessage: true));
    } else if (state is SessionSummaryGenerated && (state as SessionSummaryGenerated).errorMessage != null) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(clearErrorMessage: true));
    }
  }

  Future<void> _onSessionRecoveryRequested(
    SessionRecoveryRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    try {
      AppLogger.info('[SESSION_RECOVERY] Checking for recoverable session...');
      
      // Check if we should recover a session
      final shouldRecover = await _activeSessionStorage.shouldRecoverSession();
      if (!shouldRecover) {
        AppLogger.info('[SESSION_RECOVERY] No recoverable session found or session too old');
        return;
      }

      // Recover the session data
      final recoveredData = await _activeSessionStorage.recoverSession();
      if (recoveredData == null) {
        AppLogger.warning('[SESSION_RECOVERY] Failed to recover session data');
        return;
      }

      // Reconstruct the ActiveSessionRunning state
      final sessionId = recoveredData['session_id'] as String;
      final locationPoints = recoveredData['location_points'] as List<LocationPoint>;
      final heartRateSamples = recoveredData['heart_rate_samples'] as List<HeartRateSample>;
      
      // Restore internal state
      _allHeartRateSamples.clear();
      _allHeartRateSamples.addAll(heartRateSamples);
      _latestHeartRate = recoveredData['latest_heart_rate'] as int?;
      _minHeartRate = recoveredData['min_heart_rate'] as int?;
      _maxHeartRate = recoveredData['max_heart_rate'] as int?;
      
      // Reset heart rate throttling timers for fresh session
      _lastSavedHeartRateTime = null;
      _lastApiHeartRateTime = null;
      
      // Initialize elapsed counter with recovered time so timer continues from where it left off
      _elapsedCounter = recoveredData['elapsed_seconds'] as int;
      
      if (locationPoints.isNotEmpty) {
        _lastValidLocation = locationPoints.last;
      }

      // Create the recovered session state
      final recoveredState = ActiveSessionRunning(
        sessionId: sessionId,
        elapsedSeconds: recoveredData['elapsed_seconds'] as int,
        distanceKm: recoveredData['distance_km'] as double,
        calories: recoveredData['calories'] as double,
        elevationGain: recoveredData['elevation_gain'] as double,
        elevationLoss: recoveredData['elevation_loss'] as double,
        ruckWeightKg: recoveredData['ruck_weight_kg'] as double,
        userWeightKg: recoveredData['user_weight_kg'] as double? ?? 70.0, // Default if not available
        locationPoints: locationPoints,
        originalSessionStartTimeUtc: recoveredData['session_start_time'] as DateTime,
        totalPausedDuration: Duration.zero, // Reset pause duration on recovery
        isPaused: false, // Resume as unpaused
        pace: locationPoints.length >= 2 ? 
          _calculateCurrentPace(locationPoints) : null,
        heartRateSamples: heartRateSamples,
        latestHeartRate: _latestHeartRate,
        minHeartRate: _minHeartRate,
        maxHeartRate: _maxHeartRate,
        splits: [], // Will be recalculated if needed
        terrainSegments: [], // Will be recalculated if needed
      );

      emit(recoveredState);

      // Verify authentication is working before starting API-dependent operations
      AppLogger.info('[SESSION_RECOVERY] Verifying authentication before resuming API operations...');
      
      try {
        // Make a simple API call to test if auth is working
        // Use a lightweight endpoint that doesn't affect session state
        await GetIt.I<AuthService>().isAuthenticated();
        AppLogger.info('[SESSION_RECOVERY] Authentication verified, resuming full operations...');
        
        // Auth is working, safe to start location updates and API calls
        _startLocationUpdates(sessionId);
        _startHeartRateMonitoring(sessionId);
        add(TimerStarted());
        
      } catch (authError) {
        AppLogger.warning('[SESSION_RECOVERY] Authentication failed during recovery: $authError');
        
        // Authentication failed - start monitoring without API calls
        // This allows the user to continue their session locally until auth is resolved
        _startHeartRateMonitoring(sessionId);
        add(TimerStarted());
        
        // Don't start location updates yet - they trigger API calls
        // We'll retry authentication periodically via the timer
        AppLogger.info('[SESSION_RECOVERY] Session recovered in offline mode - will retry API sync when auth is restored');
      }

      AppLogger.info('[SESSION_RECOVERY] Successfully recovered session: $sessionId');
      
    } catch (e, stackTrace) {
      AppLogger.error('[SESSION_RECOVERY] Failed to recover session: $e\n$stackTrace');
      // Clear any corrupted session data
      await _activeSessionStorage.clearSessionData();
    }
  }

  Future<void> _onSessionReset(
    SessionReset event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.debug('Resetting session state to initial state');
    
    // Stop any active timers or services
    _stopTickerAndWatchdog();
    
    // Clear heart rate data
    _allHeartRateSamples.clear();
    _maxHeartRate = null;
    _minHeartRate = null;
    
    // Reset counters
    _elapsedCounter = 0;
    
    // Clear any stored active session
    try {
      await _activeSessionStorage.clearSessionData();
    } catch (e) {
      AppLogger.error('Error clearing active session storage: $e');
    }
    
    // Return to initial state
    emit(const ActiveSessionInitial());
  }

  double? _calculateCurrentPace(List<LocationPoint> points) {
    if (points.length < 2) return null;
    
    try {
      final lastPoint = points.last;
      final secondLastPoint = points[points.length - 2];
      
      final distance = _calculateDistance(
        secondLastPoint.latitude, secondLastPoint.longitude,
        lastPoint.latitude, lastPoint.longitude,
      );
      
      final timeDiff = lastPoint.timestamp.difference(secondLastPoint.timestamp).inSeconds;
      if (timeDiff <= 0 || distance <= 0) return null;
      
      // Return pace in minutes per km
      return (timeDiff / 60) / (distance / 1000);
    } catch (e) {
      return null;
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = (lat2 - lat1) * (math.pi / 180);
    final double dLon = (lon2 - lon1) * (math.pi / 180);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) *
            math.cos(lat2 * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  @override
  Future<void> close() async {
    _stopTickerAndWatchdog();
    _locationSubscription?.cancel();
    _batchLocationSubscription?.cancel();
    _heartRateSubscription?.cancel();
    _heartRateBufferSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _locationService.stopLocationTracking();
    await _stopHeartRateMonitoring(); 
    _log('ActiveSessionBloc closed, all resources released.');
    super.close();
  }

  /// Helper method to work around analyzer issue with AppLogger
  void _log(String message) {
    // Using try-catch to ensure this doesn't cause further issues
    try {
      if (kDebugMode) {
        debugPrint('[DEBUG] $message');
      }
    } catch (e) {
      // Silent catch - last resort to prevent logging issues from breaking functionality
    }
  }

  /// Handle session cleanup for app lifecycle management
  Future<void> _onSessionCleanupRequested(
    SessionCleanupRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('Session cleanup requested for app lifecycle');
    
    try {
      final currentState = state;
      
      // If there's an active session, ensure data is persisted
      if (currentState is ActiveSessionRunning) {
        AppLogger.info('Saving active session data during cleanup');
        
        // Force save any pending heart rate data
        if (_allHeartRateSamples.isNotEmpty) {
          await _sendHeartRateSamplesToApi(currentState.sessionId, _allHeartRateSamples);
        }
        
        // Persist current session state
        await _activeSessionStorage.saveActiveSession(currentState);
        
        AppLogger.info('Active session data saved during cleanup');
      }
      
      // Clean up resources but don't fully stop the session
      // (session might need to continue in background)
      AppLogger.info('Session cleanup completed');
      
    } catch (e) {
      AppLogger.error('Error during session cleanup: $e');
    }
  }

  /// Sync offline sessions to backend when connectivity is restored
  void _syncOfflineSessionsInBackground() {
    // Run sync in background without blocking UI
    Timer(const Duration(seconds: 2), () async {
      try {
        await _syncOfflineSessions();
      } catch (e) {
        AppLogger.warning('Background offline session sync failed: $e');
        // Schedule retry in 30 seconds
        Timer(const Duration(seconds: 30), () => _syncOfflineSessionsInBackground());
      }
    });
  }

  /// Sync stored offline sessions to backend
  Future<void> _syncOfflineSessions() async {
    try {
      final offlineSessions = await _activeSessionStorage.getCompletedOfflineSessions();
      if (offlineSessions.isEmpty) {
        AppLogger.info('No offline sessions to sync');
        return;
      }

      AppLogger.info('Found ${offlineSessions.length} offline sessions to sync');

      for (final sessionData in offlineSessions) {
        try {
          // Create session with current session data using the same format as normal session creation
          final createResponse = await _apiClient.post('/rucks', {
            'ruck_weight_kg': sessionData['ruckWeightKg'],
            'notes': sessionData['notes'] ?? '',
          });

          final newSessionId = createResponse['id']?.toString();
          if (newSessionId != null && newSessionId.isNotEmpty) {
            AppLogger.info('Successfully synced offline session. New session ID: $newSessionId');
            
            // Only update state if session is still running
            if (state is ActiveSessionRunning) {
              final currentState = state as ActiveSessionRunning;
              emit(currentState.copyWith(sessionId: newSessionId));
              
              // Start fresh location tracking with new session ID
              _startLocationUpdates(newSessionId);
            } else {
              AppLogger.info('Session already completed, not updating state');
            }
          }
        } catch (e) {
          AppLogger.warning('Failed to sync offline session: $e. Will retry on next connectivity event.');
        }
      }

      // Clean up successfully synced sessions
      await _activeSessionStorage.cleanupSyncedOfflineSessions();
      
    } catch (e) {
      AppLogger.error('Error during offline session sync', exception: e);
      rethrow;
    }
  }

  /// Build session completion payload in background to prevent UI blocking
  Future<Map<String, dynamic>> _buildCompletionPayloadInBackground(
    ActiveSessionRunning currentState,
    Map<String, dynamic> terrainStats,
    List<LocationPoint> route,
    List<HeartRateSample> heartRateSamples,
  ) async {
    final payload = {
      'duration_seconds': currentState.elapsedSeconds,
      'distance_km': currentState.distanceKm,
      'calories_burned': currentState.calories.round(),
      'elevation_gain_m': currentState.elevationGain, // Changed key
      'elevation_loss_m': currentState.elevationLoss, // Changed key
      'average_pace_min_km': currentState.pace, // Changed key
      'route': route.map((p) => p.toJson()).toList(),
      'heart_rate_samples': heartRateSamples.map((s) => s.toJson()).toList(), // Send all collected samples
      'average_heart_rate': currentState.latestHeartRate,
      'min_heart_rate': currentState.minHeartRate,
      'max_heart_rate': currentState.maxHeartRate,
      'session_photos': currentState.photos.map((p) => p.id).toList(),
      'splits': _splitTrackingService.getSplits(), // Already a List<Map<String, dynamic>>
      'terrain_stats': terrainStats, // Include terrain stats in payload
      'is_public': false, // Default to private sessions
      if (currentState.eventId != null) 'event_id': currentState.eventId, // Include event_id if session is event-linked
    };

    // Debug logging for splits to Crashlytics
    final splits = _splitTrackingService.getSplits();
    AppLogger.sessionCompletion('Splits included in completion payload', context: {
      'splits_count': splits.length,
      'splits_data': splits,
      'session_distance_km': currentState.distanceKm,
      'session_duration_seconds': currentState.elapsedSeconds,
    });

    return payload;
  }

  /// Start connectivity monitoring
  void _startConnectivityMonitoring(String sessionId) {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = GetIt.I<ConnectivityService>().connectivityStream.listen((isConnected) {
      // Only handle connectivity changes if we're in a valid session state
      if (state is! ActiveSessionRunning) {
        AppLogger.debug('Ignoring connectivity change - session not running');
        return;
      }
      
      final currentState = state as ActiveSessionRunning;
      
      if (isConnected) {
        AppLogger.info('Connectivity restored, resuming operations for session: ${currentState.sessionId}');
        
        // Add slight delay to prevent race conditions with UI rebuilds
        Timer(const Duration(milliseconds: 100), () async {
          if (state is ActiveSessionRunning) {
            final latestState = state as ActiveSessionRunning;
            
            // Only attempt sync if session is still offline
            if (latestState.sessionId.startsWith('offline_')) {
              await _attemptOfflineSessionSync(latestState.sessionId);
            } else {
              // For online sessions, just ensure location tracking is active
              _ensureLocationTrackingActive(latestState.sessionId);
            }
          }
        });
      } else {
        AppLogger.warning('Connectivity lost for session: ${currentState.sessionId}, switching to offline mode...');
        
        // Only stop location if we're not already in offline mode
        if (!currentState.sessionId.startsWith('offline_')) {
          _locationService.stopLocationTracking();
          
          // Emit validation message to inform user
          emit(currentState.copyWith(
            validationMessage: 'No network connection - session continues in offline mode',
            clearValidationMessage: false,
          ));
          
          // Clear the message after 3 seconds
          Timer(const Duration(seconds: 3), () {
            if (state is ActiveSessionRunning && !isClosed) {
              final latestState = state as ActiveSessionRunning;
              emit(latestState.copyWith(clearValidationMessage: true));
            }
          });
        }
      }
    });
  }

  /// Ensure location tracking is active
  void _ensureLocationTrackingActive(String sessionId) {
    if (_locationSubscription == null) {
      _startLocationUpdates(sessionId);
    }
  }

  /// Attempt to sync offline session
  Future<void> _attemptOfflineSessionSync(String sessionId) async {
    if (sessionId.startsWith('offline_')) {
      try {
        AppLogger.info('Attempting to sync offline session to backend...');
        
        final currentState = state;
        if (currentState is ActiveSessionRunning) {
          // Create session with current session data using the same format as normal session creation
          final createResponse = await _apiClient.post('/rucks', {
            'ruck_weight_kg': currentState.ruckWeightKg,
            'notes': currentState.notes ?? '',
          });

          final newSessionId = createResponse['id']?.toString();
          if (newSessionId != null && newSessionId.isNotEmpty) {
            AppLogger.info('Successfully synced offline session. New session ID: $newSessionId');
            
            // Only update state if session is still running
            if (state is ActiveSessionRunning) {
              final currentState = state as ActiveSessionRunning;
              emit(currentState.copyWith(sessionId: newSessionId));
              
              // Start fresh location tracking with new session ID
              _startLocationUpdates(newSessionId);
            } else {
              AppLogger.info('Session already completed, not updating state');
            }
          }
        }
      } catch (e) {
        AppLogger.warning('Failed to sync offline session: $e. Will retry on next connectivity event.');
      }
    }
  }
}