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

    AppLogger.info('SessionStarted event. Weight: ${event.ruckWeightKg}kg, Notes: ${event.notes}');
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
      AppLogger.info('Created new session with ID: $sessionId');

      await _apiClient.post('/rucks/$sessionId/start', {});
      AppLogger.info('Backend notified of session start for $sessionId');

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
        sessionPhotos: const [],
        photoLoadingStatus: PhotoLoadingStatus.initial,
        splits: const [],
      );
      emit(initialSessionState);
      AppLogger.info('ActiveSessionRunning emitted for $sessionId');

      await _watchService.startSessionOnWatch(event.ruckWeightKg);
      await _watchService.sendSessionIdToWatch(sessionId);

      _validationService.reset();
      _startLocationUpdates(sessionId);
      _startHeartRateMonitoring(sessionId); 
      add(TimerStarted());

    } catch (e, stackTrace) {
      String errorMessage = ErrorHandler.extractErrorMessage(e, defaultMessage: 'Failed to start session');
      AppLogger.error('Error starting session: $errorMessage', error: e, stackTrace: stackTrace);
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
    _locationSubscription = _locationService.onLocationChanged.listen((location) {
      add(LocationUpdated(location));
    });
    _locationService.startLocationTracking();
    AppLogger.info('Location tracking started for session $sessionId.');
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
      
      bool isValidLocation = _validationService.isValidLocation(newPoint, _lastValidLocation);
      if (!isValidLocation) {
        AppLogger.debug('Invalid location discarded: Acc ${newPoint.accuracy}');
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
        newDistanceKm += _locationService.calculateDistance(
          prevPoint.latitude, prevPoint.longitude, newPoint.latitude, newPoint.longitude
        ) / 1000.0;

        if (newPoint.altitude != null && prevPoint.altitude != null) {
          double altitudeChange = newPoint.altitude! - prevPoint.altitude!;
          if (altitudeChange > 0) newElevationGain += altitudeChange;
          else newElevationLoss += altitudeChange.abs();
        }
      }
      
      _splitTrackingService.updateDistance(newDistanceKm);

      _apiClient.post('/rucks/${currentState.sessionId}/location', newPoint.toJson())
        .catchError((e) => AppLogger.warning('Failed to send location to backend: $e'));

      emit(currentState.copyWith(
        locationPoints: newLocationPoints,
        distanceKm: newDistanceKm,
        elevationGain: newElevationGain,
        elevationLoss: newElevationLoss,
        isGpsReady: _validLocationCount > 5,
        splits: _splitTrackingService.getCurrentSplits(),
      ));
    }
  }
  
  Future<void> _onTimerStarted(TimerStarted event, Emitter<ActiveSessionState> emit) async {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) => add(Tick(timer.tick)));
    AppLogger.info('Master timer started.');

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
    AppLogger.info('Master timer and watchdog stopped.');
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
          AppLogger.info('Elapsed counter synced (diff ${(trueElapsed - _elapsedCounter).abs()}s)');
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

      User? currentUser = GetIt.I<AuthBloc>().state.user;
      double userWeightKg = currentUser?.weightKg ?? 70.0;
      double metValue = METCalculator.calculateMETs(
        speedKmh: newPace != null && newPace > 0 ? (60 / newPace) : 0,
        ruckWeightKg: currentState.ruckWeightKg,
        userWeightKg: userWeightKg,
        heartRate: _latestHeartRate, // Pass HR to METs for potentially more accurate calorie calc
      );
      double caloriesPerMinute = METCalculator.calculateCaloriesPerMinute(metValue, userWeightKg);
      double newCalories = currentState.calories + (caloriesPerMinute / 60.0);

      _splitTrackingService.updateDuration(Duration(seconds:newElapsed));

      emit(currentState.copyWith(
        elapsedSeconds: newElapsed,
        pace: newPace,
        calories: newCalories.round(),
        latestHeartRate: _latestHeartRate,
        minHeartRate: _minHeartRate,
        maxHeartRate: _maxHeartRate,
        heartRateSamples: _allHeartRateSamples.toList(),
        splits: _splitTrackingService.getCurrentSplits(),
      ));
    }
  }

  Future<void> _onSessionPaused(
    SessionPaused event, 
    Emitter<ActiveSessionState> emit
  ) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      _heartRateService.pauseMonitoring(); // Pause HR data collection/posting
      // Send any buffered heart rate samples before pausing
      if (_heartRateService.heartRateBuffer.isNotEmpty) {
         await _sendHeartRateSamplesToApi(currentState.sessionId, _heartRateService.heartRateBuffer);
        _heartRateService.clearHeartRateBuffer();
      }
      
      await _apiClient.post('/rucks/${currentState.sessionId}/pause', {});
      AppLogger.info('Session ${currentState.sessionId} paused.');
      
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
      
      _heartRateService.resumeMonitoring(); // Resume HR data collection/posting
      
      await _apiClient.post('/rucks/${currentState.sessionId}/resume', {});
      AppLogger.info('Session ${currentState.sessionId} resumed.');

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
        final User? currentUser = GetIt.I<AuthBloc>().state.user;
        final double userWeightKg = currentUser?.weightKg ?? 70.0;
        final double metValue = METCalculator.calculateMETs(
            speedKmh: currentState.pace != null && currentState.pace! > 0 ? (60 / currentState.pace!) : 0,
            ruckWeightKg: currentState.ruckWeightKg,
            userWeightKg: userWeightKg,
            heartRate: _latestHeartRate,
        );
        final double caloriesPerMinute = METCalculator.calculateCaloriesPerMinute(metValue, userWeightKg);
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
          'session_photos': currentState.sessionPhotos.map((p) => p.id).toList(),
          'splits': _splitTrackingService.getFinalSplits().map((s) => s.toJson()).toList(),
        };
        
        AppLogger.info('Completing session ${currentState.sessionId} with payload...');
        final response = await _apiClient.post('/rucks/${currentState.sessionId}/complete', payload);
        final RuckSession completedSession = RuckSession.fromJson(response);
        
        AppLogger.info('Session ${currentState.sessionId} completed successfully.');
        emit(SessionSummaryGenerated(session: completedSession, photos: currentState.sessionPhotos, photoLoadingStatus: currentState.photoLoadingStatus));
        await _watchService.endSessionOnWatch();
        await _healthService.saveWorkout(
            startTime: completedSession.startTime ?? currentState.originalSessionStartTimeUtc.subtract(finalTotalPausedDuration),
            endTime: completedSession.endTime ?? DateTime.now().toUtc(),
            distanceKm: completedSession.distanceKm,
            caloriesKcal: completedSession.caloriesBurned?.toDouble() ?? 0.0,
            metadata: {
              'ruck_id': completedSession.id,
              'ruck_weight_kg': completedSession.ruckWeightKg.toString(),
              'average_heart_rate': completedSession.averageHeartRate?.toString(),
            }
        );

      } catch (e, stackTrace) {
        String errorMessage = ErrorHandler.extractErrorMessage(e, defaultMessage: 'Failed to complete session');
        AppLogger.error('Error completing session: $errorMessage', error: e, stackTrace: stackTrace);
        try {
            await _apiClient.post('/rucks/${currentState.sessionId}/fail', {'error_message': 'Completion API call failed: $errorMessage'});
        } catch (failError) {
            AppLogger.error('Additionally, failed to mark session ${currentState.sessionId} as failed: $failError');
        }
        emit(ActiveSessionFailure(errorMessage: errorMessage, sessionDetails: currentState.toRuckSession(finalHeartRateSamples: _allHeartRateSamples)));
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

    RuckSession? sessionDetails;
    if (state is ActiveSessionRunning) {
        sessionDetails = (state as ActiveSessionRunning).toRuckSession(finalHeartRateSamples: _allHeartRateSamples);
    }

    if (event.sessionId != null && event.sessionId!.isNotEmpty) {
      try {
        await _apiClient.post('/rucks/${event.sessionId}/fail', {'error_message': event.errorMessage});
        AppLogger.info('Marked session ${event.sessionId} as failed on backend.');
      } catch (e) {
        AppLogger.error('Failed to mark session ${event.sessionId} as failed on backend: $e');
      }
    }
    emit(ActiveSessionFailure(errorMessage: event.errorMessage, sessionDetails: sessionDetails));
    await _watchService.discardSessionOnWatch();
  }

  void _startHeartRateMonitoring(String sessionId) {
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

    _heartRateService.startMonitoring(sessionId: sessionId);
    _isHeartRateMonitoringStarted = true;
    AppLogger.info('Heart rate monitoring started for session $sessionId.');
  }

  Future<void> _stopHeartRateMonitoring() async {
    if (!_isHeartRateMonitoringStarted) return;
    _heartRateSubscription?.cancel(); _heartRateSubscription = null;
    _heartRateBufferSubscription?.cancel(); _heartRateBufferSubscription = null;
    // Send any final buffered samples before stopping the service
    if (state is ActiveSessionRunning && _heartRateService.heartRateBuffer.isNotEmpty) {
        await _sendHeartRateSamplesToApi((state as ActiveSessionRunning).sessionId, _heartRateService.heartRateBuffer);
    }
    _heartRateService.stopMonitoring();
    _isHeartRateMonitoringStarted = false;
    AppLogger.info('Heart rate monitoring stopped.');
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
      await _apiClient.post('/rucks/$sessionId/heart_rate', {'samples': samplesJson});
      AppLogger.info('Sent ${samples.length} heart rate samples to API for $sessionId.');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to send heart rate samples to API', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _onFetchSessionPhotosRequested(
      FetchSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.loading));
      try {
        final photos = await _sessionRepository.getSessionPhotos(currentState.sessionId);
        emit(currentState.copyWith(sessionPhotos: photos, photoLoadingStatus: PhotoLoadingStatus.success));
      } catch (e) {
        AppLogger.error('Failed to fetch session photos: $e');
        emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.failure));
      }
    } else if (state is SessionSummaryGenerated) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.loading));
       try {
        final photos = await _sessionRepository.getSessionPhotos(currentState.session.id);
        emit(currentState.copyWith(photos: photos, photoLoadingStatus: PhotoLoadingStatus.success));
      } catch (e) {
        AppLogger.error('Failed to fetch session photos for summary: $e');
        emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.failure));
      }
    }
  }

  Future<void> _onUploadSessionPhotosRequested(
      UploadSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.loading));
      try {
        final uploadedPhotos = await _sessionRepository.uploadSessionPhotos(currentState.sessionId, event.photos);
        final currentPhotos = List<RuckPhoto>.from(currentState.sessionPhotos)..addAll(uploadedPhotos);
        emit(currentState.copyWith(sessionPhotos: currentPhotos, photoLoadingStatus: PhotoLoadingStatus.success));
      } catch (e) {
        AppLogger.error('Failed to upload session photos: $e');
        emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.failure));
      }
    }
  }

  Future<void> _onDeleteSessionPhotoRequested(
      DeleteSessionPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.loading));
      try {
        final success = await _sessionRepository.deleteSessionPhoto(event.photoId);
        if (success) {
          final updatedPhotos = currentState.sessionPhotos.where((p) => p.id != event.photoId).toList();
          emit(currentState.copyWith(sessionPhotos: updatedPhotos, photoLoadingStatus: PhotoLoadingStatus.success));
        } else {
          throw Exception('Failed to delete photo from repository');
        }
      } catch (e) {
        AppLogger.error('Failed to delete session photo: $e');
        emit(currentState.copyWith(photoLoadingStatus: PhotoLoadingStatus.failure));
      }
    }
  }

  void _onClearSessionPhotos(ClearSessionPhotos event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(sessionPhotos: [], photoLoadingStatus: PhotoLoadingStatus.initial));
    }
  }

  Future<void> _onTakePhotoRequested(TakePhotoRequested event, Emitter<ActiveSessionState> emit) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        add(UploadSessionPhotosRequested(photos: [File(photo.path)]));
      }
    } catch (e) {
      AppLogger.error('Error taking photo: $e');
      // Optionally emit a state indicating failure to take photo
    }
  }

  Future<void> _onPickPhotoRequested(PickPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    final ImagePicker picker = ImagePicker();
    try {
      final List<XFile> photos = await picker.pickMultiImage();
      if (photos.isNotEmpty) {
        add(UploadSessionPhotosRequested(photos: photos.map((p) => File(p.path)).toList()));
      }
    } catch (e) {
      AppLogger.error('Error picking photos: $e');
      // Optionally emit a state indicating failure to pick photos
    }
  }
  
  Future<void> _onLoadSessionForViewing(LoadSessionForViewing event, Emitter<ActiveSessionState> emit) async {
    AppLogger.info('Loading session for viewing: ${event.session.id}');
    // This event is primarily for UI to switch to a view mode with existing session data.
    // The BLoC might not need to do much other than emit a state that represents this mode.
    // For now, we assume the UI will use the provided session data directly.
    // If backend fetching is needed for this view, that logic would go here.

    // We can emit a SessionSummaryGenerated state, as it's designed to hold a completed session.
    // Fetch photos associated with this session if not already loaded.
    List<RuckPhoto> photos = event.session.photos ?? [];
    PhotoLoadingStatus photoStatus = PhotoLoadingStatus.initial;

    if (photos.isEmpty && event.session.id.isNotEmpty) {
        emit(SessionSummaryGenerated(session: event.session, photos: photos, photoLoadingStatus: PhotoLoadingStatus.loading));
        try {
            photos = await _sessionRepository.getSessionPhotos(event.session.id);
            photoStatus = PhotoLoadingStatus.success;
        } catch (e) {
            AppLogger.error('Failed to fetch photos for viewed session ${event.session.id}: $e');
            photoStatus = PhotoLoadingStatus.failure;
        }
    }
    emit(SessionSummaryGenerated(session: event.session, photos: photos, photoLoadingStatus: photoStatus));
  }

  void _onUpdateStateWithSessionPhotos(UpdateStateWithSessionPhotos event, Emitter<ActiveSessionState> emit) {
      if (state is ActiveSessionRunning) {
        final currentState = state as ActiveSessionRunning;
        emit(currentState.copyWith(sessionPhotos: event.photos, photoLoadingStatus: PhotoLoadingStatus.success));
      } else if (state is SessionSummaryGenerated) {
        final currentState = state as SessionSummaryGenerated;
        emit(currentState.copyWith(photos: event.photos, photoLoadingStatus: PhotoLoadingStatus.success));
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
    _locationSubscription?.cancel();
    _locationService.stopLocationTracking();
    await _stopHeartRateMonitoring(); 
    AppLogger.info('ActiveSessionBloc closed, all resources released.');
    super.close();
  }
}