library active_session_bloc;

import 'dart:async';
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:developer' as dev;
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
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/utils/met_calculator.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/split_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'active_session_coordinator.dart';

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
  final SplitTrackingService _splitTrackingService;
  final ActiveSessionStorage _activeSessionStorage;
  final TerrainTracker _terrainTracker;
  final ConnectivityService _connectivityService;

  // Coordinator for delegating to managers
  ActiveSessionCoordinator? _coordinator;
  StreamSubscription<ActiveSessionState>? _coordinatorSubscription;

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

  // Batch upload system for real-time data uploads during session
  Timer? _batchUploadTimer;
  final List<LocationPoint> _pendingLocationPoints = [];
  final List<HeartRateSample> _pendingHeartRateSamples = [];
  static const Duration _batchUploadInterval = Duration(minutes: 5);
  DateTime? _lastBatchUploadTime;
  bool _isBatchUploadInProgress = false;

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
    on<MemoryPressureDetected>(_onMemoryPressureDetected);
  }

  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('Starting session with delegation to coordinator');
    
    try {
      // Create coordinator if it doesn't exist
      if (_coordinator == null) {
        _coordinator = _createCoordinator();
        
        // Subscribe to coordinator state changes
        _coordinatorSubscription = _coordinator!.stream.listen((coordinatorState) {
          emit(coordinatorState);
        });
      }
      
      // Delegate to coordinator
      _coordinator!.add(event);
      
    } catch (e) {
      AppLogger.error('Session start failed: $e');
      emit(ActiveSessionError('Failed to start session: $e'));
    }
  }

  /// Create and configure the coordinator with all necessary services
  ActiveSessionCoordinator _createCoordinator() {
    return ActiveSessionCoordinator(
      sessionRepository: _sessionRepository,
      locationService: _locationService,
      authService: GetIt.I<AuthService>(),
      watchService: _watchService,
      storageService: GetIt.I<StorageService>(),
      apiClient: _apiClient,
      splitTrackingService: _splitTrackingService,
      terrainTracker: _terrainTracker,
      heartRateService: _heartRateService,
    );
  }

  void _startLocationUpdates(String sessionId) {
    _locationSubscription?.cancel();
    _batchLocationSubscription?.cancel();
    
    _locationSubscription = _locationService.startLocationTracking().listen(
      (locationPoint) {
        add(LocationUpdated(locationPoint));
        _lastLocationTimestamp = DateTime.now(); // Update last location timestamp
      },
      onError: (error) {
        AppLogger.warning('Location tracking error (continuing session without GPS): $error');
        // Don't stop the session - continue in offline mode without location updates
        // This allows users to ruck indoors, on airplanes, or in poor GPS areas
      },
    );
    
    // Only use batch location updates to prevent duplicate API calls
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

  Future<void> _onBatchLocationUpdated(
    BatchLocationUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Batch location processing is now handled by LocationTrackingManager
    AppLogger.debug('Delegating batch location processing to managers');
    
    // TODO: Route event to LocationTrackingManager through coordinator
    AppLogger.warning('Batch location processing delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onLocationUpdated(
    LocationUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // Location processing is now managed by LocationTrackingManager
    AppLogger.debug('Delegating location update to managers');
    
    // TODO: Route event to LocationTrackingManager through coordinator
    AppLogger.warning('Location update delegation not yet implemented - requires coordinator integration');
  }
  
  /// Process batch upload of location points
  Future<void> _processBatchLocationUpload(String sessionId, List<LocationPoint> locationPoints) async {
    AppLogger.info('Uploading batch of ${locationPoints.length} location points');
    
    final locationData = locationPoints.map((point) => point.toJson()).toList();
    
    try {
      await _apiClient.addLocationPoints(sessionId, locationData);
      AppLogger.info('Successfully uploaded ${locationPoints.length} location points');
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('Already Used')) {
        AppLogger.warning('[SESSION_RECOVERY] Location batch sync failed due to auth issue, will retry: $e');
        // Don't kill the session - continue tracking locally
      } else {
        AppLogger.warning('Failed to send location batch to backend: $e');
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

    // Start batch upload timer for real-time data uploads
    _startBatchUploadTimer();
  }

  void _stopTickerAndWatchdog() {
    _ticker?.cancel(); _ticker = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    _sessionPersistenceTimer?.cancel(); _sessionPersistenceTimer = null;
    _batchUploadTimer?.cancel(); _batchUploadTimer = null;
    AppLogger.debug('Master timer, watchdog, session persistence, and batch upload timers stopped.');
  }

  /// Start batch upload timer for real-time data uploads during session
  void _startBatchUploadTimer() {
    _batchUploadTimer?.cancel();
    _batchUploadTimer = Timer.periodic(_batchUploadInterval, (timer) async {
      if (state is ActiveSessionRunning && !_isBatchUploadInProgress) {
        final currentState = state as ActiveSessionRunning;
        await _processBatchUpload(currentState.sessionId);
      }
    });
    AppLogger.info('Batch upload timer started - uploading data every ${_batchUploadInterval.inMinutes} minutes');
  }

  /// Process batch upload of pending location points and heart rate samples
  Future<void> _processBatchUpload(String sessionId) async {
    // Batch upload logic is now handled by UploadManager
    AppLogger.debug('Delegating batch upload to managers');
    
    // TODO: Route to UploadManager through coordinator
    AppLogger.warning('Batch upload delegation not yet implemented - requires coordinator integration');
  }

  // Upload methods now handled by UploadManager

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    // Session timer, metrics, and state updates are now handled by multiple managers
    AppLogger.debug('Delegating tick processing to managers');
    
    // TODO: Route to SessionLifecycleManager, HeartRateManager, and others through coordinator
    AppLogger.warning('Tick delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onSessionPaused(
    SessionPaused event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('Pausing session with delegation to coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session pause');
      emit(ActiveSessionError('Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('Resuming session with delegation to coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session resume');
      emit(ActiveSessionError('Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionCompleted(
    SessionCompleted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Session completion logic is now handled by SessionLifecycleManager
    AppLogger.debug('Delegating session completion to managers');
    
    // TODO: Route event to SessionLifecycleManager through coordinator
    AppLogger.warning('Session completion delegation not yet implemented - requires coordinator integration');
    
    // For now, emit initial state to prevent app from getting stuck
    emit(ActiveSessionInitial());
  }

  Future<void> _onSessionFailed(
    SessionFailed event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // Session failure handling is now managed by SessionLifecycleManager
    AppLogger.debug('Delegating session failure to managers');
    
    // TODO: Route event to SessionLifecycleManager through coordinator
    AppLogger.warning('Session failure delegation not yet implemented - requires coordinator integration');
    
    // For now, emit a failure state to prevent app from getting stuck
    emit(ActiveSessionFailure(errorMessage: event.errorMessage, sessionDetails: null));
  }

  // Heart rate monitoring start/stop is now handled by HeartRateManager
  Future<void> _startHeartRateMonitoring(String sessionId) async {
    // TODO: Route to HeartRateManager through coordinator
    AppLogger.warning('Heart rate monitoring start delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _stopHeartRateMonitoring() async {
    // TODO: Route to HeartRateManager through coordinator
    AppLogger.warning('Heart rate monitoring stop delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Heart rate processing logic is now handled by HeartRateManager
    AppLogger.debug('Delegating heart rate update to managers');
    
    // TODO: Route event to HeartRateManager through coordinator
    AppLogger.warning('Heart rate update delegation not yet implemented - requires coordinator integration');
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
        // TODO: Delegate to HeartRateManager for API upload
        AppLogger.debug('[HR_API_THROTTLE] [STUB] Would send ${event.samples.length} heart rate samples to API');
        _lastApiHeartRateTime = now;
      } else {
        AppLogger.debug('[HR_API_THROTTLE] Skipped sending ${event.samples.length} heart rate samples to API (throttled)');
      }
      // Optionally emit state if UI needs to reflect that a batch was sent, though usually not needed.
    }
  }

  // Heart rate API calls now handled by HeartRateManager

  Future<void> _onFetchSessionPhotosRequested(
    FetchSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    // Photo fetching logic is now handled by PhotoManager
    AppLogger.debug('Delegating photo fetching to managers');
    
    // TODO: Route event to PhotoManager through coordinator
    AppLogger.warning('Photo fetching delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onUploadSessionPhotosRequested(
      UploadSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    // Photo uploading logic is now handled by PhotoManager
    AppLogger.debug('Delegating photo uploading to managers');
    
    // TODO: Route event to PhotoManager through coordinator
    AppLogger.warning('Photo uploading delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onDeleteSessionPhotoRequested(
      DeleteSessionPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    // Photo deletion logic is now handled by PhotoManager
    AppLogger.debug('Delegating photo deletion to managers');
    
    // TODO: Route event to PhotoManager through coordinator
    AppLogger.warning('Photo deletion delegation not yet implemented - requires coordinator integration');
  }

  void _onClearSessionPhotos(ClearSessionPhotos event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photos: []));
    }
  }

  Future<void> _onTakePhotoRequested(TakePhotoRequested event, Emitter<ActiveSessionState> emit) async {
    // Photo capture logic is now handled by PhotoManager
    AppLogger.debug('Delegating photo capture to managers');
    
    // TODO: Route event to PhotoManager through coordinator
    AppLogger.warning('Photo capture delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onPickPhotoRequested(PickPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    // Photo picking logic is now handled by PhotoManager
    AppLogger.debug('Delegating photo picking to managers');
    
    // TODO: Route event to PhotoManager through coordinator
    AppLogger.warning('Photo picking delegation not yet implemented - requires coordinator integration');
  }
  
  Future<void> _onLoadSessionForViewing(LoadSessionForViewing event, Emitter<ActiveSessionState> emit) async {
    // Session loading logic is now handled by SessionLifecycleManager and PhotoManager
    AppLogger.debug('Delegating session loading to managers');
    
    // TODO: Route to SessionLifecycleManager and PhotoManager through coordinator
    // For now, emit simple state to prevent UI breakage
    emit(SessionSummaryGenerated(
      session: event.session,
      photos: event.session.photos ?? [],
      isPhotosLoading: false,
    ));
    
    AppLogger.warning('Session loading delegation not yet implemented - requires coordinator integration');
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
    // Session recovery logic is now handled by SessionLifecycleManager
    AppLogger.debug('Delegating session recovery to managers');
    
    // TODO: Route event to SessionLifecycleManager through coordinator
    AppLogger.warning('Session recovery delegation not yet implemented - requires coordinator integration');
  }

  Future<void> _onSessionReset(
    SessionReset event, 
    Emitter<ActiveSessionState> emit
  ) async {
    // Session reset logic is now handled by SessionLifecycleManager
    AppLogger.debug('Delegating session reset to managers');
    
    // TODO: Route event to SessionLifecycleManager through coordinator
    AppLogger.warning('Session reset delegation not yet implemented - requires coordinator integration');
    
    // For now, emit initial state to prevent app from getting stuck
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
    AppLogger.debug('Closing ActiveSessionBloc - cleaning up resources');
    
    // Clean up coordinator first
    try {
      await _coordinatorSubscription?.cancel();
      await _coordinator?.close();
      _coordinator = null;
      
      // Clean up the underlying services that this bloc still directly manages
      // Stop location tracking
      await _locationService.stopLocationTracking();
      
      // Stop heart rate monitoring if it was started
      _heartRateService.stopHeartRateMonitoring();
      
      AppLogger.debug('ActiveSessionBloc resources cleaned up successfully');
    } catch (e) {
      AppLogger.error('Error during ActiveSessionBloc cleanup: $e');
    }
    
    return super.close();
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
    // Session cleanup logic is now handled by MemoryManager
    AppLogger.debug('Delegating session cleanup to managers');
    
    // TODO: Route event to MemoryManager through coordinator
    AppLogger.warning('Session cleanup delegation not yet implemented - requires coordinator integration');
  }
  
  // Memory pressure handling is now managed by MemoryPressureManager

  // Offline session sync is now handled by UploadManager
  void _syncOfflineSessionsInBackground() {
    // TODO: Route to UploadManager through coordinator
    AppLogger.warning('Offline session sync delegation not yet implemented - requires coordinator integration');
  }

  // Session completion payload building is now handled by SessionLifecycleManager
  Future<Map<String, dynamic>> _buildCompletionPayloadInBackground(
    ActiveSessionRunning currentState,
    Map<String, dynamic> terrainStats,
    List<LocationPoint> route,
    List<HeartRateSample> heartRateSamples,
  ) async {
    // TODO: Route to SessionLifecycleManager through coordinator
    AppLogger.warning('Completion payload building delegation not yet implemented - requires coordinator integration');
    return {};
  }

  // Connectivity monitoring is now handled by LocationTrackingManager
  void _startConnectivityMonitoring(String sessionId) {
    // TODO: Route to LocationTrackingManager through coordinator
    AppLogger.warning('Connectivity monitoring delegation not yet implemented - requires coordinator integration');
  }

  // Location tracking ensurance is now handled by LocationTrackingManager
  void _ensureLocationTrackingActive(String sessionId) {
    // TODO: Route to LocationTrackingManager through coordinator
    AppLogger.warning('Location tracking delegation not yet implemented - requires coordinator integration');
  }

  // Offline session sync is now handled by UploadManager
  Future<void> _attemptOfflineSessionSync(String sessionId) async {
    // TODO: Route to UploadManager through coordinator
    AppLogger.warning('Offline session sync delegation not yet implemented - requires coordinator integration');
  }
  
  // All diagnostic methods removed - now handled by managers
  
  Future<void> _onMemoryPressureDetected(
    MemoryPressureDetected event,
    Emitter<ActiveSessionState> emit,
  ) async {
    // Memory pressure handling is now managed by MemoryManager
    AppLogger.debug('Delegating memory pressure detection to managers');
    
    // TODO: Route event to MemoryManager through coordinator
    AppLogger.warning('Memory pressure delegation not yet implemented - requires coordinator integration');
  }
  
  // All diagnostic and memory pressure methods removed - now handled by dedicated managers
}