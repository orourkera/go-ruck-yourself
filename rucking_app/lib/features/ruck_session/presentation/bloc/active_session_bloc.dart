library active_session_bloc;

import 'dart:async';
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/api_exceptions.dart';
import 'package:rucking_app/core/models/api_exception.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
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
import 'package:rucking_app/core/services/session_completion_detection_service.dart';
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
import 'package:rucking_app/features/ai_cheerleader/services/ai_cheerleader_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/ai_analytics_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/elevenlabs_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/location_context_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/ai_audio_service.dart';
import 'package:latlong2/latlong.dart' as latlong;
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
  final SessionCompletionDetectionService _completionDetectionService;
  
  // AI Cheerleader services
  final AICheerleaderService _aiCheerleaderService;
  final OpenAIService _openAIService;
  final ElevenLabsService _elevenLabsService;
  final LocationContextService _locationContextService;
  final AIAudioService _audioService;

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

  // AI Cheerleader state tracking
  bool _aiCheerleaderEnabled = false;
  String? _aiCheerleaderPersonality;
  bool _aiCheerleaderExplicitContent = false;
  User? _currentUser;

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
    required SessionCompletionDetectionService completionDetectionService,
    required AICheerleaderService aiCheerleaderService,
    required OpenAIService openAIService,
    required ElevenLabsService elevenLabsService,
    required LocationContextService locationContextService,
    required AIAudioService audioService,
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
        _completionDetectionService = completionDetectionService,
        _aiCheerleaderService = aiCheerleaderService,
        _openAIService = openAIService,
        _elevenLabsService = elevenLabsService,
        _locationContextService = locationContextService,
        _audioService = audioService,
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
    on<AICheerleaderManualTriggerRequested>(_onAICheerleaderManualTriggerRequested);
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
    on<CheckForCrashedSession>(_onCheckForCrashedSession);
    on<_CoordinatorStateForwarded>(_onCoordinatorStateForwarded);
    on<SessionRecovered>(_onSessionRecovered);
  }

  Future<void> _onSessionStarted(
    SessionStarted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('Starting session with delegation to coordinator');
    
    try {
      // Capture AI Cheerleader parameters
      _aiCheerleaderEnabled = event.aiCheerleaderEnabled;
      _aiCheerleaderPersonality = event.aiCheerleaderPersonality;
      _aiCheerleaderExplicitContent = event.aiCheerleaderExplicitContent;
      
      // Reset AI Cheerleader service for new session
      if (_aiCheerleaderEnabled) {
        _aiCheerleaderService.reset();
        AppLogger.info('AI Cheerleader enabled: $_aiCheerleaderPersonality (explicit: $_aiCheerleaderExplicitContent)');
        
        // Get current user for context
        final authService = GetIt.I<AuthService>();
        _currentUser = await authService.getCurrentUser();
      }
      
      // Create coordinator if it doesn't exist
      if (_coordinator == null) {
        _coordinator = _createCoordinator();
        _setupCoordinatorSubscription();
      }
      
      // Delegate to coordinator
      _coordinator!.add(event);
      
    } catch (e) {
      AppLogger.error('Session start failed: $e');
      emit(ActiveSessionFailure(errorMessage: 'Failed to start session: $e'));
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
      connectivityService: _connectivityService,
      splitTrackingService: _splitTrackingService,
      terrainTracker: _terrainTracker,
      heartRateService: _heartRateService,
      openAIService: _openAIService,
    );
  }

  /// Setup coordinator subscription using event forwarding instead of direct emit
  void _setupCoordinatorSubscription() {
    _coordinatorSubscription?.cancel();
    _coordinatorSubscription = _coordinator!.stream.listen(
      (coordinatorState) {
        // Forward coordinator state as an internal event instead of calling emit directly
        // This prevents "emit after event handler completed" errors
        _forwardCoordinatorState(coordinatorState);
      },
      onError: (error) {
        AppLogger.error('Coordinator state error: $error');
        // Use a generic sessionId since we don't have access to the actual session ID during setup
        add(SessionFailed(
          errorMessage: 'Session coordination failed: $error',
          sessionId: 'coordinator-setup-error',
        ));
      },
    );
  }

  /// Forward coordinator state safely by converting it to an internal event
  void _forwardCoordinatorState(ActiveSessionState coordinatorState) {
    // Handle session completion detection service lifecycle
    _handleCompletionDetectionServiceLifecycle(coordinatorState);
    
    // Check for AI Cheerleader triggers if enabled and session is running
    if (_aiCheerleaderEnabled && 
        coordinatorState is ActiveSessionRunning &&
        _aiCheerleaderPersonality != null &&
        _currentUser != null) {
      AppLogger.info('[AI_DEBUG] Checking AI triggers - enabled: $_aiCheerleaderEnabled, personality: $_aiCheerleaderPersonality, user: ${_currentUser?.username}');
      _checkAICheerleaderTriggers(coordinatorState);
    } else {
      AppLogger.info('[AI_DEBUG] AI triggers skipped - enabled: $_aiCheerleaderEnabled, running: ${coordinatorState is ActiveSessionRunning}, personality: $_aiCheerleaderPersonality, user: ${_currentUser?.username}');
    }
    
    // Instead of calling emit directly, we use a custom event to safely forward states
    // This ensures the emission happens within a proper event handler context
    add(_CoordinatorStateForwarded(coordinatorState));
  }

  /// Handle session completion detection service lifecycle
  void _handleCompletionDetectionServiceLifecycle(ActiveSessionState state) {
    try {
      if (state is ActiveSessionRunning && state.isPaused == false) {
        // Start monitoring if session is actively running
        if (!_completionDetectionService.isMonitoring) {
          AppLogger.info('[SESSION_COMPLETION] Starting completion detection monitoring');
          _completionDetectionService.startMonitoring();
          
          // Update heart rate data if available
          if (state.latestHeartRate != null) {
            // Calculate average heart rate from samples
            double? workoutAverage;
            if (state.heartRateSamples.isNotEmpty) {
              final totalHr = state.heartRateSamples.fold<double>(0, (sum, sample) => sum + sample.bpm);
              workoutAverage = totalHr / state.heartRateSamples.length;
            }
            
            _completionDetectionService.updateHeartRateData(
              currentHeartRate: state.latestHeartRate!.toDouble(),
              restingHeartRate: null, // Could be added from health profile
              workoutAverage: workoutAverage,
            );
          }
        }
      } else {
        // Stop monitoring if session is paused, completed, or failed
        if (_completionDetectionService.isMonitoring) {
          AppLogger.info('[SESSION_COMPLETION] Stopping completion detection monitoring');
          _completionDetectionService.stopMonitoring();
        }
      }
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Error managing detection service lifecycle: $e');
    }
  }

  /// Check for AI Cheerleader triggers and process them
  Future<void> _checkAICheerleaderTriggers(ActiveSessionRunning state) async {
    try {
      AppLogger.info('[AI_DEBUG] Analyzing triggers for state: distance=${state.distanceKm}km, time=${state.elapsedSeconds}s');
      final trigger = _aiCheerleaderService.analyzeTriggers(
        state,
        preferMetric: _currentUser!.preferMetric,
      );
      AppLogger.info('[AI_DEBUG] Trigger analysis result: ${trigger?.type.name ?? 'null'}');
      if (trigger != null) {
        AppLogger.info('[AI_CHEERLEADER] Trigger detected: ${trigger.type.name}');
        await _processAICheerleaderTrigger(trigger, state);
      } else {
        AppLogger.info('[AI_DEBUG] No trigger detected this cycle');
      }
    } catch (e) {
      AppLogger.error('[AI_CHEERLEADER] Trigger detection failed: $e');
    }
  }

  /// Handle manual AI Cheerleader trigger request from user
  Future<void> _onAICheerleaderManualTriggerRequested(
    AICheerleaderManualTriggerRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] ======= MANUAL TRIGGER BUTTON PRESSED =======');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] AI Cheerleader enabled: $_aiCheerleaderEnabled');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] AI Cheerleader personality: $_aiCheerleaderPersonality');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] Current user: $_currentUser');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] Current state type: ${state.runtimeType}');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] State is ActiveSessionRunning: ${state is ActiveSessionRunning}');
    
    if (!_aiCheerleaderEnabled || 
        _aiCheerleaderPersonality == null || 
        _currentUser == null ||
        state is! ActiveSessionRunning) {
      AppLogger.error('[AI_CHEERLEADER_DEBUG] Manual trigger REJECTED - conditions not met:');
      AppLogger.error('[AI_CHEERLEADER_DEBUG] - AI enabled: $_aiCheerleaderEnabled');
      AppLogger.error('[AI_CHEERLEADER_DEBUG] - Personality set: $_aiCheerleaderPersonality');
      AppLogger.error('[AI_CHEERLEADER_DEBUG] - User exists: ${_currentUser != null}');
      AppLogger.error('[AI_CHEERLEADER_DEBUG] - Session running: ${state is ActiveSessionRunning}');
      return;
    }

    final runningState = state as ActiveSessionRunning;
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] Session state OK - proceeding with trigger');
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] Session elapsed: ${runningState.elapsedSeconds}s, distance: ${runningState.distanceKm}km');
    
    // Create a special manual trigger with current session context
    final manualTrigger = CheerleaderTrigger(
      type: TriggerType.manualRequest,
      data: {
        'elapsedMinutes': runningState.elapsedSeconds ~/ 60,
        'distanceKm': runningState.distanceKm,
        'manualRequest': true,
      },
    );
    
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] Manual trigger created, calling _processAICheerleaderTrigger...');
    final generatedMessage = await _processAICheerleaderTrigger(manualTrigger, runningState);
    AppLogger.warning('[AI_CHEERLEADER_DEBUG] ======= MANUAL TRIGGER PROCESSING COMPLETE =======');

    // Emit UI-visible message if available
    if (generatedMessage != null && generatedMessage.isNotEmpty) {
      AppLogger.info('[AI_CHEERLEADER_UI] Emitting AI cheer message to UI');
      emit(runningState.copyWith(aiCheerMessage: generatedMessage));
    } else {
      AppLogger.warning('[AI_CHEERLEADER_UI] No message generated to emit');
    }
  }

  /// Process AI Cheerleader trigger through the full pipeline
  Future<String?> _processAICheerleaderTrigger(
    CheerleaderTrigger trigger, 
    ActiveSessionRunning state
  ) async {
    try {
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 1: Assembling context...');
      // 1. Fetch historical user data for richer AI context
      Map<String, dynamic>? history;
      try {
        AppLogger.info('[AI_CHEERLEADER_DEBUG] Fetching user history from ${ApiEndpoints.aiCheerleaderUserHistory}');
        final historyResp = await _apiClient.get(ApiEndpoints.aiCheerleaderUserHistory, queryParams: {
          'ruck_limit': 50,
          'achievements_limit': 50,
        });
        if (historyResp is Map<String, dynamic>) {
          history = historyResp;
          AppLogger.info('[AI_CHEERLEADER_DEBUG] User history fetched successfully');
        } else {
          AppLogger.warning('[AI_CHEERLEADER_DEBUG] Unexpected user history response type: ${historyResp.runtimeType}');
        }
      } catch (e) {
        AppLogger.warning('[AI_CHEERLEADER_DEBUG] Failed to fetch user history (continuing without it): $e');
      }

      // 2. Fetch coaching plan data for AI context
      Map<String, dynamic>? coachingPlan;
      try {
        final coachingResponse = await _apiClient.get('/user-coaching-plans');
        if (coachingResponse != null && coachingResponse is Map<String, dynamic>) {
          coachingPlan = coachingResponse;
          AppLogger.info('[AI_CHEERLEADER_DEBUG] Fetched coaching plan data: ${coachingPlan?['plan_name']}');
        }
      } catch (e) {
        AppLogger.info('[AI_CHEERLEADER_DEBUG] No coaching plan available: $e');
      }

      // 3. Assemble context for AI generation (including history and coaching plan if available)
      final context = _aiCheerleaderService.assembleContext(
        state,
        trigger,
        _currentUser!,
        _aiCheerleaderPersonality!,
        _aiCheerleaderExplicitContent,
        history: history,
        coachingPlan: coachingPlan,
      );
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 1 complete: Context assembled');
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Context keys: ${context.keys.toList()}');

      // Inspect assembled context typing and normalize environment before any location work
      AppLogger.info('[AI_CONTEXT_DEBUG] Context runtimeType: ${context.runtimeType}');
      final envRawBefore = context['environment'];
      AppLogger.info('[AI_CONTEXT_DEBUG] Environment (pre-normalization) type: ${envRawBefore?.runtimeType}');
      AppLogger.info('[AI_CONTEXT_DEBUG] Environment (pre-normalization) value: $envRawBefore');
      try {
        if (envRawBefore is Map) {
          final envKeys = (envRawBefore as Map).keys.toList();
          AppLogger.info('[AI_CONTEXT_DEBUG] Environment keys: $envKeys');
        }
      } catch (_) {}

      // Normalize environment to Map<String, dynamic> to avoid Map<String, String> inference downstream
      final Map<String, dynamic> _normalizedEnv =
          (envRawBefore is Map)
              ? Map<String, dynamic>.from(envRawBefore as Map)
              : <String, dynamic>{};
      context['environment'] = _normalizedEnv;
      AppLogger.info('[AI_CONTEXT_DEBUG] Environment normalized type: ${context['environment']?.runtimeType}');
      AppLogger.info('[AI_CONTEXT_DEBUG] Environment normalized value: ${context['environment']}');

      // 2. Add location context if available
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 2: Adding location context...');
      AppLogger.warning('[AI_LOCATION_DEBUG] Checking location context...');
      AppLogger.warning('[AI_LOCATION_DEBUG] State type: ${state.runtimeType}');
      AppLogger.warning('[AI_LOCATION_DEBUG] About to access state.locationPoints...');
      
      try {
        AppLogger.warning('[AI_LOCATION_DEBUG] Location points available: ${state.locationPoints.length}');
        AppLogger.warning('[AI_LOCATION_DEBUG] Location points type: ${state.locationPoints.runtimeType}');
        
        AppLogger.warning('[AI_LOCATION_DEBUG] About to check if locationPoints is not empty...');
        final lastLocation = state.locationPoints.isNotEmpty ? state.locationPoints.last : null;
        AppLogger.warning('[AI_LOCATION_DEBUG] Last location extracted: $lastLocation');
        AppLogger.warning('[AI_LOCATION_DEBUG] Last location type: ${lastLocation.runtimeType}');
        
        if (lastLocation != null) {
          AppLogger.warning('[AI_LOCATION_DEBUG] Last location coords: ${lastLocation.latitude}, ${lastLocation.longitude}');
          AppLogger.warning('[AI_LOCATION_DEBUG] About to call getLocationContext...');
          
          final locationContext = await _locationContextService.getLocationContext(
            lastLocation.latitude,
            lastLocation.longitude,
          ).timeout(
            Duration(seconds: 5),
            onTimeout: () {
              AppLogger.warning('[AI_LOCATION_DEBUG] Location context call timed out after 5 seconds');
              return null;
            },
          );
          AppLogger.warning('[AI_LOCATION_DEBUG] getLocationContext call completed');
          
          AppLogger.info('[AI_LOCATION_DEBUG] Location context result: $locationContext');
          
          if (locationContext != null) {
            // Ensure environment is a mutable Map<String, dynamic> before adding location
            final envRaw = context['environment'];
            AppLogger.warning('[AI_LOCATION_DEBUG] Environment before update - type: ${envRaw.runtimeType}, value: $envRaw');

            // Create a dynamic-typed copy to avoid Map<String, String> value type restriction
            final Map<String, dynamic> environment =
                (envRaw is Map)
                    ? Map<String, dynamic>.from(envRaw as Map)
                    : <String, dynamic>{};

            environment['location'] = {
              'description': locationContext.description,
              'city': locationContext.city,
              'terrain': locationContext.terrain,
              'landmark': locationContext.landmark ?? '', // Handle nullable landmark
              'weatherCondition': locationContext.weatherCondition,
              'temperature': locationContext.temperature,
            };
            context['environment'] = environment;
            AppLogger.info('[AI_LOCATION_DEBUG] Added location to context: ${environment['location']}');
            
            // Also populate a dedicated weather map for OpenAIService prompt consumption
            // OpenAIService._buildBaseContext expects environment['weather'] with keys like tempF/tempC and condition/summary
            final weatherMap = <String, dynamic>{};
            if (locationContext.temperature != null) {
              weatherMap['tempF'] = locationContext.temperature; // Fahrenheit already
            }
            final condition = locationContext.weatherCondition;
            if (condition != null && condition.isNotEmpty) {
              weatherMap['condition'] = condition;
            }
            if (weatherMap.isNotEmpty) {
              environment['weather'] = weatherMap;
              context['environment'] = environment; // reassign to ensure updated ref
              AppLogger.info('[AI_LOCATION_DEBUG] Added weather to context: ${environment['weather']}');
            }
          } else {
            AppLogger.warning('[AI_LOCATION_DEBUG] Location context service returned null');
          }
        } else {
          AppLogger.warning('[AI_LOCATION_DEBUG] No location points available in session state');
        }
      } catch (e) {
        AppLogger.error('[AI_LOCATION_DEBUG] Error in location processing: $e');
        AppLogger.error('[AI_LOCATION_DEBUG] Error type: ${e.runtimeType}');
        AppLogger.warning('[AI_LOCATION_DEBUG] Continuing without location context due to error');
        // Don't rethrow - continue without location context
      }
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 2 complete: Location context processed');

      // 3. Generate motivational text with OpenAI (LOCAL GENERATION ONLY)
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 3: Calling LOCAL OpenAI service...');
      AppLogger.info('[AI_CHEERLEADER_DEBUG] Using local OpenAI generation with full context');
      AppLogger.info('[AI_CHEERLEADER_DEBUG] Personality: $_aiCheerleaderPersonality, Explicit: $_aiCheerleaderExplicitContent');
      
      final messageStartTime = DateTime.now();
      String? message;
      try {
        // Use LOCAL OpenAI service with full context (session, weather, location, history)
        message = await _openAIService.generateMessage(
          context: context,
          personality: _aiCheerleaderPersonality!,
          explicitContent: _aiCheerleaderExplicitContent,
        );
        AppLogger.info('[AI_CHEERLEADER_DEBUG] Local OpenAI service returned: $message');
      } catch (e) {
        AppLogger.error('[AI_CHEERLEADER_DEBUG] Local OpenAI service failed: $e');
        message = null;
      }
      final messageEndTime = DateTime.now();
      final generationTimeMs = messageEndTime.difference(messageStartTime).inMilliseconds;
      
      AppLogger.warning('[AI_CHEERLEADER_DEBUG] Step 3 complete: OpenAI call finished');
      AppLogger.info('[AI_CHEERLEADER_DEBUG] Received message from OpenAI: $message');

      if (message != null && message.isNotEmpty) {
        AppLogger.info('[AI_CHEERLEADER] Generated message: "$message"');
        
        // 4. Synthesize speech with ElevenLabs
        final synthesisStartTime = DateTime.now();
        final audioBytes = await _elevenLabsService.synthesizeSpeech(
          text: message,
          personality: _aiCheerleaderPersonality!,
        );
        final synthesisEndTime = DateTime.now();
        final synthesisTimeMs = synthesisEndTime.difference(synthesisStartTime).inMilliseconds;
        final synthesisSuccess = audioBytes != null;

        if (audioBytes != null) {
          AppLogger.info('[AI_CHEERLEADER] Audio synthesized successfully');
          
          // 5. Play audio through audio service
          final playbackSuccess = await _audioService.playCheerleaderAudio(
            audioBytes: audioBytes,
            fallbackText: message,
            personality: _aiCheerleaderPersonality!,
          );
          
          if (playbackSuccess) {
            AppLogger.info('[AI_CHEERLEADER] Audio playback completed successfully');
          } else {
            AppLogger.warning('[AI_CHEERLEADER] Audio playback failed');
          }
        } else {
          AppLogger.warning('[AI_CHEERLEADER] Audio synthesis failed, skipping playback (TTS disabled)');
        }

        // 5. Log interaction to analytics
        try {
          final aiAnalyticsService = GetIt.instance<AIAnalyticsService>();
          await aiAnalyticsService.logInteraction(
            sessionId: state.sessionId,
            userId: _currentUser!.userId,
            personality: _aiCheerleaderPersonality!,
            triggerType: trigger.type.toString(),
            openaiPrompt: context.toString(),
            openaiResponse: message,
            elevenlabsVoiceId: _aiCheerleaderPersonality!,
            sessionContext: {
              'distance_km': state.distanceKm,
              'elapsed_seconds': state.elapsedSeconds,
              'pace': state.pace,
              'calories': state.calories,
              'elevation_gain': state.elevationGain,
              'is_paused': state.isPaused,
            },
            locationContext: context['environment']?['location'],
            triggerData: trigger.data,
            explicitContentEnabled: _aiCheerleaderExplicitContent,
            userGender: _currentUser!.gender,
            userPreferMetric: _currentUser!.preferMetric,
            generationTimeMs: generationTimeMs,
            synthesisSuccess: synthesisSuccess,
            synthesisTimeMs: synthesisTimeMs,
          );
          AppLogger.info('[AI_ANALYTICS] Interaction logged successfully for automatic trigger');
        } catch (e) {
          AppLogger.error('[AI_ANALYTICS] Failed to log automatic trigger interaction: $e');
        }
        // Return the generated message for optional UI display
        return message;

      } else {
        AppLogger.warning('[AI_CHEERLEADER] Text generation failed');
      }

      return null;

    } catch (e, stackTrace) {
      AppLogger.error('[AI_CHEERLEADER] Pipeline processing failed: $e');
      AppLogger.error('[AI_CHEERLEADER] Stack trace: $stackTrace');
      return null;
    }
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
    AppLogger.debug('Batch location update received: ${event.locationPoints.length} points');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for batch location update');
    }
  }

  Future<void> _onLocationUpdated(
    LocationUpdated event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.debug('Location update received: ${event.locationPoint}');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for location update');
    }
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
    AppLogger.debug('Processing batch upload for session: $sessionId');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      // Create a custom event for batch upload processing
      _coordinator!.add(SessionBatchUploadRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for batch upload');
    }
  }

  // Upload methods now handled by UploadManager

  Future<void> _onTick(Tick event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('[OLD_BLOC] Tick event received - main bloc is processing events');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for tick processing');
    }
  }

  Future<void> _onSessionPaused(
    SessionPaused event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('[OLD_BLOC] ===== SESSION PAUSE EVENT RECEIVED IN HANDLER =====');
    AppLogger.info('[OLD_BLOC] ===== SESSION PAUSE EVENT RECEIVED =====');
    AppLogger.info('[OLD_BLOC] Pausing session with delegation to coordinator');
    AppLogger.info('[OLD_BLOC] Coordinator exists: ${_coordinator != null}');
    AppLogger.info('[OLD_BLOC] Event source: ${event.source}');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.info('[OLD_BLOC] Delegating SessionPaused event to coordinator...');
      _coordinator!.add(event);
      AppLogger.info('[OLD_BLOC] SessionPaused event delegated successfully');
    } else {
      AppLogger.warning('[OLD_BLOC] No coordinator available for session pause');
      emit(ActiveSessionFailure(errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionResumed(
    SessionResumed event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.info('[OLD_BLOC] ===== SESSION RESUME EVENT RECEIVED =====');
    AppLogger.info('[OLD_BLOC] Resuming session with delegation to coordinator');
    AppLogger.info('[OLD_BLOC] Coordinator exists: ${_coordinator != null}');
    AppLogger.info('[OLD_BLOC] Event source: ${event.source}');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.info('[OLD_BLOC] Delegating SessionResumed event to coordinator...');
      _coordinator!.add(event);
      AppLogger.info('[OLD_BLOC] SessionResumed event delegated successfully');
    } else {
      AppLogger.warning('[OLD_BLOC] No coordinator available for session resume');
      emit(ActiveSessionFailure(errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionCompleted(
    SessionCompleted event, 
    Emitter<ActiveSessionState> emit
  ) async {
    print('🚀🚀🚀 MAIN BLOC SESSION COMPLETION STARTED 🚀🚀🚀');
    AppLogger.error('[OLD_BLOC] ===== MAIN BLOC SESSION COMPLETION STARTED =====');
    AppLogger.info('[OLD_BLOC] Session completion requested');
    AppLogger.info('[OLD_BLOC] Current state: ${state.runtimeType}');
    AppLogger.info('[OLD_BLOC] Session completed event: $event');
    AppLogger.error('[OLD_BLOC] Coordinator null check: _coordinator == null? ${_coordinator == null}');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.error('[OLD_BLOC] ===== DELEGATING TO COORDINATOR =====');
      AppLogger.info('[OLD_BLOC] Delegating to coordinator');
      _coordinator!.add(event);
      AppLogger.info('[OLD_BLOC] Event sent to coordinator, waiting for state update');
      AppLogger.error('[OLD_BLOC] ===== DELEGATION COMPLETE =====');
    } else {
      AppLogger.error('[OLD_BLOC] ===== NO COORDINATOR AVAILABLE =====');
      AppLogger.error('[OLD_BLOC] No coordinator available for session completion');
      emit(ActiveSessionFailure(errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionFailed(
    SessionFailed event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.error('Session failed with delegation to coordinator', exception: Exception(event.errorMessage));
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session failure');
      emit(ActiveSessionFailure(errorMessage: event.errorMessage, sessionDetails: null));
    }
  }

  // Heart rate monitoring start/stop is now handled by HeartRateManager
  Future<void> _startHeartRateMonitoring(String sessionId) async {
    AppLogger.debug('Starting heart rate monitoring through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(HeartRateMonitoringStartRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for heart rate monitoring start');
    }
  }

  Future<void> _stopHeartRateMonitoring() async {
    AppLogger.debug('Stopping heart rate monitoring through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(HeartRateMonitoringStopRequested());
    } else {
      AppLogger.warning('No coordinator available for heart rate monitoring stop');
    }
  }

  Future<void> _onHeartRateUpdated(
    HeartRateUpdated event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.debug('Heart rate updated: ${event.sample.bpm} bpm');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for heart rate update');
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
        // Delegate to coordinator for heart rate batch upload
        if (_coordinator != null) {
          _coordinator!.add(HeartRateBatchUploadRequested(samples: event.samples));
        } else {
          AppLogger.warning('No coordinator available for heart rate batch upload');
        }
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
    AppLogger.debug('Fetching session photos for ruck ID: ${event.ruckId}');
    
    try {
      // Fetch photos directly from the repository
      final photos = await _sessionRepository.getSessionPhotos(event.ruckId);
      
      // Emit SessionPhotosLoadedForId state so UI can listen for it
      emit(SessionPhotosLoadedForId(
        sessionId: event.ruckId.toString(),
        photos: photos,
      ));
      
      // Also update the current state with the fetched photos if it's a running session
      final currentState = state;
      if (currentState is ActiveSessionRunning) {
        emit(currentState.copyWith(photos: photos));
      }
      
      AppLogger.debug('Successfully fetched ${photos.length} photos for ruck ${event.ruckId}, emitted SessionPhotosLoadedForId state');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch session photos for ruck ${event.ruckId}', exception: e);
      
      // Log to Sentry for debugging
      await AppErrorHandler.handleError(
        'Fetch session photos',
        e,
        context: {
          'ruck_id': event.ruckId,
          'current_state': state.runtimeType.toString(),
          'stack_trace': stackTrace.toString(),
        },
        severity: ErrorSeverity.error,
      );
    }
  }

  Future<void> _onUploadSessionPhotosRequested(
      UploadSessionPhotosRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Uploading session photos through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for photo uploading, creating coordinator');
      
      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();
      
      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  Future<void> _onDeleteSessionPhotoRequested(
      DeleteSessionPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Deleting session photo through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for photo deletion, creating coordinator');
      
      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();
      
      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  void _onClearSessionPhotos(ClearSessionPhotos event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photos: []));
    }
  }

  Future<void> _onTakePhotoRequested(TakePhotoRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Taking photo through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for photo taking, creating coordinator');
      
      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();
      
      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  Future<void> _onPickPhotoRequested(PickPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Picking photo through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for photo picking, creating coordinator');
      
      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();
      
      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }
  
  Future<void> _onLoadSessionForViewing(LoadSessionForViewing event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Loading session for viewing through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      try {
        AppLogger.debug('Attempting to delegate LoadSessionForViewing to coordinator');
        _coordinator!.add(event);
      } catch (e) {
        AppLogger.error('Failed to delegate LoadSessionForViewing to coordinator: $e');
        // Fallback to prevent UI breakage
        emit(SessionSummaryGenerated(
          session: event.session,
          photos: event.session.photos ?? [],
          isPhotosLoading: false,
        ));
      }
    } else {
      AppLogger.warning('No coordinator available for session loading');
      // Fallback to prevent UI breakage
      emit(SessionSummaryGenerated(
        session: event.session,
        photos: event.session.photos ?? [],
        isPhotosLoading: false,
      ));
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
    AppLogger.debug('Requesting session recovery through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session recovery');
    }
  }

  Future<void> _onSessionReset(
    SessionReset event, 
    Emitter<ActiveSessionState> emit
  ) async {
    AppLogger.debug('Resetting session through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session reset');
      emit(const ActiveSessionInitial());
    }
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
      
      // Stop session completion detection monitoring
      _completionDetectionService.stopMonitoring();
      
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
    AppLogger.debug('Requesting session cleanup through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session cleanup');
    }
  }
  
  // Memory pressure handling is now managed by MemoryPressureManager

  // Offline session sync is now handled by UploadManager
  void _syncOfflineSessionsInBackground() {
    AppLogger.debug('Syncing offline sessions through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(OfflineSessionSyncRequested());
    } else {
      AppLogger.warning('No coordinator available for offline session sync');
    }
  }

  // Session completion payload building is now handled by SessionLifecycleManager
  Future<Map<String, dynamic>> _buildCompletionPayloadInBackground(
    ActiveSessionRunning currentState,
    Map<String, dynamic> terrainStats,
    List<LocationPoint> route,
    List<HeartRateSample> heartRateSamples,
  ) async {
    AppLogger.debug('Building completion payload through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(CompletionPayloadBuildRequested(
        currentState: currentState,
        terrainStats: terrainStats,
        route: route,
        heartRateSamples: heartRateSamples,
      ));
    } else {
      AppLogger.warning('No coordinator available for completion payload building');
    }
    return {}; // Placeholder - actual data will come through coordinator
  }

  // Connectivity monitoring is now handled by LocationTrackingManager
  void _startConnectivityMonitoring(String sessionId) {
    AppLogger.debug('Starting connectivity monitoring through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(ConnectivityMonitoringStartRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for connectivity monitoring');
    }
  }

  // Location tracking ensurance is now handled by LocationTrackingManager
  void _ensureLocationTrackingActive(String sessionId) {
    AppLogger.debug('Ensuring location tracking through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(LocationTrackingEnsureActiveRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for location tracking ensurance');
    }
  }

  // Offline session sync is now handled by UploadManager
  Future<void> _attemptOfflineSessionSync(String sessionId) async {
    AppLogger.debug('Attempting offline session sync through coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(OfflineSessionSyncAttemptRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for offline session sync attempt');
    }
  }
  
  // All diagnostic methods removed - now handled by managers
  
  Future<void> _onMemoryPressureDetected(
    MemoryPressureDetected event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.debug('Memory pressure detected, delegating to coordinator');
    
    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for memory pressure handling');
    }
  }
  
  /// Handle coordinator state forwarding
  void _onCoordinatorStateForwarded(
    _CoordinatorStateForwarded event,
    Emitter<ActiveSessionState> emit,
  ) {
    // Safely emit the coordinator state within an event handler context
    emit(event.state);
  }
  
  Future<void> _onCheckForCrashedSession(
    CheckForCrashedSession event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.info('Checking for crashed sessions on app startup');
    
    try {
      // Create coordinator if it doesn't exist to handle crash recovery
      if (_coordinator == null) {
        _coordinator = _createCoordinator();
        _setupCoordinatorSubscription();
      }
      
      // Delegate crash recovery check to coordinator
      // The coordinator will internally check with its SessionLifecycleManager
      _coordinator!.add(event);
      
      AppLogger.info('Crash recovery check delegated to coordinator');
      
    } catch (e) {
      AppLogger.error('Error during crash recovery check: $e');
      // Continue gracefully - not critical for app startup
    }
  }
  
  Future<void> _onSessionRecovered(SessionRecovered event, Emitter<ActiveSessionState> emit) async {
    // Just emit current state - coordinator handles the actual recovery
    emit(state);
  }
  
  // All diagnostic and memory pressure methods removed - now handled by dedicated managers
}

/// Internal event for safely forwarding coordinator states
class _CoordinatorStateForwarded extends ActiveSessionEvent {
  final ActiveSessionState state;
  
  const _CoordinatorStateForwarded(this.state);
  
  @override
  List<Object> get props => [state];
}
