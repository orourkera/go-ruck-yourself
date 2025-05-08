import 'dart:math';
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
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
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';

part 'active_session_event.dart';
part 'active_session_state.dart';

class ActiveSessionBloc extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  final ApiClient _apiClient;
  final LocationService _locationService;
  final HealthService _healthService;
  final WatchService _watchService;
  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  Timer? _ticker;
  // Reuse one validation service instance to keep state between points
  final SessionValidationService _validationService = SessionValidationService();
  LocationPoint? _lastValidLocation;
  int _validLocationCount = 0;
  int _latestHeartRate = 0;

  ActiveSessionBloc({
    required ApiClient apiClient,
    required LocationService locationService,
    required HealthService healthService,
    required WatchService watchService,
  }) : _apiClient = apiClient,
       _locationService = locationService,
       _healthService = healthService,
       _watchService = watchService,
       super(ActiveSessionInitial()) {
    on<SessionStarted>(_onSessionStarted);
    on<LocationUpdated>(_onLocationUpdated);
    on<SessionPaused>(_onSessionPaused);
    on<SessionResumed>(_onSessionResumed);
    on<SessionCompleted>(_onSessionCompleted);
    on<SessionFailed>(_onSessionFailed);
    on<HeartRateUpdated>(_onHeartRateUpdated);
    on<Tick>(_onTick);
    on<SessionErrorCleared>(_onSessionErrorCleared);
    on<TimerStarted>(_onTimerStarted);
  }

  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('SessionStarted event received. plannedDuration: \u001B[33m${event.plannedDuration}\u001B[0m seconds');
    AppLogger.info('SessionStarted event received. Weight: ${event.ruckWeightKg}kg, Notes: ${event.notes}');
    emit(ActiveSessionLoading());
    String? sessionId; // Declare sessionId here to be accessible in catch block if needed

    try {
      // Location permissions check
      AppLogger.info('Checking location permission...');
      bool hasPermission = await _locationService.hasLocationPermission();
      if (!hasPermission) {
        AppLogger.info('Requesting location permission.');
        hasPermission = await _locationService.requestLocationPermission();
      }

      if (!hasPermission) {
        AppLogger.warning('Location permission denied.');
        emit(const ActiveSessionFailure(
          errorMessage: 'Location permission is required to start a ruck session. Please enable it in settings.',
        ));
        return;
      }
      AppLogger.info('Location permission granted.');

      // Create a new session in the backend
      AppLogger.info('Creating new ruck session in backend...');
      final createResponse = await _apiClient.post('/rucks', {
        'ruck_weight_kg': event.ruckWeightKg,
        'notes': event.notes,
        // 'planned_duration_seconds': event.plannedDuration, // Add if backend supports this
      });
      
      sessionId = createResponse['id']?.toString();
      
      if (sessionId == null || sessionId.isEmpty) {
        AppLogger.error('Failed to create session: No session ID received from backend.');
        throw Exception('Failed to create session: No session ID received from backend.');
      }
      AppLogger.info('Created new session with ID: $sessionId');

      // Explicitly start the session on the backend
      AppLogger.info('Attempting to start session with ruck ID: $sessionId');
      await _apiClient.post('/rucks/$sessionId/start', {});
      AppLogger.info('Backend notified of session start for ruck ID: $sessionId');

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
        plannedDuration: event.plannedDuration, // This is in seconds already from event
        originalSessionStartTimeUtc: DateTime.now().toUtc(),
        totalPausedDuration: Duration.zero,
        currentPauseStartTimeUtc: null,
      );
      emit(initialSessionState);
      AppLogger.info('ActiveSessionRunning state emitted for session $sessionId with plannedDuration: \u001B[33m${initialSessionState.plannedDuration}\u001B[0m seconds');

      _startLocationTracking(emit); 
      _startHeartRateMonitoring();
      AppLogger.info('Location, heart rate started for session $sessionId');
    } catch (e, stackTrace) {
      final String RuckIdForError = sessionId ?? "unknown";
      AppLogger.error('Failed to start session $RuckIdForError: $e. StackTrace: $stackTrace');
      emit(ActiveSessionFailure(
        errorMessage: ErrorHandler.getUserFriendlyMessage(e, 'Session Start'),
      ));
    }
  }

  void _startLocationTracking(Emitter<ActiveSessionState> emit) {
    try {
      _locationSubscription?.cancel();
      _heartRateSubscription?.cancel();

      final locationStream = _locationService.startLocationTracking();
      _locationSubscription = locationStream.listen(
        (locationPoint) {
          add(LocationUpdated(locationPoint));
        },
        onError: (error) {
          AppLogger.error('Location error during active session: $error');
          // Removed: add(SessionFailed(...)) to avoid abrupt session termination for all location errors.
          // Permission errors should be caught before starting the session.
          // Other mid-session errors will be logged for now.
        },
      );

      _heartRateSubscription = _healthService.heartRateStream.listen(
        (sample) => add(HeartRateUpdated(sample)),
        onError: (e) => AppLogger.error('Heart rate stream error: $e'),
      );
    } catch (e) {
      AppLogger.error('Failed to start location tracking: $e');
      
      // Don't change state if we're not in Running state - just log the error
      if (state is ActiveSessionRunning) {
        emit(ActiveSessionFailure(
          errorMessage: ErrorHandler.getUserFriendlyMessage(
            e, 
            'Location Tracking'
          ),
        ));
      }
    }
  }

  void _startHeartRateMonitoring() {
    AppLogger.info('Starting heart rate monitoring...');
    _heartRateSubscription?.cancel(); // Cancel previous subscription if any
    _heartRateSubscription = _healthService.heartRateStream.listen(
      (HeartRateSample sample) {
        AppLogger.info('Heart rate sample received: ${sample.bpm} BPM at ${sample.timestamp}');
        add(HeartRateUpdated(sample));
      },
      onError: (error) {
        AppLogger.error('Error in heart rate stream: $error');
        // Optionally, dispatch an error event to the BLoC state
      },
      onDone: () {
        AppLogger.info('Heart rate stream closed.');
      },
    );
  }

  void _stopHeartRateMonitoring() {
    AppLogger.info('Stopping heart rate monitoring...');
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => add(Tick()));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
            c(lat1 * p) * c(lat2 * p) * 
            (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000; // 2 * R; R = 6371 km, returns meters
  }
  
  // Get user weight from current user state
  double _getUserWeightKg() {
    try {
      // Try to get from auth bloc state, which should have the User
      final authBloc = GetIt.instance<AuthBloc>();
      if (authBloc.state is Authenticated) {
        final User user = (authBloc.state as Authenticated).user;
        if (user.weightKg != null && user.weightKg! > 0) {
          return user.weightKg!;
        }
      }
    } catch (e) {
      AppLogger.info('Could not get user weight from profile: $e');
    }
    
    return 70.0; // Default to ~154 lbs
  }

  Future<void> _onLocationUpdated(
    LocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    final currentPoint = event.locationPoint;
    const double thresholdMeters = 10.0; 
    const double driftIgnoreJumpMeters = 15.0; 

    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (_lastValidLocation != null) {
        final last = _lastValidLocation!;
        final double distance = _calculateDistance(last.latitude, last.longitude, currentPoint.latitude, currentPoint.longitude);

        if (currentState.distanceKm * 1000 < 10 && distance > driftIgnoreJumpMeters) {
          debugPrint("Ignoring GPS update due to drift: distance = " + distance.toString());
          return;
        }

        if (distance < thresholdMeters) {
          AppLogger.info('Ignoring minimal location update; distance ' + distance.toString() + ' m is below threshold.');
          return;
        }

        _validLocationCount++;
      } else {
        _validLocationCount = 1;
      }
    }

    _lastValidLocation = currentPoint;

    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      
      AppLogger.info('LocationUpdated event: ${event.locationPoint}');

      final previousPoint = currentState.locationPoints.isNotEmpty ? currentState.locationPoints.last : null;
      final validationResult = _validationService.validateLocationPoint(event.locationPoint, previousPoint);
      if (!validationResult['isValid']) {
        AppLogger.warning('Invalid location point: ${validationResult['reason']}');
        return;
      }

      List<LocationPoint> updatedPoints = List.from(currentState.locationPoints)..add(event.locationPoint);

      double newDistance = currentState.distanceKm;
      if (updatedPoints.length > 1) {
        final prevPoint = updatedPoints[updatedPoints.length - 2];
        newDistance += _locationService.calculateDistance(prevPoint, event.locationPoint);
      }

      double newElevationGain = currentState.elevationGain;
      double newElevationLoss = currentState.elevationLoss;
      if (updatedPoints.length > 1) {
        final prevPoint = updatedPoints[updatedPoints.length - 2];
        final diff = event.locationPoint.elevation - prevPoint.elevation;
        if (diff > 0) newElevationGain += diff;
        if (diff < 0) newElevationLoss += diff.abs();
      }

      final double newPace = newDistance > 0
          ? (currentState.elapsedSeconds / newDistance)
          : 0;
        
      int newCalories = currentState.calories;
      
      if (updatedPoints.length > 1) {
        final prevPoint = updatedPoints[updatedPoints.length - 2];
        final currentPoint = event.locationPoint;
        
        final double segmentDistanceMeters = _locationService.calculateDistance(prevPoint, currentPoint) * 1000;
        
        final double elevationChange = currentPoint.elevation - prevPoint.elevation;
        
        double segmentSpeedKmh = 0.0;
        if (segmentDistanceMeters > 0) {
          final segmentSeconds = currentPoint.timestamp.difference(prevPoint.timestamp).inSeconds;
          if (segmentSeconds > 0) {
            final segmentPaceSecPerKm = segmentSeconds / (segmentDistanceMeters / 1000);
            segmentSpeedKmh = 3600 / segmentPaceSecPerKm;
          }
        }
        
        final double speedMph = MetCalculator.kmhToMph(segmentSpeedKmh);
        
        final double ruckWeightKg = currentState.ruckWeightKg;
        final double ruckWeightLbs = ruckWeightKg * 2.20462; // kg to lbs
        
        final double grade = MetCalculator.calculateGrade(
          elevationChangeMeters: elevationChange,
          distanceMeters: segmentDistanceMeters,
        );
        
        final double metValue = MetCalculator.calculateRuckingMetByGrade(
          speedMph: speedMph,
          grade: grade,
          ruckWeightLbs: ruckWeightLbs,
        );
        
        final double segmentTimeMinutes = currentPoint.timestamp.difference(prevPoint.timestamp).inSeconds / 60.0;
        
        final userWeight = _getUserWeightKg();
        
        final double segmentCalories = MetCalculator.calculateCaloriesBurned(
          weightKg: userWeight + (ruckWeightKg * 0.75), // Count 75% of ruck weight
          durationMinutes: segmentTimeMinutes,
          metValue: metValue,
        );
        
        newCalories += segmentCalories.round();
      }
    
      emit(currentState.copyWith(
        locationPoints: updatedPoints,
        distanceKm: newDistance,
        pace: newPace,
        calories: newCalories,
        elevationGain: newElevationGain.toDouble(),
        elevationLoss: newElevationLoss.toDouble(),
      ));

      try {
        await _apiClient.post('/rucks/${currentState.sessionId}/location', {
          'latitude': event.locationPoint.latitude,
          'longitude': event.locationPoint.longitude,
          'elevation': event.locationPoint.elevation,
          'timestamp': event.locationPoint.timestamp.toIso8601String(),
        });
      } catch (e) {
        // Only log the error, don't disrupt the session for location updates
        AppLogger.error('Failed to send location to backend: $e');
      }
      
      // Handle auto-pause / auto-end based on validation flags
      if (validationResult != null) {
        if (validationResult['shouldPause'] == true && !currentState.isPaused) {
          add(SessionPaused());
        }
        if (validationResult['shouldEnd'] == true) {
          add(const SessionCompleted());
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
      if (currentState.sessionId.isEmpty) {
        AppLogger.error('Invalid session ID for pausing session.');
        emit(ActiveSessionFailure(errorMessage: 'Session ID is missing. Please try again.'));
        return;
      }
      
      AppLogger.info('Pausing session ${currentState.sessionId}');
      
      // Stop the timer when pausing
      _stopTicker();
      
      // Tell watch to pause
      _watchService.pauseSessionOnWatch();
      
      // Update backend about pause
      try {
        await _apiClient.post('/rucks/${currentState.sessionId}/pause', {});
      } catch (e) {
        AppLogger.error('Failed to pause session in backend: $e');
        // Continue with local pause even if backend update fails
      }
      
      // Emit paused state
      emit(currentState.copyWith(
        isPaused: true,
        currentPauseStartTimeUtc: DateTime.now().toUtc(), // Record when pause started
      ));
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      Duration newTotalPausedDuration = currentState.totalPausedDuration;

      if (currentState.currentPauseStartTimeUtc != null) {
        final pauseEndedUtc = DateTime.now().toUtc();
        final currentPauseLength = pauseEndedUtc.difference(currentState.currentPauseStartTimeUtc!);
        newTotalPausedDuration += currentPauseLength;
      } // else: was not properly in a timed pause state, resume without adding to pause duration
      
      AppLogger.info('Resuming session ${currentState.sessionId}');
      
      // Restart the timer when resuming
      _startTicker();
      
      // Tell watch to resume
      _watchService.resumeSessionOnWatch();
      
      // Update backend about resume
      try {
        await _apiClient.post('/rucks/${currentState.sessionId}/resume', {});
      } catch (e) {
        AppLogger.error('Failed to resume session in backend: $e');
        // Continue with local resume even if backend update fails
      }
      
      // Emit resumed state
      emit(currentState.copyWith(
        isPaused: false,
        totalPausedDuration: newTotalPausedDuration, // Update total paused duration
        clearCurrentPauseStartTimeUtc: true, // Clear the specific pause start time
      ));
    }
  }

  Future<void> _onSessionCompleted(
    SessionCompleted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (currentState.sessionId.isEmpty) {
        AppLogger.error('Invalid session ID for completing session.');
        emit(ActiveSessionFailure(errorMessage: 'Session ID is missing. Please try again.'));
        return;
      }
      
      try {
        AppLogger.info('Completing session ${currentState.sessionId}');
        
        // Validate session before saving
        final validationSave = _validationService.validateSessionForSave(
          distanceMeters: currentState.distanceKm * 1000,
          duration: Duration(seconds: currentState.elapsedSeconds),
          caloriesBurned: currentState.calories.toDouble(),
        );
        if (validationSave['isValid'] == false) {
          emit(ActiveSessionFailure(errorMessage: validationSave['message'] ?? 'Session invalid.'));
          return;
        }
        
        // Tell watch to end
        _watchService.endSessionOnWatch();
        
        // Update backend about session completion
        await _apiClient.post(
          '/rucks/${currentState.sessionId}/complete',
          {
            'distance_km': double.parse(currentState.distanceKm.toStringAsFixed(3)),
            'duration_seconds': currentState.elapsedSeconds,
            'calories_burned': currentState.calories.round(),
            'elevation_gain_m': currentState.elevationGain.round(),
            'elevation_loss_m': currentState.elevationLoss.round(),
            'ruck_weight_kg': currentState.ruckWeightKg.roundToDouble(),
          },
        );
        
        // Cancel location subscription
        await _locationSubscription?.cancel();
        _locationSubscription = null;
        await _heartRateSubscription?.cancel();
        _heartRateSubscription = null;
        _stopTicker();
        
        // Save workout to HealthKit
        try {
          final startTime = DateTime.now().subtract(Duration(seconds: currentState.elapsedSeconds));
          final endTime = DateTime.now();
          await _healthService.saveWorkout(
            startDate: startTime,
            endDate: endTime,
            distanceKm: currentState.distanceKm,
            caloriesBurned: currentState.calories,
            ruckWeightKg: currentState.ruckWeightKg,
            elevationGainMeters: currentState.elevationGain,
            elevationLossMeters: currentState.elevationLoss,
          );
        } catch (e) {
          AppLogger.error('Failed to save workout to HealthKit: $e');
        }
        
        // Emit completion state
        emit(ActiveSessionComplete(
          session: RuckSession(
            id: currentState.sessionId,
            startTime: DateTime.now().subtract(Duration(seconds: currentState.elapsedSeconds)),
            endTime: DateTime.now(),
            duration: Duration(seconds: currentState.elapsedSeconds),
            distance: currentState.distanceKm,
            elevationGain: currentState.elevationGain,
            elevationLoss: currentState.elevationLoss,
            caloriesBurned: currentState.calories.toInt(),
            averagePace: currentState.distanceKm > 0
                ? (currentState.elapsedSeconds / currentState.distanceKm)
                : 0.0,
            ruckWeightKg: currentState.ruckWeightKg,
            status: RuckStatus.completed,
            notes: null,
            rating: null,
          ),
        ));
      } catch (e) {
        AppLogger.error('Failed to complete session: $e');
        
        // Try fallback - complete locally even if backend fails
        await _locationSubscription?.cancel();
        _locationSubscription = null;
        await _heartRateSubscription?.cancel();
        _heartRateSubscription = null;
        _stopTicker();
        
        // Check if the error is a network issue
        final errorMessage = e is ApiException && e.statusCode == 503
            ? 'Could not save to server - check your internet connection. Your session data is saved locally.'
            : ErrorHandler.getUserFriendlyMessage(e, 'Session Completion');
        
        emit(ActiveSessionFailure(
          errorMessage: errorMessage,
        ));
      }
    }
  }

  void _onSessionFailed(
    SessionFailed event, 
    Emitter<ActiveSessionState> emit
  ) {
    AppLogger.error('Session failed: ${event.errorMessage}');
    
    // Cancel location subscription
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
    _stopTicker();
    
    // Emit failure state
    emit(ActiveSessionFailure(
      errorMessage: event.errorMessage,
    ));
  }

  List<HeartRateSample> _hrBuffer = [];
  DateTime? _lastHrFlush;

  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    _latestHeartRate = event.sample.bpm;
    final currentState = state;
    if (currentState is ActiveSessionRunning) {
      AppLogger.info('HeartRateUpdated event: ${event.sample.bpm} BPM at ${event.sample.timestamp}');
      _hrBuffer.add(event.sample);
      emit(currentState.copyWith(latestHeartRate: _latestHeartRate));
      if (_hrBuffer.length > 10) {
        await _flushHeartRateBuffer(currentState);
      }
    } else {
      AppLogger.warning('HeartRateUpdated event received but session is not running. Current state: $currentState');
    }
  }

  Future<void> _flushHeartRateBuffer(ActiveSessionRunning currentState) async {
    if (_hrBuffer.isEmpty || currentState.sessionId.isEmpty) return;
    try {
      await _apiClient.post(
        '/rucks/${currentState.sessionId}/heart_rate',
        {
          'samples': _hrBuffer.map((s) => {
            'timestamp': s.timestamp.toIso8601String(),
            'bpm': s.bpm,
          }).toList(),
        },
      );
      _hrBuffer.clear();
      _lastHrFlush = DateTime.now();
    } catch (e) {
      AppLogger.error('Failed to send heart rate samples: $e');
    }
  }

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
  // Heart rate batching: flush every 5 seconds if buffer not empty
  if (state is ActiveSessionRunning) {
    final currentState = state as ActiveSessionRunning;
    if (_hrBuffer.isNotEmpty && (_lastHrFlush == null || DateTime.now().difference(_lastHrFlush!) > Duration(seconds: 5))) {
      await _flushHeartRateBuffer(currentState);
    }
  }
  if (state is ActiveSessionRunning) {
    final currentState = state as ActiveSessionRunning;
    final double currentDistance = currentState.distanceKm; // in km
    double? newPace;

    // Only show pace/distance if at least 3 valid points
    if (_validLocationCount < 3 || currentDistance < 0.02) {
      newPace = null;
    } else {
      // Calculate pace in seconds per km
      newPace = currentState.elapsedSeconds / currentDistance;
      // Filter out absurd pace values (e.g. < 5 min/km or > 20 min/km)
      // 5 min/km = 300 sec/km, 20 min/km = 1200 sec/km
      if (newPace < 300 || newPace > 1200) {
        newPace = null;
      }
    }

    final nowUtc = DateTime.now().toUtc();
    final grossDuration = nowUtc.difference(currentState.originalSessionStartTimeUtc);
    final netDuration = grossDuration - currentState.totalPausedDuration;
    int newElapsed = netDuration.inSeconds;

    // Sanity check to ensure elapsed time doesn't go negative
    if (newElapsed < 0) newElapsed = 0;

    final newCalories = 0; // Removed calorie calculation

    emit(currentState.copyWith(
      elapsedSeconds: newElapsed,
      pace: newPace,
      calories: newCalories,
    ));
  }
}

  Future<void> _onTimerStarted(
    TimerStarted event,
    Emitter<ActiveSessionState> emit,
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      // Update the session start time so that elapsed time resets to 0
      final updatedState = currentState.copyWith(originalSessionStartTimeUtc: DateTime.now());
      emit(updatedState);
      _startTicker();
      AppLogger.info('Timer started at: ${DateTime.now()}');
    }
  }

  void _onSessionErrorCleared(SessionErrorCleared event, Emitter<ActiveSessionState> emit) {
    emit(ActiveSessionInitial());
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _heartRateSubscription?.cancel();
    _ticker?.cancel();
    return super.close();
  }
}