import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
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

class ActiveSessionBloc extends Bloc<ActiveSessionEvent, ActiveSessionState> {
  int _paceTickCounter = 0;
  final ApiClient _apiClient;
  final LocationService _locationService;
  final HealthService _healthService;
  final WatchService _watchService;
  final HeartRateService _heartRateService;
  final SessionValidationService _validationService;
  final SessionRepository _sessionRepository;
  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  StreamSubscription<List<HeartRateSample>>? _heartRateBufferSubscription;
  Timer? _ticker;
  Timer? _watchdogTimer;
  DateTime _lastTickTime = DateTime.now();
  LocationPoint? _lastValidLocation;
  int _validLocationCount = 0;
  // Local dumb timer counters
  int _elapsedCounter = 0; // seconds since session start minus pauses
  int _ticksSinceTruth = 0;
  // Watchdog: track time of last valid location to auto-restart GPS if stalled
  DateTime _lastLocationTimestamp = DateTime.now();
  
  // Service for tracking distance milestones/splits
  final SplitTrackingService _splitTrackingService;
  
  // Flag to track if heart rate monitoring has been started
  bool _isHeartRateMonitoringStarted = false;

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
    // Ensure the current instance is globally available for cross-layer callbacks (e.g. WatchService).
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
    on<TakePhotoRequested>(_onTakePhotoRequested);
    on<PickPhotoRequested>(_onPickPhotoRequested);
    on<LoadSessionForViewing>(_onLoadSessionForViewing);
  }

  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Reset split tracking for new session
    _splitTrackingService.reset();
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
      await _apiClient.post('/rucks/start', {'ruck_id': sessionId});
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
        heartRateSamples: [], // Initialize heartRateSamples
        isGpsReady: false,
      );
      emit(initialSessionState);
      AppLogger.info('ActiveSessionRunning state emitted for session $sessionId with plannedDuration: \u001B[33m${initialSessionState.plannedDuration}\u001B[0m seconds');
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: About to call _watchService.startSessionOnWatch. Current BLoC state: ${state.runtimeType}');

      // Initialize the watch workout
      AppLogger.info('Initializing watch workout for session $sessionId');
      final userPrefs = await GetIt.instance<SharedPreferences>();
      final bool preferMetric = userPrefs.getBool('use_metric') ?? false;
      
      // First start the session with ruck weight
      await _watchService.startSessionOnWatch(event.ruckWeightKg);
      
      // Then send the session ID to the watch
      await _watchService.sendSessionIdToWatch(sessionId!);
      
      AppLogger.info('Watch workout initialized successfully');

      // Before starting location tracking, reset the validator state
      _validationService.reset();

      // Start location tracking and heart rate monitoring
      _startLocationTracking(emit);
      _elapsedCounter = 0;
      _ticksSinceTruth = 0;
      if (!_isHeartRateMonitoringStarted) {
        await _startHeartRateMonitoring();
        _isHeartRateMonitoringStarted = true;
      }
      AppLogger.info('Location, heart rate started for session $sessionId');
      // Verify heart rate subscription status
      if (_heartRateSubscription == null) {
        AppLogger.warning('Heart rate subscription was null after session start!');
        if (!_isHeartRateMonitoringStarted) {
          await _startHeartRateMonitoring();
        } else {
          AppLogger.warning('Heart rate monitoring was marked as started but subscription is null - reconnecting');
          // Just reconnect the subscription without reinitializing the service
          _setupHeartRateSubscriptions();
        }
      } else {
        AppLogger.info('Heart rate subscription confirmed active for session $sessionId');
      }
    } catch (e) {
      final String RuckIdForError = sessionId ?? "unknown";
      AppLogger.error('Failed to start session $RuckIdForError: $e');
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
          debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _startLocationTracking stream onError: $error. Adding SessionFailed.');
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
    // Skip if already started to avoid disrupting the connection
    if (_isHeartRateMonitoringStarted) {
      AppLogger.info('Heart rate monitoring already started, skipping initialization');
      // Even if monitoring is already started, make sure we have active subscriptions
      _setupHeartRateSubscriptions();
      return;
    }
    
    AppLogger.info('Starting heart rate monitoring via HeartRateService...');
    
    // Start the heart rate service which handles both Watch and HealthKit
    await _heartRateService.startHeartRateMonitoring();
    
    // Mark as started
    _isHeartRateMonitoringStarted = true;
    
    // Setup subscriptions for heart rate updates
    _setupHeartRateSubscriptions();
    
    // Immediately get the current heart rate if available
    final currentHr = _heartRateService.latestHeartRate;
    if (currentHr > 0 && state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      AppLogger.info('Setting initial heart rate value: $currentHr BPM');
      emit(currentState.copyWith(latestHeartRate: currentHr));
    }
  }
  
  /// Set up subscriptions to heart rate data streams
  void _setupHeartRateSubscriptions() {
    AppLogger.info('Setting up heart rate stream subscriptions');
    
    // First, cancel any existing subscriptions to avoid duplicates
    _heartRateSubscription?.cancel();
    _heartRateBufferSubscription?.cancel();
    
    // Listen for individual heart rate updates
    _heartRateSubscription = _heartRateService.heartRateStream.listen(
      (HeartRateSample sample) {
        AppLogger.info('Heart rate sample received in ActiveSessionBloc: ${sample.bpm} BPM at ${sample.timestamp}');
        
        // Only process valid heart rate values
        if (sample.bpm <= 0) {
          AppLogger.warning('Ignoring invalid heart rate value: ${sample.bpm}');
          return;
        }
        
        // Update the session state with the latest heart rate
        if (state is ActiveSessionRunning) {
          final currentState = state as ActiveSessionRunning;
          final newHeartRateSamples = List<HeartRateSample>.from(currentState.heartRateSamples)..add(sample);

          // Only emit if heart rate has changed or samples list grew to avoid unnecessary renders
          if (currentState.latestHeartRate != sample.bpm || newHeartRateSamples.length > currentState.heartRateSamples.length) {
            AppLogger.info('Updating UI with heart rate: ${sample.bpm} BPM (previous: ${currentState.latestHeartRate}), total samples: ${newHeartRateSamples.length}');
            emit(currentState.copyWith(latestHeartRate: sample.bpm, heartRateSamples: newHeartRateSamples));
          }
        } else {
          AppLogger.warning('Received heart rate update but state is not ActiveSessionRunning: ${state.runtimeType}');
        }
      },
      onError: (error) {
        AppLogger.error('Error in heart rate stream: $error');
        // Try to recover by reestablishing the subscription
        Future.delayed(const Duration(seconds: 2), () {
          AppLogger.info('Attempting to reestablish heart rate subscription after error');
          _setupHeartRateSubscriptions();
        });
      },
    );
    
    // Listen for buffered heart rate samples to send to the API
    _heartRateBufferSubscription = _heartRateService.heartRateBufferStream.listen(
      (List<HeartRateSample> samples) {
        if (samples.isEmpty) return;
        
        AppLogger.info('[PAUSE_DEBUG] Received heart rate buffer with ${samples.length} samples in _setupHeartRateSubscriptions');

        if (state is ActiveSessionRunning) {
          final currentState = state as ActiveSessionRunning;
          // Only send if the session is NOT paused
          if (!currentState.isPaused) {
            AppLogger.info('[PAUSE_DEBUG] Session is RUNNING. Sending ${samples.length} HR samples via _sendHeartRateSamplesToApi.');
            _sendHeartRateSamplesToApi(currentState, samples);
          } else {
            AppLogger.info('[PAUSE_DEBUG] Session is PAUSED. Suppressing HR sample send for ${samples.length} samples.');
          }

          // Also update the current heart rate from the latest sample
          final latestSample = samples.last;
          if (latestSample.bpm > 0) {
            final currentState = state as ActiveSessionRunning;
            if (currentState.latestHeartRate != latestSample.bpm) {
              AppLogger.info('Updating UI with latest buffered heart rate: ${latestSample.bpm} BPM');
              emit(currentState.copyWith(latestHeartRate: latestSample.bpm));
            }
          }
        }
      },
      onError: (error) {
        AppLogger.error('Error in heart rate buffer stream: $error');
      },
    );
    
    AppLogger.info('Heart rate stream subscriptions successfully set up');
  }

  void _stopHeartRateMonitoring() {
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
    _heartRateBufferSubscription?.cancel();
    _heartRateBufferSubscription = null;
    
    // Reset the flag to allow restarting heart rate monitoring in a new session
    _isHeartRateMonitoringStarted = false;
    
    AppLogger.info('Heart rate monitoring stopped');
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
  
  /// Get the user's gender from the auth bloc state
  String? _getUserGender() {
    try {
      // Try to get from auth bloc state, which should have the User
      final authBloc = GetIt.instance<AuthBloc>();
      if (authBloc.state is Authenticated) {
        final User user = (authBloc.state as Authenticated).user;
        return user.gender;
      }
    } catch (e) {
      AppLogger.info('Could not get user gender from profile: $e');
    }
    
    return null; // Default to null (gender not specified)
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

      // If the session is currently paused, ignore location updates. This prevents
      // distance, pace and duration from changing while paused and avoids
      // sending "isPaused = 0" metric updates back to the watch which would
      // cause the watch UI to flip back to the running state.
      if (currentState.isPaused) {
        return;
      }

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
      
      // Check for distance milestones via service
      await _splitTrackingService.checkForMilestone(
        currentDistanceKm: currentState.distanceKm,
        sessionStartTime: currentState.originalSessionStartTimeUtc,
        elapsedSeconds: currentState.elapsedSeconds,
        isPaused: currentState.isPaused,
      );
      
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
    AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused event handler entered.');

    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;

      // Prevent re-pausing if already paused
      if (currentState.isPaused) {
        AppLogger.info('[PAUSE_DEBUG] _onSessionPaused: Session is already paused. Ignoring event.');
        return;
      }

      AppLogger.info('[PAUSE_DEBUG] _onSessionPaused: Processing pause. Current isPaused: ${currentState.isPaused}');
      _stopTicker(); // Stop the ticker to halt elapsed time updates

      final now = DateTime.now().toUtc();
      final newPausedState = currentState.copyWith(
        isPaused: true,
        currentPauseStartTimeUtc: now,
      );
      emit(newPausedState);
      AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: Paused. Emitting ActiveSessionRunning with isPaused: true. Watch update next.');
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused calling _watchService.updateSessionOnWatch. isPaused: true, distance: ${newPausedState.distanceKm}, elapsed: ${newPausedState.elapsedSeconds}');
      await _watchService.updateSessionOnWatch(
        distance: newPausedState.distanceKm,
        duration: Duration(seconds: newPausedState.elapsedSeconds),
        pace: newPausedState.pace ?? 0.0,
        isPaused: true,
        calories: newPausedState.calories.toDouble(),
        elevationGain: newPausedState.elevationGain,
        elevationLoss: newPausedState.elevationLoss,
      );
      AppLogger.info('Session paused. Watch notified.');
    } else if (state is ActiveSessionFailure) {
      final failureState = state as ActiveSessionFailure;
      if (failureState.sessionDetails != null) {
        AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused: Session is in ActiveSessionFailure state with details, attempting to pause it.');
        final sessionDetails = failureState.sessionDetails!;
        
        if (sessionDetails.isPaused) {
          AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused: SessionFailure details indicate already paused. Emitting and notifying watch.');
          _stopTicker(); 
          final now = DateTime.now().toUtc();
          final consistentPausedState = sessionDetails.copyWith(isPaused: true, currentPauseStartTimeUtc: sessionDetails.currentPauseStartTimeUtc ?? now);
          emit(consistentPausedState);
          await _watchService.updateSessionOnWatch(
            distance: consistentPausedState.distanceKm,
            duration: Duration(seconds: consistentPausedState.elapsedSeconds),
            pace: consistentPausedState.pace ?? 0.0,
            isPaused: true,
            calories: consistentPausedState.calories.toDouble(),
            elevationGain: consistentPausedState.elevationGain,
            elevationLoss: consistentPausedState.elevationLoss,
          );
          AppLogger.info('Session paused from failure state (already paused in details). Watch notified.');
          return;
        }

        _stopTicker();
        final now = DateTime.now().toUtc();
        final newPausedStateFromFailure = sessionDetails.copyWith(
          isPaused: true,
          currentPauseStartTimeUtc: now,
        );
        emit(newPausedStateFromFailure);
        AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: Paused from Failure. Emitting ActiveSessionRunning with isPaused: true. Watch update next.');
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused (from failure) calling _watchService.updateSessionOnWatch. isPaused: true, distance: ${newPausedStateFromFailure.distanceKm}, elapsed: ${newPausedStateFromFailure.elapsedSeconds}');
        await _watchService.updateSessionOnWatch(
          distance: newPausedStateFromFailure.distanceKm,
          duration: Duration(seconds: newPausedStateFromFailure.elapsedSeconds),
          pace: newPausedStateFromFailure.pace ?? 0.0,
          isPaused: true,
          calories: newPausedStateFromFailure.calories.toDouble(),
          elevationGain: newPausedStateFromFailure.elevationGain,
          elevationLoss: newPausedStateFromFailure.elevationLoss,
        );
        AppLogger.info('Session paused from failure state. Watch notified.');
      } else {
        AppLogger.warning('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused: Session is ActiveSessionFailure but has no sessionDetails. Cannot pause.');
      }
    } else {
      AppLogger.warning('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionPaused: Session is not ActiveSessionRunning or ActiveSessionFailure. Current state: ${state.runtimeType}. Cannot pause.');
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionResumed triggered. Event source: ${event.source}');
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;

      // Prevent re-resuming if already resumed
      if (!currentState.isPaused) {
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionResumed from WATCH, but already running. Ignoring to prevent loop.');
        // Similar to pause, consider logic if already resumed by watch.
      }
      
      // If not paused and event is not from UI override, consider logging and returning
      if (!currentState.isPaused && event.source != SessionActionSource.ui) {
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionResumed called but session already running. Current source: ${event.source}. State: $currentState');
        // emit(currentState); // Optionally re-emit
        // return; // Let it proceed
      }

      // Calculate paused duration
      int justPausedSeconds = 0;
      if (currentState.currentPauseStartTimeUtc != null) {
        justPausedSeconds = DateTime.now().toUtc().difference(currentState.currentPauseStartTimeUtc!).inSeconds;
      }
      final newTotalPausedDuration = currentState.totalPausedDuration + Duration(seconds: justPausedSeconds);

      // Notify the backend that the session is resumed
      try {
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: Notifying backend session ${currentState.sessionId} is RESUMED.');
        await _apiClient.post('/rucks/${currentState.sessionId}/resume', {});
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: Backend notified of RESUME for session ${currentState.sessionId}.');
      } catch (e) {
        AppLogger.error('Error notifying backend of session resume: $e');
        // Decide if this should prevent resume or just be logged
      }

      // Update the watch about the resume state *before* emitting the new state
      try {
        debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: Calling _watchService.resumeSessionOnWatch() for session ${currentState.sessionId}');
        await _watchService.resumeSessionOnWatch(); // Explicitly tell watch to resume
      } catch (e) {
        AppLogger.error('Error telling watch to resume: $e');
      }

      final newResumedState = currentState.copyWith(
        isPaused: false,
        totalPausedDuration: newTotalPausedDuration,
        clearCurrentPauseStartTimeUtc: true, // Clears currentPauseStartTimeUtc
      );
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: Emitting new Resumed state: isPaused: ${newResumedState.isPaused}, totalPausedDuration: ${newResumedState.totalPausedDuration}');
      emit(newResumedState);
      // Restart the ticker now that the session is running again
      _startTicker();
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: Resumed. Ticker restarted.');
    } else {
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionResumed called but state is not ActiveSessionRunning. State: $state');
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
        AppLogger.info('  distance_km: \u001b[36m${double.parse(currentState.distanceKm.toStringAsFixed(3))}\u001B[0m');
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
        AppLogger.info('  startTime: \u001b[32m${DateTime.now().subtract(actualDuration)}\u001b[0m');
        AppLogger.info('  endTime: \u001b[32m${DateTime.now()}\u001b[0m');
        AppLogger.info('  duration: \u001b[32m$actualDuration\u001b[0m');
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
        AppLogger.info('  heartRateSamples count: ${currentState.heartRateSamples.length}');
        
        await _apiClient.post(
          '/rucks/${currentState.sessionId}/complete',
          {
            'distance_km': double.parse(currentState.distanceKm.toStringAsFixed(3)),
            'duration_seconds': finalElapsedSeconds,
            'calories_burned': currentState.calories.round(),
            'elevation_gain_m': currentState.elevationGain.round(),
            'elevation_loss_m': currentState.elevationLoss.round(),
            'ruck_weight_kg': currentState.ruckWeightKg.roundToDouble(),
            'notes': event.notes,
            'rating': event.rating,
            'tags': event.tags,
            'perceived_exertion': event.perceivedExertion,
            'weight_kg': event.weightKg ?? currentState.weightKg,
            'planned_duration_minutes': event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null),
            'paused_duration_seconds': event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds,
            // Ensure heart rate samples are sent to the API if needed here
            // 'heart_rate_samples': currentState.heartRateSamples.map((s) => s.toJson()).toList(), 
          },
        );
        
        final completedSession = RuckSession(
          id: currentState.sessionId,
          // Use the computed start time for consistency
          startTime: DateTime.now().subtract(actualDuration),
          endTime: DateTime.now(),
          duration: actualDuration,
          distance: currentState.distanceKm,
          elevationGain: currentState.elevationGain,
          elevationLoss: currentState.elevationLoss,
          caloriesBurned: currentState.calories.toInt(),
          averagePace: currentState.distanceKm > 0 ? (currentState.elapsedSeconds / currentState.distanceKm) : 0.0,
          ruckWeightKg: currentState.ruckWeightKg,
          status: RuckStatus.completed,
          notes: event.notes,
          rating: event.rating,
          tags: event.tags ?? currentState.tags,
          perceivedExertion: event.perceivedExertion ?? currentState.perceivedExertion,
          weightKg: event.weightKg ?? currentState.weightKg,
          plannedDurationMinutes: event.plannedDurationMinutes ?? (currentState.plannedDuration != null ? (currentState.plannedDuration! ~/ 60) : null),
          pausedDurationSeconds: event.pausedDurationSeconds ?? currentState.totalPausedDuration.inSeconds,
          heartRateSamples: currentState.heartRateSamples, // Pass the collected samples
          locationPoints: currentState.locationPoints.map((p) => p.toJson()).toList(), // Pass collected location points as route
        );
        
        // Stop location tracking and ticker
        _locationSubscription?.cancel();
        _stopTicker();
        _stopHeartRateMonitoring();
        
        AppLogger.info('Session completed successfully. Emitting ActiveSessionComplete with session: ${completedSession.id}');
        AppLogger.info('Heart rate samples in completed session: ${completedSession.heartRateSamples?.length ?? 0}');
        
        emit(ActiveSessionComplete(session: completedSession));
      } on ApiException catch (e) {
        AppLogger.error('API Exception during session completion: ${e.message}');
        emit(ActiveSessionFailure(
          errorMessage: e.message,
          sessionDetails: state as ActiveSessionRunning, // Pass current state for potential recovery
        ));
      } catch (e, stackTrace) {
        AppLogger.error('Unexpected error during session completion: ${e.toString()}');
        emit(ActiveSessionFailure(
          errorMessage: 'Failed to complete session: ${e.toString()}. Please try again.',
          sessionDetails: state as ActiveSessionRunning, // Pass current state for potential recovery
        ));
      }
    } else {
      AppLogger.warning('SessionCompleted event received but state is not ActiveSessionRunning: ${state.runtimeType}');
    }
  }

  Future<void> _onSessionFailed(
    SessionFailed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.error('SessionFailed event received: ${event.errorMessage}');
    _stopTicker();
    _stopHeartRateMonitoring(); // Ensure heart rate monitoring is stopped on failure
    _locationSubscription?.cancel();
    _locationSubscription = null; // Clear the subscription

    // Send any remaining heart rate samples to the API
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      if (_heartRateService.heartRateBuffer.isNotEmpty) {
        await _sendHeartRateSamplesToApi(currentState, _heartRateService.heartRateBuffer);
        _heartRateService.clearHeartRateBuffer();
      }
      // Emit failure state with current session details
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionFailed triggered. Emitting ActiveSessionFailure with sessionDetails.');
      emit(ActiveSessionFailure(errorMessage: event.errorMessage, sessionDetails: currentState));
    } else {
      // Emit failure state without session details if not in ActiveSessionRunning state
      debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionFailed triggered. Emitting ActiveSessionFailure without sessionDetails.');
      emit(ActiveSessionFailure(errorMessage: event.errorMessage));
    }
  }

  Future<void> _sendHeartRateSamplesToApi(ActiveSessionRunning currentState, List<HeartRateSample> samples) async {
    if (samples.isEmpty) return;

    // Check if there is a session ID
    if (currentState.sessionId.isEmpty) {
      AppLogger.warning('No session ID available. Cannot send heart rate samples to API.');
      return;
    }

    final List<Map<String, dynamic>> samplesJson = samples.map((s) => s.toJson()).toList();
    
    try {
      AppLogger.info('[HR_BATCH] Sending batch of ${samplesJson.length} heart rate samples for session ${currentState.sessionId}.');
      await _apiClient.post(
        '/rucks/${currentState.sessionId}/heartrate',
        {'samples': samplesJson},
      );
      AppLogger.info('[HR_BATCH] Successfully sent ${samplesJson.length} heart rate samples.');
    } on ApiException catch (e) {
      AppLogger.error('[HR_BATCH] API Exception sending heart rate samples: ${e.message}');
    } catch (e, stackTrace) {
      AppLogger.error('[HR_BATCH] Unexpected error sending heart rate samples: ${e.toString()}');
    }
  }

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    // Update last tick time to track when ticks happen
    _lastTickTime = DateTime.now();
    _paceTickCounter++; // Increment local pace counter

    if (state is! ActiveSessionRunning) return;
    final currentState = state as ActiveSessionRunning;
    
    // If the session is currently paused, ignore this tick entirely. This ensures
    // we do NOT send an update with isPaused = false that could flip the watch
    // UI back to the running state. Because there might be one final tick that
    // slipped through the cracks right before _stopTicker() cancelled the
    // timer, this guard guarantees nothing happens while paused.
    if (currentState.isPaused) {
      return;
    }

    // Check if heart rate service buffer needs flushing ONLY IF NOT PAUSED
    if (_heartRateService.shouldFlushBuffer()) {
      AppLogger.info('Session is RUNNING. Flushing HR buffer.');
      await _heartRateService.flushHeartRateBuffer(); // This will trigger the listener in _setupHeartRateSubscriptions
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

    // Calories - include gender for more accurate gender-specific calculations
    final double calculatedCalories = MetCalculator.calculateRuckingCalories(
      userWeightKg: _getUserWeightKg(),
      ruckWeightKg: currentState.ruckWeightKg,
      distanceKm: currentState.distanceKm,
      elapsedSeconds: newElapsed,
      elevationGain: currentState.elevationGain,
      elevationLoss: currentState.elevationLoss,
      gender: _getUserGender(), // Include user gender for more accurate calculations
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
    
    // Send updates to the watch
    // Ensure pace has a non-null value; default to 0.0 if null
    debugPrint('[PAUSE_DEBUG] ActiveSessionBloc: _onTick calling _watchService.updateSessionOnWatch. isPaused: ${currentState.isPaused}, distance: ${currentState.distanceKm}, elapsed: $newElapsed');
    await _watchService.updateSessionOnWatch(
      distance: currentState.distanceKm,
      duration: Duration(seconds: newElapsed),
      pace: newPace ?? 0.0, // Pass 0.0 if newPace is null
      isPaused: currentState.isPaused,
      calories: finalCalories.toDouble(),
      elevationGain: currentState.elevationGain,
      elevationLoss: currentState.elevationLoss,
    );

    // Check for distance milestones via service on ticks too
    await _splitTrackingService.checkForMilestone(
      currentDistanceKm: currentState.distanceKm,
      sessionStartTime: currentState.originalSessionStartTimeUtc,
      elapsedSeconds: newElapsed,
      isPaused: currentState.isPaused,
    );
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
    AppLogger.info('SessionErrorCleared event received.');
    if (state is ActiveSessionFailure) {
      final failureState = state as ActiveSessionFailure;
      if (failureState.sessionDetails != null) {
        AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionErrorCleared. Restoring sessionDetails. isPaused: ${failureState.sessionDetails!.isPaused}');
        emit(failureState.sessionDetails!);
        if (!failureState.sessionDetails!.isPaused) {
          AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: Restored session was not paused. Restarting ticker and location tracking.');
          _startTicker();
          _startLocationTracking(emit); // This also handles heart rate if conditions are met within it
        }
      } else {
        AppLogger.info('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionErrorCleared. No sessionDetails in FailureState. Emitting ActiveSessionInitial.');
        emit(ActiveSessionInitial());
      }
    } else {
      AppLogger.warning('[PAUSE_DEBUG] ActiveSessionBloc: _onSessionErrorCleared called but current state is not ActiveSessionFailure. Emitting ActiveSessionInitial.');
      emit(ActiveSessionInitial());
    }
  }

  Future<void> _onFetchSessionPhotosRequested(
    FetchSessionPhotosRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(isPhotosLoading: true, photosError: null, clearPhotosError: true));
      try {
        final photos = await _sessionRepository.getSessionPhotos(event.sessionId);
 
        emit(currentState.copyWith(
          photos: photos,
          isPhotosLoading: false,
        ));
      } catch (e) {
        AppLogger.error('Failed to fetch session photos: $e');
        emit(currentState.copyWith(
          isPhotosLoading: false,
          photosError: 'Failed to load photos. Please try again.',
        ));
      }
    }
  }

  Future<void> _onUploadSessionPhotosRequested(
    UploadSessionPhotosRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(isUploading: true, uploadError: null, clearUploadError: true));
      
      try {
        AppLogger.info('Uploading ${event.photos.length} photos for session ${event.sessionId}');
        
        // Use the repository to upload photos
        final uploadedPhotos = await _sessionRepository.uploadSessionPhotos(
          event.sessionId,
          event.photos,
        );
        
        // IMPORTANT: Check if we got valid data back
        if (uploadedPhotos.isEmpty) {
          AppLogger.error('No photos returned from upload API - trying to fetch all photos instead');
          // If the upload succeeded but didn't return photo data, try to fetch all photos
          await Future.delayed(const Duration(seconds: 1)); // Wait a moment for the backend to process
          
          // Reload all photos to ensure we have the latest
          emit(currentState.copyWith(
            isUploading: false,
            isPhotosLoading: true,
          ));
          
          // Refetch all photos for this session
          final allPhotos = await _sessionRepository.getSessionPhotos(event.sessionId);
          AppLogger.info('Fetched ${allPhotos.length} photos after upload');
          
          // Create a new list with clean URLs to prevent caching issues
          final cleanedPhotos = allPhotos.map((photo) {
            if (photo.url != null && photo.url!.contains('?')) {
              // Need to create a new copy with the cleaned URL
              final cleanUrl = photo.url!.split('?')[0] + '?t=${DateTime.now().millisecondsSinceEpoch}';
              AppLogger.info('Cleaned photo URL: $cleanUrl');
              
              // Create a new RuckPhoto with the cleaned URL
              return RuckPhoto(
                id: photo.id,
                ruckId: photo.ruckId,
                userId: photo.userId,
                filename: photo.filename, 
                originalFilename: photo.originalFilename,
                contentType: photo.contentType,
                size: photo.size,
                createdAt: photo.createdAt,
                url: cleanUrl,
                thumbnailUrl: photo.thumbnailUrl != null 
                  ? photo.thumbnailUrl!.split('?')[0] + '?t=${DateTime.now().millisecondsSinceEpoch}'
                  : null,
              );
            }
            return photo;
          }).toList();
          
          emit(currentState.copyWith(
            photos: cleanedPhotos,  // Use our cleaned photos list
            isPhotosLoading: false,
            uploadSuccess: true,
          ));
          return;
        }
        
        // Clean all photo URLs to avoid caching issues
        final cleanedUploadedPhotos = uploadedPhotos.map((photo) {
          if (photo.url != null && photo.url!.contains('?')) {
            final cleanUrl = photo.url!.split('?')[0] + '?t=${DateTime.now().millisecondsSinceEpoch}';
            AppLogger.info('Cleaned photo URL: $cleanUrl');
            
            return RuckPhoto(
              id: photo.id,
              ruckId: photo.ruckId,
              userId: photo.userId,
              filename: photo.filename, 
              originalFilename: photo.originalFilename,
              contentType: photo.contentType,
              size: photo.size,
              createdAt: photo.createdAt,
              url: cleanUrl,
              thumbnailUrl: photo.thumbnailUrl != null 
                ? photo.thumbnailUrl!.split('?')[0] + '?t=${DateTime.now().millisecondsSinceEpoch}'
                : null,
            );
          }
          return photo;
        }).toList();
        
        // Get existing photos plus new ones
        final updatedPhotos = List<RuckPhoto>.from(currentState.photos ?? []);
        updatedPhotos.addAll(cleanedUploadedPhotos);  // Use the cleaned photos
        
        AppLogger.info('Successfully uploaded ${cleanedUploadedPhotos.length} photos');
        AppLogger.info('Photo URLs: ${cleanedUploadedPhotos.map((p) => p.url).join(', ')}');
        
        emit(currentState.copyWith(
          photos: updatedPhotos,
          isUploading: false,
          uploadSuccess: true,
        ));
      } catch (e) {
        AppLogger.error('Failed to upload photos: $e');
        emit(currentState.copyWith(
          isUploading: false,
          uploadError: 'Failed to upload photos. Please try again.',
        ));
      }
    }
  }

  Future<void> _onDeleteSessionPhotoRequested(
    DeleteSessionPhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      
      // Check if the photo exists in the current state
      final List<RuckPhoto> currentPhotos = List<RuckPhoto>.from(currentState.photos ?? []);
      final bool photoExists = currentPhotos.any((p) => p.id == event.photo.id);
      
      // If the photo is not in our state, it's likely already been deleted
      if (!photoExists) {
        AppLogger.info('Photo ${event.photo.id} not found in state, likely already deleted');
        return; // Exit early without emitting a new state
      }
      
      try {
        AppLogger.info('Deleting photo ${event.photo.id} from session ${event.sessionId}');
        
        // Optimistically remove the photo from the list immediately for responsive UI
        final List<RuckPhoto> updatedPhotos = currentPhotos.where((p) => p.id != event.photo.id).toList();
        
        emit(currentState.copyWith(
          photos: updatedPhotos,
          isDeleting: true,
        ));
        
        // Use the repository to delete the photo
        final success = await _sessionRepository.deletePhoto(event.photo);
        
        if (success) {
          AppLogger.info('Successfully deleted photo ${event.photo.id}');
          emit(currentState.copyWith(
            isDeleting: false,
            // Keep the updatedPhotos that were set in the optimistic update
          ));
        } else {
          // If deletion failed, restore the photo to the list
          AppLogger.error('Failed to delete photo ${event.photo.id}');
          emit(currentState.copyWith(
            photos: currentPhotos, // Restore original photos
            isDeleting: false,
            deleteError: 'Failed to delete photo. Please try again.',
          ));
        }
      } catch (e) {
        // Special handling for 404 errors - the photo was already deleted
        if (e.toString().contains('404') || e.toString().contains('not found')) {
          AppLogger.info('Photo ${event.photo.id} already deleted (404)');
          // Keep the optimistic update (photo removed from list)
          emit(currentState.copyWith(
            isDeleting: false,
          ));
        } else {
          // For other errors, restore the photo to the list
          AppLogger.error('Exception when deleting photo: $e');
          emit(currentState.copyWith(
            photos: currentPhotos, // Restore original photos
            isDeleting: false,
            deleteError: 'Failed to delete photo. Please try again.',
          ));
        }
      }
    }
  }

  Future<void> _onTakePhotoRequested(
    TakePhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('--- _onTakePhotoRequested: Event received for session ${event.sessionId} ---');
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      AppLogger.info('--- _onTakePhotoRequested: Current state is ActiveSessionRunning ---');
      
      try {
        AppLogger.info('Taking photo for session ${event.sessionId}');
        
        // Skip manual permission checks and let image_picker handle camera permissions
        AppLogger.info('--- _onTakePhotoRequested: Attempting to take photo with camera... ---');
        final imagePicker = ImagePicker();
        final XFile? pickedFile = await imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );
        AppLogger.info('--- _onTakePhotoRequested: Image picker result: ${pickedFile?.path ?? "No file picked"} ---');
        
        if (pickedFile != null) {
          // Upload the photo by dispatching an UploadSessionPhotosRequested event
          add(UploadSessionPhotosRequested(
            sessionId: event.sessionId,
            photos: [File(pickedFile.path)],
          ));
        }
      } catch (e) {
        AppLogger.error('Error taking photo: $e');
        emit(currentState.copyWith(
          uploadError: 'Error taking photo: $e',
        ));
      }
    } else {
      AppLogger.warning('--- _onTakePhotoRequested: Event received but state is ${state.runtimeType}, not ActiveSessionRunning. Skipping. ---');
    }
  }

  Future<void> _onPickPhotoRequested(
    PickPhotoRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('--- _onPickPhotoRequested: Event received for session ${event.sessionId} ---');
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      AppLogger.info('--- _onPickPhotoRequested: Current state is ActiveSessionRunning ---');
      
      try {
        AppLogger.info('Picking photos for session ${event.sessionId}');
        
        // Skip manual permission checks and let image_picker handle permissions
        AppLogger.info('--- _onPickPhotoRequested: Attempting to pick images from gallery... ---');
        final imagePicker = ImagePicker();
        final List<XFile> pickedFiles = await imagePicker.pickMultiImage(
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );
        
        AppLogger.info('--- _onPickPhotoRequested: Image picker result: ${pickedFiles.length} files picked ---');
        
        if (pickedFiles.isNotEmpty) {
          // Convert XFiles to Files and upload them
          final List<File> files = pickedFiles.map((xFile) => File(xFile.path)).toList();
          
          // Upload the photos by dispatching an UploadSessionPhotosRequested event
          add(UploadSessionPhotosRequested(
            sessionId: event.sessionId,
            photos: files,
          ));
        }
      } catch (e) {
        AppLogger.error('Error picking photos: $e');
        emit(currentState.copyWith(
          uploadError: 'Error picking photos: $e',
        ));
      }
    } else {
      AppLogger.warning('--- _onPickPhotoRequested: Event received but state is ${state.runtimeType}, not ActiveSessionRunning. Skipping. ---');
    }
  }

  Future<void> _onLoadSessionForViewing(
    LoadSessionForViewing event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('--- _onLoadSessionForViewing: Event received for session ${event.sessionId} ---');
    
    try {
      // Use the session object directly from the event
      final session = event.session;
      AppLogger.info('--- _onLoadSessionForViewing: Processing session ${event.sessionId} ---');

      // Create an empty list for location points
      List<LocationPoint> locationPoints = [];
      
      // Safely convert location points if they exist
      if (session.locationPoints != null) {
        try {
          for (var point in session.locationPoints!) {
            try {
              locationPoints.add(LocationPoint.fromJson(point));
            } catch (e) {
              // Log error but continue processing other points
              AppLogger.warning('Could not convert location point: $e');
            }
          }
        } catch (e) {
          AppLogger.warning('Error processing location points: $e');
          // Continue with empty location points rather than failing
        }
      }
      
      // Empty list for heart rate samples with null safety
      List<HeartRateSample> heartRateSamples = [];
      if (session.heartRateSamples != null) {
        heartRateSamples = session.heartRateSamples!;
      }

      // Handle numeric values safely with null-coalescing
      final int elapsedSeconds = session.duration != null ? session.duration.inSeconds : 0;
      final double distance = session.distance ?? 0.0;
      final double elevationGain = session.elevationGain ?? 0.0;
      final double elevationLoss = session.elevationLoss ?? 0.0;
      final int calories = session.caloriesBurned ?? 0;
      
      // Set a valid session ID (never null)
      final String sessionId = session.id ?? event.sessionId;
      
      // Use a safe default for start time
      final DateTime startTime = session.startTime;
      
      // Create the ActiveSessionRunning state with all required parameters
      // and safe defaults for optional ones
      emit(ActiveSessionRunning(
        sessionId: sessionId,
        locationPoints: locationPoints,
        elapsedSeconds: elapsedSeconds,
        distanceKm: distance,
        ruckWeightKg: session.ruckWeightKg,
        calories: calories,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        pace: session.averagePace,
        heartRateSamples: heartRateSamples,
        isPaused: false,
        originalSessionStartTimeUtc: startTime,
        totalPausedDuration: Duration(seconds: session.pausedDurationSeconds ?? 0),
        notes: session.notes,
        tags: session.tags,
        perceivedExertion: session.perceivedExertion,
        weightKg: session.weightKg,
        isGpsReady: true, // Viewing existing sessions, so GPS is ready
        photos: [], // Photos will be loaded separately via FetchSessionPhotosRequested
      ));
      
      AppLogger.info('--- _onLoadSessionForViewing: Successfully emitted ActiveSessionRunning for session $sessionId ---');
    } catch (e, stackTrace) {
      AppLogger.error('--- _onLoadSessionForViewing: Error loading session ${event.sessionId}: $e ---');
      AppLogger.error('Stack trace: $stackTrace');
      
      // Fall back to a safe failure state that won't crash the app
      emit(ActiveSessionFailure(
        errorMessage: 'Error loading session for viewing: ${e.toString()}',
        // Don't pass any session details to avoid propagating potentially corrupted data
        sessionDetails: null,
      ));
    }  
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _heartRateSubscription?.cancel();
    _heartRateBufferSubscription?.cancel();
    _ticker?.cancel();
    _watchdogTimer?.cancel();
    
    // Make sure to stop heart rate monitoring
    if (_isHeartRateMonitoringStarted) {
      _heartRateService.stopHeartRateMonitoring();
      _isHeartRateMonitoringStarted = false;
    }
    
    // Unregister this instance so a new session can register afresh.
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      GetIt.I.unregister<ActiveSessionBloc>();
    }
    return super.close();
  }
}