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
    try {
      // Start a new session
      emit(ActiveSessionLoading());
      
      AppLogger.info('Starting a new ruck session with weight: ${event.ruckWeightKg}kg');
      
      // Create a new session in the backend
      final response = await _apiClient.post('/rucks', {
        'ruck_weight_kg': event.ruckWeightKg,
        'notes': event.notes,
      });
      
      // Extract session ID from response
      final String sessionId = response['id'].toString();
      AppLogger.info('Created new session with ID: $sessionId');
      
      // Start location tracking
      _startLocationTracking(emit);
      _startTicker();
      
      // Emit success state with session ID
      emit(ActiveSessionRunning(
        sessionId: sessionId,
        locationPoints: [],
        elapsedSeconds: 0,
        distanceKm: 0.0,
        ruckWeightKg: event.ruckWeightKg,
        notes: event.notes,
        calories: 0,
        elevationGain: 0,
        elevationLoss: 0,
        isPaused: false,
        pace: 0,
      ));
    } catch (e) {
      AppLogger.error('Failed to start session: $e');
      
      // Emit failure state with user-friendly error message
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
          AppLogger.error('Location error: $error');
          
          // Only send location errors that are critical to the session
          if (state is ActiveSessionRunning) {
            add(SessionFailed(
              errorMessage: ErrorHandler.getUserFriendlyMessage(
                error, 
                'Location Tracking'
              ),
            ));
          }
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
      final List<LocationPoint> updatedPoints = List.from(currentState.locationPoints)
        ..add(event.locationPoint);
      
      // Calculate new distance
      double newDistance = currentState.distanceKm;
      Map<String, dynamic>? validationResult; // capture validation info
      if (updatedPoints.length > 1) {
        final previousPoint = updatedPoints[updatedPoints.length - 2];
        final newPoint = event.locationPoint;
        
        try {
          // Calculate distance between last two points (in km)
          final segmentDistanceKm = _locationService.calculateDistance(previousPoint, newPoint);
          final segmentDistanceMeters = segmentDistanceKm * 1000;

          // Validate the new segment & track session behaviour
          validationResult = _validationService.validateLocationPoint(
            newPoint,
            previousPoint,
            distanceMeters: segmentDistanceMeters,
          );

          if (validationResult['isValid'] == true) {
            newDistance += segmentDistanceKm;
          } else {
            AppLogger.warning('Filtered out segment: ${validationResult['message'] ?? 'Unknown reason'}');
          }
        } catch (e) {
          AppLogger.error('Error calculating distance: $e');
          // Don't update distance on error, keep previous value
        }
      }
      
      // Calculate elevation changes
      double elevationGain = currentState.elevationGain;
      double elevationLoss = currentState.elevationLoss;

      if (updatedPoints.length > 1) {
        final previousPoint = updatedPoints[updatedPoints.length - 2];
        final newPoint = event.locationPoint;
        final elevationResult = _validationService.validateElevationChange(previousPoint, newPoint);
        elevationGain += elevationResult['gain'] ?? 0.0;
        elevationLoss += elevationResult['loss'] ?? 0.0;
      }
      
      // Derive pace (minutes per km). If distance is zero, pace is 0 to avoid NaN/inf
      final int newElapsedSeconds = currentState.elapsedSeconds + 1;
      final double newPace = newDistance > 0
          ? (newElapsedSeconds / 60) / newDistance // minutes per km
          : 0;
      
      // Update the state with new location data
      emit(ActiveSessionRunning(
        sessionId: currentState.sessionId,
        locationPoints: updatedPoints,
        elapsedSeconds: newElapsedSeconds, // Increment elapsed time
        distanceKm: newDistance,
        ruckWeightKg: currentState.ruckWeightKg,
        notes: currentState.notes,
        calories: _calculateCalories(
          newDistance, 
          currentState.ruckWeightKg
        ).toDouble(),
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        isPaused: currentState.isPaused,
        pace: newPace,
        validationMessage: (validationResult != null && validationResult['isValid'] == false)
          ? validationResult['message'] as String?
          : null,
      ));
      
      // Update backend with new location point
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
      emit(currentState.copyWith(isPaused: true));
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      
      AppLogger.info('Resuming session ${currentState.sessionId}');
      
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
      emit(currentState.copyWith(isPaused: false));
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
          caloriesBurned: currentState.calories,
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
            caloriesBurned: currentState.calories.round(),
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
    Emitter<ActiveSessionState> emit,
  ) async {
    if (state is ActiveSessionRunning) {
      final current = state as ActiveSessionRunning;
      try {
        await _apiClient.addHeartRateSamples(
          current.sessionId,
          [
            {
              'timestamp': event.sample.timestamp.toIso8601String(),
              'bpm': event.sample.bpm,
            }
          ],
        );
        emit(current.copyWith(latestHeartRate: event.sample.bpm));
      } catch (e) {
        AppLogger.error('Failed to send heart rate sample: $e');
      }
    }
  }

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    if (state is! ActiveSessionRunning) return;
    final current = state as ActiveSessionRunning;
    if (current.isPaused) return;

    final newElapsed = current.elapsedSeconds + 1;
    final newPace = current.distanceKm > 0
        ? (newElapsed / 60) / current.distanceKm
        : 0.0;
    final newCalories = _calculateCalories(current.distanceKm, current.ruckWeightKg);

    emit(current.copyWith(
      elapsedSeconds: newElapsed,
      pace: newPace,
      calories: newCalories.toDouble(),
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