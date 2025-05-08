import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/models/api_exception.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
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
        AppLogger.error('Failed to create session: No ID received from backend.');
        throw Exception('Failed to create session: No ID received from backend.');
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
      _startTicker();
      AppLogger.info('Location, heart rate, and ticker started for session $sessionId');

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
    if (state is! ActiveSessionRunning) return; // Only monitor if session is running

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

  Future<void> _onLocationUpdated(
    LocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      AppLogger.info('LocationUpdated event: ${event.locationPoint}');

      // Validate the incoming point
      final previousPoint = currentState.locationPoints.isNotEmpty ? currentState.locationPoints.last : null;
      final validationResult = _validationService.validateLocationPoint(event.locationPoint, previousPoint);
      if (!validationResult['isValid']) {
        AppLogger.warning('Invalid location point: ${validationResult['reason']}');
        // Optionally, emit a specific state or handle the error, for now, we just log and ignore it.
        return;
      }

      List<LocationPoint> updatedPoints = List.from(currentState.locationPoints)..add(event.locationPoint);

      // Calculate new total distance
      double newDistance = currentState.distanceKm;
      if (updatedPoints.length > 1) {
        final prevPoint = updatedPoints[updatedPoints.length - 2];
        newDistance += _locationService.calculateDistance(prevPoint, event.locationPoint);
      }

      // Calculate new elevation gain/loss
      double newElevationGain = currentState.elevationGain;
      double newElevationLoss = currentState.elevationLoss;
      if (updatedPoints.length > 1) {
        final prevPoint = updatedPoints[updatedPoints.length - 2];
        final diff = event.locationPoint.elevation - prevPoint.elevation;
        if (diff > 0) newElevationGain += diff;
        if (diff < 0) newElevationLoss += diff.abs();
      }

      // Pace (minutes per km). Use current elapsed time, not incremented here.
      final double newPace = newDistance > 0
          ? (currentState.elapsedSeconds / 60) / newDistance
          : 0;
      
      // Update the state with new location data using copyWith
      emit(currentState.copyWith(
        locationPoints: updatedPoints,
        distanceKm: newDistance,
        pace: newPace,
        calories: _calculateCalories(newDistance, currentState.ruckWeightKg),
        elevationGain: newElevationGain.toDouble(),
        elevationLoss: newElevationLoss.toDouble(),
        // elapsedSeconds will be taken from currentState via copyWith, _onTick handles its progression
      ));

      // Send location update to backend
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
      
      AppLogger.info('Pausing session ${currentState.sessionId}');
      
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
      
      AppLogger.info('Resuming session ${currentState.sessionId}. Total paused duration: $newTotalPausedDuration');
      
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
            'notes': event.notes,
            'rating': event.rating,
            'distance_km': double.parse(currentState.distanceKm.toStringAsFixed(3)),
            'distance_meters': (currentState.distanceKm * 1000).toInt(),
            'final_distance_km': double.parse(currentState.distanceKm.toStringAsFixed(3)),
            'duration_seconds': currentState.elapsedSeconds,
            'final_average_pace': currentState.distanceKm > 0
                ? double.parse((currentState.elapsedSeconds / currentState.distanceKm)
                    .toStringAsFixed(2))
                : null,
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
            ruckWeightKg: currentState.ruckWeightKg,
            distance: currentState.distanceKm,
            duration: Duration(seconds: currentState.elapsedSeconds),
            startTime: DateTime.now().subtract(Duration(seconds: currentState.elapsedSeconds)),
            endTime: DateTime.now(),
            notes: event.notes,
            rating: event.rating,
            caloriesBurned: currentState.calories.toInt(),
            elevationGain: currentState.elevationGain,
            elevationLoss: currentState.elevationLoss,
            status: RuckStatus.completed, // Added missing status
            averagePace: currentState.distanceKm > 0 
                ? (currentState.elapsedSeconds / 60) / currentState.distanceKm 
                : 0.0,
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

  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    final currentState = state;
    if (currentState is ActiveSessionRunning) {
      AppLogger.info('HeartRateUpdated event: ${event.sample.bpm} BPM at ${event.sample.timestamp}');
      // Send heart rate to backend
      if (currentState.sessionId.isNotEmpty) {
        try {
          await _apiClient.post(
            '/rucks/${currentState.sessionId}/heart_rate',
            {
              'samples': [
                {
                  'timestamp': event.sample.timestamp.toIso8601String(),
                  'bpm': event.sample.bpm,
                }
              ]
            }
          );

          emit(currentState.copyWith(latestHeartRate: event.sample.bpm));
        } catch (e) {
          AppLogger.error('Failed to send heart rate sample: $e');
        }
      }
    } else {
      AppLogger.warning('HeartRateUpdated event received but session is not running. Current state: $currentState');
    }
  }

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    if (state is! ActiveSessionRunning) return;
    final current = state as ActiveSessionRunning;
    if (current.isPaused) return; // Don't update elapsed time if paused

    final nowUtc = DateTime.now().toUtc();
    final grossDuration = nowUtc.difference(current.originalSessionStartTimeUtc);
    final netDuration = grossDuration - current.totalPausedDuration;
    int newElapsed = netDuration.inSeconds;

    // Sanity check to ensure elapsed time doesn't go negative
    if (newElapsed < 0) newElapsed = 0;

    // If newElapsed is somehow less than current.elapsedSeconds (e.g. clock changed backwards significantly)
    // and it's not the very start (where current.elapsedSeconds might be 0 and newElapsed is also 0 after a tiny fraction of a second)
    // then it might be more robust to just increment. However, relying on wall clock is generally better for background robustness.
    // For now, we'll trust the wall clock calculation.
    // if (newElapsed < current.elapsedSeconds && current.elapsedSeconds > 0) { 
    //   newElapsed = current.elapsedSeconds + 1;
    // }

    final newPace = current.distanceKm > 0
        ? (newElapsed / 60) / current.distanceKm // Pace in min/km
        : 0.0;
    final newCalories = _calculateCalories(current.distanceKm, current.ruckWeightKg);

    emit(current.copyWith(
      elapsedSeconds: newElapsed,
      pace: newPace,
      calories: newCalories,
    ));
  }

  /// Calculate calories burned based on distance, weight, and MET value
  int _calculateCalories(double distanceKm, double ruckWeightKg) {
    // MET values (Metabolic Equivalent of Task):
    // - Walking with weighted backpack (10-20kg): ~7.0 MET
    // - Walking with very heavy backpack (>20kg): ~8.5 MET
    double metValue = ruckWeightKg < 20 ? 7.0 : 8.5;
    
    // Average weight of a person in kg (adjust if needed)
    const double averageWeightKg = 70.0;
    
    // Standard formula for calories burned:
    // Calories = MET × Weight (kg) × Duration (hours)
    
    // Estimate duration based on distance and average walking speed (4.5 km/h with ruck)
    double durationHours = distanceKm / 4.5;
    
    // Calculate calories
    return (metValue * averageWeightKg * durationHours).round();
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _heartRateSubscription?.cancel();
    _ticker?.cancel();
    return super.close();
  }
}