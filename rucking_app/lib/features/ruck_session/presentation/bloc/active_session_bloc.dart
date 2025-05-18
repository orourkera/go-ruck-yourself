import 'dart:math' as math;
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
  int _paceTickCounter = 0;
  final ApiClient _apiClient;
  final LocationService _locationService;
  final HealthService _healthService;
  final WatchService _watchService;
  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  Timer? _ticker;
  Timer? _watchdogTimer;
  DateTime _lastTickTime = DateTime.now();
  // Reuse one validation service instance to keep state between points
  final SessionValidationService _validationService = SessionValidationService();
  LocationPoint? _lastValidLocation;
  int _validLocationCount = 0;
  int _latestHeartRate = 0;
  // Local dumb timer counters
  int _elapsedCounter = 0; // seconds since session start minus pauses
  int _ticksSinceTruth = 0;
  // Watchdog: track time of last valid location to auto-restart GPS if stalled
  DateTime _lastLocationTimestamp = DateTime.now();

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
        isGpsReady: false,
      );
      emit(initialSessionState);
      AppLogger.info('ActiveSessionRunning state emitted for session $sessionId with plannedDuration: \u001B[33m${initialSessionState.plannedDuration}\u001B[0m seconds');

      // Before starting location tracking, reset the validator state
      _validationService.reset();

      // Start location tracking and heart rate monitoring
      _startLocationTracking(emit);
      _elapsedCounter = 0;
      _ticksSinceTruth = 0;
      await _startHeartRateMonitoring();
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
          // Instead of giving up, attempt a graceful retry after a short delay.
          if (state is ActiveSessionRunning) {
            // Cancel the faulty subscription first.
            _locationSubscription?.cancel();
            _locationSubscription = null;
            // Schedule a retry only if we are still in a running session after 5 seconds.
            Future.delayed(const Duration(seconds: 5), () {
              if (state is ActiveSessionRunning) {
                AppLogger.info('Retrying location tracking after error...');
                _startLocationTracking(emit);
              }
            });
          }
          // Note: do **not** emit a SessionFailed here to avoid aborting the session.
        },
      );

      // Heart-rate subscription handled in _startHeartRateMonitoring to avoid duplicates
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

  Future<void> _startHeartRateMonitoring() async {
    AppLogger.info('Starting heart rate monitoring...');
    
    // Ensure HealthKit permissions are granted once per app session
    if (!_healthService.isAuthorized) {
      final granted = await _healthService.requestAuthorization();
      if (!granted) {
        AppLogger.warning('Health authorization denied – heart-rate stream disabled');
        return; // Do not start subscription without permission
      }
    }
    
    _heartRateSubscription?.cancel(); // Cancel previous subscription if any
    _heartRateSubscription = _healthService.heartRateStream.listen(
      (HeartRateSample sample) {
        AppLogger.info('Heart rate sample received: ${sample.bpm} BPM at ${sample.timestamp}');
        add(HeartRateUpdated(sample));
      },
      onError: (error) {
        AppLogger.error('Error in heart rate stream: $error');
      },
      onDone: () {
        AppLogger.info('Heart rate stream closed.');
      },
    );

    // Seed with immediate reading in case stream takes a few seconds
    try {
      final initialHr = await _healthService.getHeartRate();
      if (initialHr != null && initialHr > 0) {
        AppLogger.info('Initial heart rate fetched: $initialHr BPM');
        add(HeartRateUpdated(HeartRateSample(
          timestamp: DateTime.now(),
          bpm: initialHr.round(),
        )));
      } else {
        AppLogger.info('Initial heart rate not available');
      }
    } catch (e) {
      AppLogger.error('Error fetching initial heart rate: $e');
    }
  }

  void _stopHeartRateMonitoring() {
    AppLogger.info('Stopping heart rate monitoring...');
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _watchdogTimer?.cancel();
    
    // Record the start time for this ticker
    _lastTickTime = DateTime.now();
    
    // Main timer that fires every second normally
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      add(Tick());
    });
    
    // Watchdog timer that checks for missed ticks every 5 seconds
    // This helps recover from background/lock screen situations
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastTickTime).inSeconds;
      
      // If we've missed more than 2 seconds, catch up by adding the missed ticks
      if (elapsed > 2) {
        AppLogger.info('Watchdog caught $elapsed seconds of missed ticks, catching up');
        for (int i = 0; i < elapsed; i++) {
          add(Tick());
        }
        _lastTickTime = now;
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    double dLat = (lat2 - lat1) * (math.pi / 180);
    double dLon = (lon2 - lon1) * (math.pi / 180);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
               math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
               math.sin(dLon / 2) * math.sin(dLon / 2);
    double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c / 1000; // Convert to km
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
        // DEDUPLICATION: Ignore if lat/lng and timestamp match last valid location
        if (last.latitude == currentPoint.latitude &&
            last.longitude == currentPoint.longitude &&
            last.timestamp == currentPoint.timestamp) {
          AppLogger.info('Ignoring duplicate location point.');
          return;
        }
        // Calculate segment distance in metres for comparison against metre thresholds.
        final double distanceMeters = _calculateDistance(
              last.latitude,
              last.longitude,
              currentPoint.latitude,
              currentPoint.longitude,
            ) * 1000; // _calculateDistance returns kilometres

        // Ignore large GPS jumps when total travelled distance is still tiny (<10 m)
        if (currentState.distanceKm * 1000 < 10 && distanceMeters > driftIgnoreJumpMeters) {
          debugPrint("Ignoring GPS update due to drift: distance = " + distanceMeters.toString());
          return;
        }

        // Ignore negligible movements below the noise threshold
        if (distanceMeters < thresholdMeters) {
          AppLogger.info('Ignoring minimal location update; distance ' + distanceMeters.toString() + ' m is below threshold.');
          return;
        }

        _validLocationCount++;
      } else {
        _validLocationCount = 1;
      }
    }

    _lastValidLocation = currentPoint;
    _lastLocationTimestamp = DateTime.now();

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

      // Removed inline pace calculation here; pace updates every 15 seconds in _onTick.
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
    
      Map<String, dynamic> updates = {};
      updates['locationPoints'] = updatedPoints;
      updates['distanceKm'] = newDistance;
      updates['calories'] = newCalories;
      updates['elevationGain'] = newElevationGain.toDouble();
      updates['elevationLoss'] = newElevationLoss.toDouble();
      updates['validationMessage'] = validationResult['reason'];
      updates['clearValidationMessage'] = validationResult['shouldClearMessage'];

      // Set isGpsReady to true if it's not already true
      // Determine if isGpsReady needs to be updated
      bool newIsGpsReady = currentState.isGpsReady;
      if (!currentState.isGpsReady) {
        newIsGpsReady = true; // Set to true as we have a valid point
        AppLogger.info('GPS is now ready. First valid location point received and processed.');
      }
      
      emit(currentState.copyWith(
        locationPoints: updates['locationPoints'],
        distanceKm: updates['distanceKm'],
        calories: updates['calories'],
        elevationGain: updates['elevationGain'],
        elevationLoss: updates['elevationLoss'],
        validationMessage: updates['validationMessage'],
        clearValidationMessage: updates['clearValidationMessage'],
        isGpsReady: newIsGpsReady, // Pass the determined value
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
      
      // Re-sync elapsed counter on resume
      _elapsedCounter = DateTime.now().toUtc().difference(currentState.originalSessionStartTimeUtc).inSeconds - newTotalPausedDuration.inSeconds;
      _ticksSinceTruth = 0;
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
        AppLogger.info('Session start time (before computation): ${currentState.originalSessionStartTimeUtc}');
        AppLogger.info('Total paused duration (before computation): ${currentState.totalPausedDuration}');
        
        AppLogger.info('Completing session ${currentState.sessionId}');
        
        Duration actualDuration;
        try {
          final DateTime sessionStart = currentState.originalSessionStartTimeUtc;
          // Defensive: this should never be null. If it is, something is critically wrong.
          assert(sessionStart != null, 'originalSessionStartTimeUtc should never be null!');
          final Duration pausedDuration = currentState.totalPausedDuration;
          // Defensive: this should never be null. If it is, something is critically wrong.
          assert(pausedDuration != null, 'totalPausedDuration should never be null!');
          actualDuration = DateTime.now().difference(sessionStart) - pausedDuration;
        } catch (e) {
          AppLogger.error('Error computing actualDuration in _onSessionCompleted: $e');
          actualDuration = Duration.zero;
        }

        // Ensure duration is at least 0 seconds
        final int finalElapsedSeconds = actualDuration.inSeconds < 0
            ? 0
            : actualDuration.inSeconds;

        // Tell watch to end
        _watchService.endSessionOnWatch();
        
        // Update backend about session completion
        // DEBUG: Log all outgoing values for session completion
        AppLogger.info('[SESSION COMPLETE PAYLOAD]');
        AppLogger.info('  distance_km: [36m${double.parse(currentState.distanceKm.toStringAsFixed(3))}[0m');
        AppLogger.info('  duration_seconds: ${finalElapsedSeconds}');
        AppLogger.info('  calories_burned: ${currentState.calories.round()}');
        AppLogger.info('  elevation_gain_m: ${currentState.elevationGain.round()}');
        AppLogger.info('  elevation_loss_m: ${currentState.elevationLoss.round()}');
        AppLogger.info('  ruck_weight_kg: ${currentState.ruckWeightKg.roundToDouble()}');
        AppLogger.info('  notes: ${event.notes}');
        AppLogger.info('  rating: ${event.rating}');
        AppLogger.info('  tags: ${event.tags}');
        AppLogger.info('  perceived_exertion: ${event.perceivedExertion}');
        AppLogger.info('  weight_kg: ${event.weightKg ?? currentState.weightKg}');
        AppLogger.info('  planned_duration_minutes: ${event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null)}');
        AppLogger.info('  paused_duration_seconds: ${event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds}');
        
        // DEBUG: Log all values used to construct the RuckSession emitted in ActiveSessionComplete
        AppLogger.info('[ACTIVE SESSION COMPLETE]');
        AppLogger.info('  id: ${currentState.sessionId}');
        AppLogger.info('  startTime: [32m${DateTime.now().subtract(actualDuration)}[0m');
        AppLogger.info('  endTime: [32m${DateTime.now()}[0m');
        AppLogger.info('  duration: [32m$actualDuration[0m');
        AppLogger.info('  distance: ${currentState.distanceKm}');
        AppLogger.info('  elevationGain: ${currentState.elevationGain}');
        AppLogger.info('  elevationLoss: ${currentState.elevationLoss}');
        AppLogger.info('  caloriesBurned: ${currentState.calories}');
        AppLogger.info('  averagePace: ${currentState.distanceKm > 0 ? (currentState.elapsedSeconds / currentState.distanceKm) : 0.0}');
        AppLogger.info('  ruckWeightKg: ${currentState.ruckWeightKg}');
        AppLogger.info('  status: RuckStatus.completed');
        AppLogger.info('  notes: ${event.notes}');
        AppLogger.info('  rating: ${event.rating}');
        AppLogger.info('  tags: ${event.tags ?? currentState.tags}');
        AppLogger.info('  perceivedExertion: ${event.perceivedExertion ?? currentState.perceivedExertion}');
        AppLogger.info('  weightKg: ${event.weightKg ?? currentState.weightKg}');
        AppLogger.info('  plannedDurationMinutes: ${event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null)}');
        AppLogger.info('  pausedDurationSeconds: ${event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds}');
        
        await _apiClient.post(
          '/rucks/${currentState.sessionId}/complete',
          {
            'distance_km': double.parse(currentState.distanceKm.toStringAsFixed(3)),
            'duration_seconds': finalElapsedSeconds,
            'calories_burned': currentState.calories.round(),
            'elevation_gain_m': currentState.elevationGain.round(),
            'elevation_loss_m': currentState.elevationLoss.round(),
            'average_pace': currentState.distanceKm > 0
                ? (currentState.elapsedSeconds / currentState.distanceKm)
                : 0.0,
            'ruck_weight_kg': currentState.ruckWeightKg.roundToDouble(),
            'notes': event.notes,
            'rating': event.rating,
            'tags': event.tags,
            'perceived_exertion': event.perceivedExertion,
            'weight_kg': event.weightKg ?? currentState.weightKg,
            'planned_duration_minutes': event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null),
            'paused_duration_seconds': event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds,
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
          final startTime = DateTime.now().subtract(actualDuration);
          final endTime = DateTime.now();
          await _healthService.saveWorkout(
            startDate: startTime,
            endDate: endTime,
            distanceKm: currentState.distanceKm,
            caloriesBurned: currentState.calories,
            ruckWeightKg: currentState.ruckWeightKg,
            elevationGainMeters: currentState.elevationGain,
            elevationLossMeters: currentState.elevationLoss,          );
        } catch (e) {
          AppLogger.error('Failed to save workout to HealthKit: $e');
        }
        
        // Emit completion state
        AppLogger.info('[COMPLETE] Emitting ActiveSessionComplete with values:');
AppLogger.info('  id: ${currentState.sessionId}');
AppLogger.info('  startTime: [32m${DateTime.now().subtract(actualDuration)}[0m');
AppLogger.info('  endTime: [32m${DateTime.now()}[0m');
AppLogger.info('  duration: [32m$actualDuration[0m');
AppLogger.info('  distance: ${currentState.distanceKm}');
AppLogger.info('  elevationGain: ${currentState.elevationGain}');
AppLogger.info('  elevationLoss: ${currentState.elevationLoss}');
AppLogger.info('  caloriesBurned: ${currentState.calories}');
AppLogger.info('  averagePace: ${currentState.distanceKm > 0 ? (currentState.elapsedSeconds / currentState.distanceKm) : 0.0}');
AppLogger.info('  ruckWeightKg: ${currentState.ruckWeightKg}');

assert(currentState.sessionId != null, 'sessionId should never be null');
assert(actualDuration != null, 'actualDuration should never be null');
assert(currentState.distanceKm != null, 'distanceKm should never be null');
assert(currentState.elevationGain != null, 'elevationGain should never be null');
assert(currentState.elevationLoss != null, 'elevationLoss should never be null');
assert(currentState.calories != null, 'calories should never be null');
assert(currentState.ruckWeightKg != null, 'ruckWeightKg should never be null');

emit(ActiveSessionComplete(
  session: RuckSession(
    id: currentState.sessionId,
    startTime: DateTime.now().subtract(actualDuration),
    endTime: DateTime.now(),
    duration: actualDuration,
    distance: currentState.distanceKm,
    elevationGain: currentState.elevationGain,
    elevationLoss: currentState.elevationLoss,
    caloriesBurned: currentState.calories.toInt(),
    averagePace: currentState.distanceKm > 0
        ? (currentState.elapsedSeconds / currentState.distanceKm)
        : 0.0,
    ruckWeightKg: currentState.ruckWeightKg,
    status: RuckStatus.completed,
    notes: event.notes,
    rating: event.rating,
    tags: event.tags ?? currentState.tags,
    perceivedExertion: event.perceivedExertion ?? currentState.perceivedExertion,
    weightKg: event.weightKg ?? currentState.weightKg,
    plannedDurationMinutes: event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null),
    pausedDurationSeconds: event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds,
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
    // Update last tick time to track when ticks happen
    _lastTickTime = DateTime.now();
    _paceTickCounter++; // Increment local pace counter

    if (state is! ActiveSessionRunning) return;
    final currentState = state as ActiveSessionRunning;

    // Flush heart-rate buffer every 5 seconds
    if (_hrBuffer.isNotEmpty &&
        (_lastHrFlush == null ||
            DateTime.now().difference(_lastHrFlush!) > const Duration(seconds: 5))) {
      await _flushHeartRateBuffer(currentState);
    }

    _elapsedCounter++;
    _ticksSinceTruth++;

    int newElapsed = _elapsedCounter;

    // periodic truth-up every 5 minutes (300 ticks)
    if (_ticksSinceTruth >= 300) {
      final trueElapsed = DateTime.now()
              .toUtc()
              .difference(currentState.originalSessionStartTimeUtc)
              .inSeconds -
          currentState.totalPausedDuration.inSeconds;
      if ((trueElapsed - _elapsedCounter).abs() > 2) {
        _elapsedCounter = trueElapsed;
        newElapsed = trueElapsed;
        AppLogger.info('Elapsed counter synced to wall-clock (diff ${(trueElapsed - _elapsedCounter).abs()}s)');
      }
      _ticksSinceTruth = 0;
    }

    // Pace calculation
    double? newPace = currentState.pace;
    if (newElapsed % 15 == 0) {
      if (_validLocationCount < 10 || currentState.distanceKm < 0.1) {
        newPace = null;
      } else {
        final candidate = newElapsed / currentState.distanceKm;
        newPace = (candidate > 1200) ? null : candidate;
      }
    }

    // Calories
    final double calculatedCalories = MetCalculator.calculateRuckingCalories(
      userWeightKg: _getUserWeightKg(),
      ruckWeightKg: currentState.ruckWeightKg,
      distanceKm: currentState.distanceKm,
      elapsedSeconds: newElapsed,
      elevationGain: currentState.elevationGain,
      elevationLoss: currentState.elevationLoss,
    );
    
    // Never allow calories to decrease during a session
    // This prevents the drops when timer is trued up
    final int finalCalories = math.max(calculatedCalories.round(), currentState.calories);

    // Inactivity watchdog: if no GPS fix for >15s, restart location tracking
    if (DateTime.now().difference(_lastLocationTimestamp) > const Duration(seconds: 15)) {
      AppLogger.warning('No GPS fix for 15s – restarting location stream');
      _startLocationTracking(emit);
      _lastLocationTimestamp = DateTime.now();
    }

    emit(currentState.copyWith(
      elapsedSeconds: newElapsed,
      pace: newPace,
      calories: finalCalories,
    ));
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
    _watchdogTimer?.cancel();
    return super.close();
  }
}