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
import 'package:rucking_app/core/models/api_exception.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
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

  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  StreamSubscription<List<HeartRateSample>>? _heartRateBufferSubscription;
  Timer? _ticker;
  Timer? _watchdogTimer;
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

  ActiveSessionBloc({
    required ApiClient apiClient,
    required LocationService locationService,
    required HealthService healthService,
    required WatchService watchService,
    required HeartRateService heartRateService,
    required SplitTrackingService splitTrackingService,
    required SessionRepository sessionRepository,
    SessionValidationService? validationService,
  })  : _apiClient = apiClient,
        _locationService = locationService,
        _healthService = healthService,
        _watchService = watchService,
        _heartRateService = heartRateService,
        _splitTrackingService = splitTrackingService,
        _sessionRepository = sessionRepository,
        _validationService = validationService ?? SessionValidationService(),
        super(ActiveSessionInitial()) {
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      GetIt.I.unregister<ActiveSessionBloc>();
    }
    GetIt.I.registerSingleton<ActiveSessionBloc>(this);

    on<SessionStarted>(_onSessionStarted);
    on<LocationUpdated>(_onLocationUpdated);
    on<SessionPaused>(_onSessionPaused);
    on<SessionResumed>(_onSessionResumed);
    on<SessionCompleted>(_onSessionCompleted);
    on<SessionFailed>(_onSessionFailed);
    on<Tick>(_onTick);
    on<SessionErrorCleared>(_onSessionErrorCleared);
    on<TimerStarted>(_onTimerStarted);
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
    _isHeartRateMonitoringStarted = false;
    _elapsedCounter = 0;
    _ticksSinceTruth = 0;
    _lastTickTime = DateTime.now();
    _lastValidLocation = null;
    _validLocationCount = 0;
    _paceTickCounter = 0;

    AppLogger.debug('SessionStarted event. Weight: ${event.ruckWeightKg}kg, Notes: ${event.notes}');
    emit(ActiveSessionLoading());
    String? sessionId;

    try {
      bool hasPermission = await _locationService.hasLocationPermission();
      if (!hasPermission) hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        emit(const ActiveSessionFailure(errorMessage: 'Location permission is required.'));
        return;
      }

      final createResponse = await _apiClient.post('/rucks', {
        'ruck_weight_kg': event.ruckWeightKg,
        'notes': event.notes,
      });
      sessionId = createResponse['id']?.toString();
      if (sessionId == null || sessionId.isEmpty) throw Exception('Failed to create session: No ID.');
      AppLogger.debug('Created new session with ID: $sessionId');

      // Use path with explicit ruck_id as URL parameter to match server expectation
      await _apiClient.post('/rucks/$sessionId/start', {});
      AppLogger.debug('Backend notified of session start for $sessionId');

      final initialSessionState = ActiveSessionRunning(
        sessionId: sessionId,
        locationPoints: const [],
        elapsedSeconds: 0,
        distanceKm: 0.0,
        ruckWeightKg: event.ruckWeightKg,
        notes: event.notes,
        calories: 0,
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
        photos: const [],
        isPhotosLoading: false,
        splits: const [],
      );
      emit(initialSessionState);
      AppLogger.debug('ActiveSessionRunning emitted for $sessionId');

      await _watchService.startSessionOnWatch(event.ruckWeightKg);
      await _watchService.sendSessionIdToWatch(sessionId);

      _validationService.reset();
      _startLocationUpdates(sessionId);
      _startHeartRateMonitoring(sessionId); 
      add(TimerStarted());

    } catch (e, stackTrace) {
      String errorMessage = ErrorHandler.getUserFriendlyMessage(e, 'Session Start');
      AppLogger.error('Error starting session: $errorMessage\nError: $e\n$stackTrace');
      if (sessionId != null && sessionId.isNotEmpty) {
         try {
            await _apiClient.post('/rucks/$sessionId/fail', {'error_message': errorMessage});
         } catch (failError) {
            AppLogger.error('Additionally, failed to mark session $sessionId as failed: $failError');
         }
      }
      emit(ActiveSessionFailure(errorMessage: errorMessage));
    }
  }

  void _startLocationUpdates(String sessionId) {
    _locationSubscription?.cancel();
    _locationSubscription = _locationService.startLocationTracking().listen((location) {
      add(LocationUpdated(location));
    });
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
      if (!(validationResult['isValid'] as bool? ?? false)) { // Safely access 'isValid'
        final String message = validationResult['message'] as String? ?? 'Validation failed, no specific message';
        AppLogger.debug('Invalid location discarded: $message. Acc ${newPoint.accuracy}');
        return;
      }
      _validLocationCount++;
      _lastValidLocation = newPoint;

      List<LocationPoint> newLocationPoints = List.from(currentState.locationPoints)..add(newPoint);
      double newDistanceKm = currentState.distanceKm;
      double newElevationGain = currentState.elevationGain;
      double newElevationLoss = currentState.elevationLoss;

      if (newLocationPoints.length > 1) {
        final prevPoint = newLocationPoints[newLocationPoints.length - 2];
        newDistanceKm += _locationService.calculateDistance(prevPoint, newPoint);

        // Elevation is non-nullable in LocationPoint, direct access is safe if prevPoint and newPoint are valid.
        double elevationChange = newPoint.elevation - prevPoint.elevation;
        if (elevationChange > 0) newElevationGain += elevationChange;
        else newElevationLoss += elevationChange.abs();
      }
      
      _splitTrackingService.checkForMilestone(
        currentDistanceKm: newDistanceKm,
        sessionStartTime: currentState.originalSessionStartTimeUtc,
        elapsedSeconds: currentState.elapsedSeconds,
        isPaused: currentState.isPaused,
      );

      _apiClient.post('/rucks/${currentState.sessionId}/location', newPoint.toJson())
        .catchError((e) => AppLogger.warning('Failed to send location to backend: $e'));

      emit(currentState.copyWith(
        locationPoints: newLocationPoints,
        distanceKm: newDistanceKm,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
        isGpsReady: _validLocationCount > 5,
        splits: _splitTrackingService.getSplits(),
      ));
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
  }

  void _stopTickerAndWatchdog() {
    _ticker?.cancel(); _ticker = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    AppLogger.debug('Master timer and watchdog stopped.');
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
            newPace = (newElapsed / 60.0) / currentState.distanceKm;
        } else { newPace = null; }
      }

      // Check if auth state is Authenticated before accessing user property
      final authState = GetIt.I<AuthBloc>().state;
      User? currentUser = authState is Authenticated ? authState.user : null;
      double userWeightKg = currentUser?.weightKg ?? 70.0;
      // Convert km/h to mph for MetCalculator
      double speedMph = MetCalculator.kmhToMph(newPace != null && newPace > 0 ? (60 / newPace) : 0);
      // Convert kg to lbs for rucksack weight
      double ruckWeightLbs = currentState.ruckWeightKg * 2.20462;

      double metValue = MetCalculator.calculateRuckingMetByGrade(
        speedMph: speedMph,
        grade: 0, // Assuming flat ground if no grade info available
        ruckWeightLbs: ruckWeightLbs,
      );

      // Calculate calories per minute using the standard MET formula
      // MET formula: Calories = MET value × Weight (kg) × Duration (hours)
      // For calories per minute: Calories = MET value × Weight (kg) / 60
      double caloriesPerMinute = metValue * (userWeightKg + currentState.ruckWeightKg) / 60;
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
        calories: newCalories.round(),
        latestHeartRate: _latestHeartRate,
        minHeartRate: _minHeartRate,
        maxHeartRate: _maxHeartRate,
        heartRateSamples: _allHeartRateSamples.toList(),
        splits: _splitTrackingService.getSplits(),
      ));
      
      // Update metrics on watch
      try {
        await _watchService.updateMetricsOnWatch(
          distance: currentState.distanceKm,
          duration: Duration(seconds: newElapsed),
          pace: newPace ?? 0.0,
          isPaused: currentState.isPaused,
          calories: newCalories.round(),
          elevation: currentState.elevationGain,
          elevationLoss: currentState.elevationLoss,
        );
      } catch (e) {
        AppLogger.error('Failed to update metrics on watch: $e');
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
      
      await _apiClient.post('/rucks/${currentState.sessionId}/pause', {});
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
      
      await _apiClient.post('/rucks/${currentState.sessionId}/resume', {});
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
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      _stopTickerAndWatchdog();
      _locationSubscription?.cancel(); _locationSubscription = null;
      _locationService.stopLocationTracking();
      await _stopHeartRateMonitoring(); // Includes sending final buffer

      try {
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
        // Convert km/h to mph for MetCalculator
        double speedMph = MetCalculator.kmhToMph(currentState.pace != null && currentState.pace! > 0 ? (60 / currentState.pace!) : 0);
        // Convert kg to lbs for rucksack weight
        double ruckWeightLbs = currentState.ruckWeightKg * 2.20462;

        final double metValue = MetCalculator.calculateRuckingMetByGrade(
            speedMph: speedMph,
            grade: 0, // Assuming flat ground if no grade info available
            ruckWeightLbs: ruckWeightLbs,
        );

        // Calculate calories per minute using the standard MET formula
        final double caloriesPerMinute = metValue * (userWeightKg + currentState.ruckWeightKg) / 60;
        final double finalCalories = (caloriesPerMinute / 60.0) * finalDurationSeconds;

        int? avgHeartRate;
        if (_allHeartRateSamples.isNotEmpty) {
          avgHeartRate = _allHeartRateSamples.map((s) => s.bpm).reduce((a, b) => a + b) ~/ _allHeartRateSamples.length;
        }

        final payload = {
          'duration_seconds': finalDurationSeconds,
          'distance_km': finalDistanceKm,
          'calories_burned': finalCalories.round(),
          'elevation_gain_meters': currentState.elevationGain,
          'elevation_loss_meters': currentState.elevationLoss,
          'average_pace_min_km': currentState.pace, 
          'route': currentState.locationPoints.map((p) => p.toJson()).toList(),
          'heart_rate_samples': _allHeartRateSamples.map((s) => s.toJson()).toList(), // Send all collected samples
          'average_heart_rate': avgHeartRate,
          'min_heart_rate': _minHeartRate,
          'max_heart_rate': _maxHeartRate,
          'session_photos': currentState.photos.map((p) => p.id).toList(),
          'splits': _splitTrackingService.getSplits(), // Already a List<Map<String, dynamic>>
        };
        
        AppLogger.debug('Completing session ${currentState.sessionId} with payload...');
        final response = await _apiClient.post('/rucks/${currentState.sessionId}/complete', payload);
        final RuckSession completedSession = RuckSession.fromJson(response);
        
        AppLogger.debug('Session ${currentState.sessionId} completed successfully.');
      
      // Create a modified session that includes heart rate data if not present in the API response
      final RuckSession enrichedSession = completedSession.copyWith(
        heartRateSamples: completedSession.heartRateSamples ?? _allHeartRateSamples,
        avgHeartRate: completedSession.avgHeartRate ?? avgHeartRate,
        maxHeartRate: completedSession.maxHeartRate ?? _maxHeartRate,
        minHeartRate: completedSession.minHeartRate ?? _minHeartRate
      );
      
      emit(SessionSummaryGenerated(session: enrichedSession, photos: currentState.photos, isPhotosLoading: false));
      
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
            elevationLossMeters: completedSession.elevationLoss
        );

      } catch (e, stackTrace) {
        String errorMessage = ErrorHandler.getUserFriendlyMessage(e, 'Session Complete');
        AppLogger.error('Error completing session: $errorMessage\nError: $e\n$stackTrace');
        try {
            await _apiClient.post('/rucks/${currentState.sessionId}/fail', {'error_message': 'Completion API call failed: $errorMessage'});
        } catch (failError) {
            AppLogger.error('Additionally, failed to mark session ${currentState.sessionId} as failed: $failError');
        }
        // Pass the current state directly instead of trying to convert it
        emit(ActiveSessionFailure(errorMessage: errorMessage, sessionDetails: currentState));
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
    _locationSubscription?.cancel(); _locationSubscription = null;
    _locationService.stopLocationTracking();
    await _stopHeartRateMonitoring();

    ActiveSessionRunning? sessionDetails;
    if (state is ActiveSessionRunning) {
        sessionDetails = state as ActiveSessionRunning;
    }

    try {
      await _apiClient.post('/rucks/${event.sessionId}/fail', {'error_message': event.errorMessage});
      AppLogger.debug('Marked session ${event.sessionId} as failed on backend.');
    } catch (e) {
      AppLogger.error('Failed to mark session ${event.sessionId} as failed on backend: $e');
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
      
      _allHeartRateSamples.add(event.sample);
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
      // _allHeartRateSamples.addAll(event.samples); // Samples are already added via _onHeartRateUpdated
      await _sendHeartRateSamplesToApi(currentState.sessionId, event.samples);
      // Optionally emit state if UI needs to reflect that a batch was sent, though usually not needed.
    }
  }

  Future<void> _sendHeartRateSamplesToApi(String sessionId, List<HeartRateSample> samples) async {
    if (samples.isEmpty || sessionId.isEmpty) return;
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

  @override
  Future<void> close() async {
    _stopTickerAndWatchdog();
    // Remove reference to non-existent _sessionSubscription
    _locationSubscription?.cancel();
    _heartRateSubscription?.cancel();
    _heartRateBufferSubscription?.cancel();
    _locationService.stopLocationTracking();
    await _stopHeartRateMonitoring(); 
    _log('ActiveSessionBloc closed, all resources released.');
    super.close();
  }

  // Helper method to work around analyzer issue with AppLogger
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
}