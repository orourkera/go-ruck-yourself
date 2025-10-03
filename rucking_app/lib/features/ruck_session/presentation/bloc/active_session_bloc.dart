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
import 'package:rucking_app/core/services/auth_service_consolidated.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/services/terrain_tracker.dart';
import 'package:rucking_app/core/services/memory_monitor_service.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/services/session_completion_detection_service.dart';
import 'package:rucking_app/core/services/battery_optimization_service.dart';
import 'package:rucking_app/core/services/android_optimization_service.dart';
import 'package:rucking_app/core/services/connectivity_service.dart';
import 'package:rucking_app/core/services/device_performance_service.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/data/services/coaching_service.dart';
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
  final DevicePerformanceService _devicePerformanceService;
  final bool _skipLocationContextEnrichment;
  final bool _skipAIAudioPipeline;
  final int _cheerHistoryLimit;
  final double _aiCheerleaderMemorySoftLimitMb;
  final Duration _aiCheerleaderThrottleInterval;

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

  // AI Cheerleader caching + resource guardrails
  Map<String, dynamic>? _cachedCheerHistory;
  DateTime? _lastCheerHistoryFetch;
  Map<String, dynamic>? _cachedCoachingContext;
  DateTime? _lastCoachingContextFetch;
  DateTime? _lastAiMemorySkip;
  static const Duration _cheerHistoryCacheTtl = Duration(minutes: 10);
  static const Duration _coachingContextCacheTtl = Duration(minutes: 10);
  static const Duration _aiMemorySkipCooldown = Duration(minutes: 3);

  // Circuit breaker for AI failures
  int _aiCheerleaderFailureCount = 0;
  static const int _maxAiCheerleaderFailures = 5; // More lenient - was 3
  DateTime? _lastAiFailureTime;

  // Batch upload system for real-time data uploads during session
  Timer? _batchUploadTimer;
  static const Duration _batchUploadInterval = Duration(minutes: 5);
  DateTime? _lastBatchUploadTime;
  bool _isBatchUploadInProgress = false;

  // AI Cheerleader throttling to prevent blocking distance tracking
  DateTime? _lastAICheerleaderCheck;
  bool _isProcessingAICheerleader = false;

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
    required DevicePerformanceService devicePerformanceService,
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
        _devicePerformanceService = devicePerformanceService,
        _skipLocationContextEnrichment =
            devicePerformanceService.shouldSkipLocationContext,
        _skipAIAudioPipeline = devicePerformanceService.shouldSkipAIAudio,
        _cheerHistoryLimit = devicePerformanceService.cheerHistoryLimit,
        _aiCheerleaderMemorySoftLimitMb =
            devicePerformanceService.aiCheerleaderMemorySoftLimitMb,
        _aiCheerleaderThrottleInterval =
            devicePerformanceService.cheerleaderMinTriggerInterval,
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
    on<AICheerleaderManualTriggerRequested>(
        _onAICheerleaderManualTriggerRequested);
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

  void _resetAICaches() {
    _cachedCheerHistory = null;
    _cachedCoachingContext = null;
    _lastCheerHistoryFetch = null;
    _lastCoachingContextFetch = null;
    _lastAiMemorySkip = null;
  }

  void _logAiDebug(String message) {
    if (kDebugMode) {
      AppLogger.debug(message);
    }
  }

  Future<Map<String, dynamic>?> _loadCheerHistory() async {
    final now = DateTime.now();
    if (_cachedCheerHistory != null &&
        _lastCheerHistoryFetch != null &&
        now.difference(_lastCheerHistoryFetch!) < _cheerHistoryCacheTtl) {
      return _cachedCheerHistory;
    }

    try {
      final historyResp = await _apiClient.get(
        ApiEndpoints.aiCheerleaderLogs,
        queryParams: {
          'limit': _cheerHistoryLimit.toString(),
          'offset': '0',
        },
      );

      if (historyResp is Map<String, dynamic>) {
        _cachedCheerHistory = historyResp;
      } else {
        _cachedCheerHistory = null;
      }
    } catch (e) {
      _logAiDebug('[AI_CHEERLEADER_DEBUG] Failed to fetch history: $e');
      // Keep previously cached value (if any) without overriding
    } finally {
      _lastCheerHistoryFetch = now;
    }

    return _cachedCheerHistory;
  }

  Future<Map<String, dynamic>?> _loadCoachingPlanContext() async {
    final now = DateTime.now();
    if (_cachedCoachingContext != null &&
        _lastCoachingContextFetch != null &&
        now.difference(_lastCoachingContextFetch!) < _coachingContextCacheTtl) {
      return _cachedCoachingContext;
    }

    try {
      final coachingService = GetIt.instance<CoachingService>();
      final plan = await coachingService.getActiveCoachingPlan();
      Map<String, dynamic>? context;

      if (plan != null) {
        final progressResponse =
            await coachingService.getCoachingPlanProgress();
        final progress = progressResponse['progress'] is Map
            ? Map<String, dynamic>.from(progressResponse['progress'])
            : null;
        final nextSession = progressResponse['next_session'] is Map
            ? Map<String, dynamic>.from(progressResponse['next_session'])
            : null;

        context = coachingService.buildAIPlanContext(
          plan: plan,
          progress: progress,
          nextSession: nextSession,
        );
      } else {
        context = null;
      }

      _cachedCoachingContext = context;
    } catch (e) {
      _logAiDebug('[AI_CHEERLEADER_DEBUG] Failed to fetch coaching plan: $e');
      // Preserve previous cached context if available
    } finally {
      _lastCoachingContextFetch = now;
    }

    return _cachedCoachingContext;
  }

  Future<void> _onSessionStarted(
      SessionStarted event, Emitter<ActiveSessionState> emit) async {
    AppLogger.info('Starting session with delegation to coordinator');

    try {
      // Capture AI Cheerleader parameters
      _aiCheerleaderEnabled = event.aiCheerleaderEnabled;
      _aiCheerleaderPersonality = event.aiCheerleaderPersonality;
      _aiCheerleaderExplicitContent = event.aiCheerleaderExplicitContent;
      _resetAICaches();

      // Reset AI Cheerleader service for new session
      if (_aiCheerleaderEnabled) {
        _aiCheerleaderService.reset();
        AppLogger.info(
            'AI Cheerleader enabled: $_aiCheerleaderPersonality (explicit: $_aiCheerleaderExplicitContent)');

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
        // CRITICAL: Wrap in try-catch to prevent ANY error from killing the coordinator stream
        try {
          // Forward coordinator state as an internal event instead of calling emit directly
          // This prevents "emit after event handler completed" errors
          _onCoordinatorStateChanged(coordinatorState);
        } catch (e, stack) {
          AppLogger.error(
              '[CRITICAL] Error in coordinator state handler (GPS continues): $e');
          AppLogger.error('[CRITICAL] Stack: $stack');
          // DO NOT rethrow - this would kill the coordinator stream and stop GPS updates
          // The session continues even if AI cheerleader or other features fail
        }
      },
      onError: (error) {
        AppLogger.error('[COORDINATOR] Stream error: $error');

        // Attempt to recover coordinator instead of failing the session
        try {
          // Log the error but try to maintain session state
          if (state is ActiveSessionRunning) {
            final runningState = state as ActiveSessionRunning;
            AppLogger.warning(
                '[COORDINATOR] Maintaining session state despite coordinator error');

            // Try to restart coordinator if it's completely failed
            if (_coordinator?.isClosed == true) {
              AppLogger.info(
                  '[COORDINATOR] Restarting coordinator due to critical failure');
              _restartCoordinator();
            }
          }
        } catch (recoveryError) {
          AppLogger.error('[COORDINATOR] Recovery failed: $recoveryError');
          // Only as last resort, report to Sentry but don't kill the session
          AppErrorHandler.handleError(
            'coordinator_recovery_failed',
            recoveryError,
            severity: ErrorSeverity.error,
          );
        }
      },
      cancelOnError: false, // CRITICAL: Don't cancel subscription on errors
    );
  }

  /// Restart coordinator after critical failure to maintain session continuity
  void _restartCoordinator() {
    try {
      AppLogger.info('[COORDINATOR] Attempting to restart coordinator');

      // Cancel existing subscription
      _coordinatorSubscription?.cancel();

      // Create new coordinator instance
      _coordinator = ActiveSessionCoordinator(
        sessionRepository: _sessionRepository,
        locationService: _locationService,
        authService: GetIt.instance<AuthService>(),
        watchService: _watchService,
        storageService: GetIt.instance<StorageService>(),
        apiClient: _apiClient,
        connectivityService: _connectivityService,
        splitTrackingService: _splitTrackingService,
        terrainTracker: _terrainTracker,
        heartRateService: _heartRateService,
        openAIService: _openAIService,
      );

      // Re-establish subscription with enhanced error handling
      _coordinatorSubscription = _coordinator!.stream.listen(
        (coordinatorState) {
          if (!isClosed) {
            add(_CoordinatorStateForwarded(coordinatorState));
          }
        },
        onError: (error) {
          AppLogger.error('[COORDINATOR] Restarted coordinator error: $error');
          // Prevent infinite restart loops
          AppErrorHandler.handleError(
            'coordinator_restart_error',
            error,
            severity: ErrorSeverity.warning,
          );
        },
        cancelOnError: false,
      );

      // If we have a running session, forward the current state to restart tracking
      if (state is ActiveSessionRunning) {
        final runningState = state as ActiveSessionRunning;
        AppLogger.info(
            '[COORDINATOR] Re-initializing session tracking after restart');

        // Forward session start event to reactivate tracking
        _coordinator!.add(SessionStarted(
          ruckWeightKg: runningState.ruckWeightKg,
          userWeightKg: runningState.userWeightKg,
          notes: runningState.notes,
          sessionId: runningState.sessionId,
          aiCheerleaderEnabled: _aiCheerleaderEnabled,
          aiCheerleaderPersonality: _aiCheerleaderPersonality,
          aiCheerleaderExplicitContent: _aiCheerleaderExplicitContent,
        ));
      }

      AppLogger.info('[COORDINATOR] Successfully restarted coordinator');
    } catch (e) {
      AppLogger.error('[COORDINATOR] Failed to restart coordinator: $e');
      AppErrorHandler.handleError(
        'coordinator_restart_failed',
        e,
        severity: ErrorSeverity.error,
      );
    }
  }

  /// Handle state changes from the coordinator
  void _onCoordinatorStateChanged(ActiveSessionState coordinatorState) {
    // CRITICAL: Wrap each feature in try-catch to prevent cascading failures

    // Handle completion detection service lifecycle
    try {
      _handleCompletionDetectionServiceLifecycle(coordinatorState);
    } catch (e) {
      AppLogger.error('[COMPLETION_DETECTION] Error handling lifecycle: $e');
      // Continue - don't let this break the session
    }

    // Check for AI Cheerleader triggers if enabled and session is running
    // CRITICAL: This must NEVER crash the coordinator stream
    if (_aiCheerleaderEnabled &&
        coordinatorState is ActiveSessionRunning &&
        _aiCheerleaderPersonality != null &&
        _currentUser != null) {
      // Throttle AI cheerleader checks to prevent blocking distance tracking
      final now = DateTime.now();
      if (_lastAICheerleaderCheck != null &&
          now.difference(_lastAICheerleaderCheck!).inSeconds <
              _aiCheerleaderThrottleInterval.inSeconds) {
        // Skip this check - too soon since last check
        // CRITICAL: Don't return here - still need to forward the state!
        // Just skip the AI processing
      } else if (_isProcessingAICheerleader) {
        // Skip if already processing to prevent overlapping operations
        // CRITICAL: Don't return here - still need to forward the state!
      } else {
        _lastAICheerleaderCheck = now;

        _logAiDebug(
            'Checking AI triggers (enabled=$_aiCheerleaderEnabled personality=$_aiCheerleaderPersonality user=${_currentUser?.username})');

        // Fire and forget with complete isolation
        Future.microtask(() async {
          _isProcessingAICheerleader = true;
          try {
            await _checkAICheerleaderTriggers(coordinatorState);
          } catch (e, stack) {
            AppLogger.error(
                '[AI_CHEERLEADER] Isolated trigger check failed: $e');
            AppLogger.error('[AI_CHEERLEADER] Stack: $stack');
            // Log to Sentry but don't crash the session
            await _reportAICheerleaderIssue(
              'ai_cheerleader_trigger_async_failure',
              e,
              state: coordinatorState is ActiveSessionRunning
                  ? coordinatorState
                  : null,
              extraContext: {
                'stack_trace': stack.toString(),
                'coordinator_state': coordinatorState.runtimeType.toString(),
              },
              severity: ErrorSeverity.error,
            );
          } finally {
            _isProcessingAICheerleader = false;
          }
        });
      }
    } else {
      _logAiDebug(
          'AI triggers skipped (enabled=$_aiCheerleaderEnabled running=${coordinatorState is ActiveSessionRunning} personality=$_aiCheerleaderPersonality user=${_currentUser?.username})');
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
          AppLogger.info(
              '[SESSION_COMPLETION] Starting completion detection monitoring');
          _completionDetectionService.startMonitoring();

          // Update heart rate data if available
          if (state.latestHeartRate != null) {
            // Calculate average heart rate from samples
            double? workoutAverage;
            if (state.heartRateSamples.isNotEmpty) {
              final totalHr = state.heartRateSamples
                  .fold<double>(0, (sum, sample) => sum + sample.bpm);
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
          AppLogger.info(
              '[SESSION_COMPLETION] Stopping completion detection monitoring');
          _completionDetectionService.stopMonitoring();
        }
      }
    } catch (e) {
      AppLogger.error(
          '[SESSION_COMPLETION] Error managing detection service lifecycle: $e');
    }
  }

  /// Check for AI Cheerleader triggers and process them
  Future<void> _checkAICheerleaderTriggers(ActiveSessionRunning state) async {
    try {
      final now = DateTime.now();

      // Reset failure count if it's been more than 5 minutes since last failure
      if (_lastAiFailureTime != null &&
          now.difference(_lastAiFailureTime!).inMinutes > 5 &&
          _aiCheerleaderFailureCount > 0) {
        _logAiDebug('Resetting AI cheerleader failure count after cooldown');
        _aiCheerleaderFailureCount = 0;
      }

      // Check memory usage before processing AI cheerleader
      try {
        final memoryInfo = MemoryMonitorService.getCurrentMemoryInfo();
        final memoryUsageMb = memoryInfo['memory_usage_mb'] as double;

        if (memoryUsageMb > _aiCheerleaderMemorySoftLimitMb) {
          if (_lastAiMemorySkip == null ||
              now.difference(_lastAiMemorySkip!) > _aiMemorySkipCooldown) {
            AppLogger.warning(
              '[AI_CHEERLEADER] Skipping cheer trigger due to high memory usage: ${memoryUsageMb.toStringAsFixed(1)}MB',
            );
            await _reportAICheerleaderIssue(
              'ai_cheerleader_memory_skip',
              Exception(
                  'AI cheerleader skipped due to high memory usage: ${memoryUsageMb.toStringAsFixed(1)}MB'),
              state: state,
              extraContext: {
                'memory_usage_mb': memoryUsageMb,
                'memory_soft_limit_mb': _aiCheerleaderMemorySoftLimitMb,
              },
              severity: ErrorSeverity.warning,
            );
            _lastAiMemorySkip = now;
          }
          return;
        }

        _lastAiMemorySkip = null;
        _logAiDebug(
            'AI cheerleader memory check: ${memoryUsageMb.toStringAsFixed(1)}MB');
      } catch (e) {
        _logAiDebug('AI cheerleader memory check failed: $e');
      }

      _logAiDebug(
          'Analyzing AI triggers distance=${state.distanceKm}km time=${state.elapsedSeconds}s');
      final trigger = _aiCheerleaderService.analyzeTriggers(
        state,
        preferMetric: _currentUser!.preferMetric,
      );
      _logAiDebug('Trigger result: ${trigger?.type.name ?? 'none'}');
      if (trigger != null) {
        await _processAICheerleaderTrigger(trigger, state);
      } else {
        // No trigger debug logging removed for performance (very frequent)
        // AppLogger.info('[AI_DEBUG] No trigger detected this cycle');
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
    _logAiDebug('Manual AI cheerleader trigger requested');
    _logAiDebug(
        'AI enabled: $_aiCheerleaderEnabled, personality: $_aiCheerleaderPersonality');

    if (!_aiCheerleaderEnabled ||
        _aiCheerleaderPersonality == null ||
        _currentUser == null ||
        state is! ActiveSessionRunning) {
      AppLogger.warning(
          '[AI_CHEERLEADER] Manual trigger rejected – missing prerequisites');
      return;
    }

    final runningState = state as ActiveSessionRunning;
    _logAiDebug(
        'Manual trigger proceeding elapsed=${runningState.elapsedSeconds}s distance=${runningState.distanceKm}km');

    // Create a special manual trigger with current session context
    final manualTrigger = CheerleaderTrigger(
      type: TriggerType.manualRequest,
      data: {
        'elapsedMinutes': runningState.elapsedSeconds ~/ 60,
        'distanceKm': runningState.distanceKm,
        'manualRequest': true,
      },
    );

    final generatedMessage =
        await _processAICheerleaderTrigger(manualTrigger, runningState);

    // Emit UI-visible message if available
    if (generatedMessage != null && generatedMessage.isNotEmpty) {
      // AI message emission debug logging reduced for performance
      // AppLogger.info('[AI_CHEERLEADER_UI] Emitting AI cheer message to UI');
      emit(runningState.copyWith(aiCheerMessage: generatedMessage));
    } else {
      _logAiDebug('Manual trigger produced no message');
    }
  }

  /// Process AI Cheerleader trigger through the full pipeline
  Future<String?> _processAICheerleaderTrigger(
      CheerleaderTrigger trigger, ActiveSessionRunning state) async {
    try {
      _logAiDebug('AI cheerleader trigger ${trigger.type.name} started');

      // 1. Fetch historical user data for richer AI context
      final history = await _loadCheerHistory();

      // 2. Fetch coaching plan data for AI context
      final coachingPlan = await _loadCoachingPlanContext();

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
      _logAiDebug('Context assembled for trigger ${trigger.type.name}');

      // Normalize environment to Map<String, dynamic> to avoid Map<String, String> inference downstream
      final envRawBefore = context['environment'];
      final Map<String, dynamic> normalizedEnv = (envRawBefore is Map)
          ? Map<String, dynamic>.from(envRawBefore as Map)
          : <String, dynamic>{};
      context['environment'] = normalizedEnv;

      // 2. Add location context if available
      if (!_skipLocationContextEnrichment) {
        _logAiDebug('Attempting to enrich location context');

        try {
          // SAFETY: Check if locationPoints exists and is accessible
          final pointsCount = state.locationPoints?.length ?? 0;
          AppLogger.warning(
              '[AI_LOCATION_DEBUG] Location points available: $pointsCount');
          AppLogger.warning(
              '[AI_LOCATION_DEBUG] Location points type: ${state.locationPoints?.runtimeType ?? "null"}');

          AppLogger.warning(
              '[AI_LOCATION_DEBUG] About to check if locationPoints is not empty...');
          final lastLocation =
              (state.locationPoints != null && state.locationPoints.isNotEmpty)
                  ? state.locationPoints.last
                  : null;
          if (lastLocation != null) {
            final locationContext = await _locationContextService
                .getLocationContext(
                  lastLocation.latitude,
                  lastLocation.longitude,
                )
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => null,
                );

            if (locationContext != null) {
              final environment =
                  (context['environment'] as Map<String, dynamic>?) ??
                      <String, dynamic>{};
              final locationSummary = {
                'description': locationContext.description,
                'city': locationContext.city,
                'terrain': locationContext.terrain,
                'landmark': locationContext.landmark,
                'weatherCondition': locationContext.weatherCondition,
                'temperature': locationContext.temperature,
              };
              locationSummary.removeWhere((key, value) =>
                  value == null || (value is String && value.isEmpty));
              if (locationSummary.isNotEmpty) {
                environment['location'] = locationSummary;
              }

              final weatherMap = <String, dynamic>{};
              final tempF = locationContext.temperature;
              if (tempF != null) {
                weatherMap['tempF'] = tempF;
              }
              final condition = locationContext.weatherCondition;
              if (condition != null && condition.isNotEmpty) {
                weatherMap['condition'] = condition;
              }
              if (weatherMap.isNotEmpty) {
                environment['weather'] = weatherMap;
              }

              context['environment'] = environment;
              _logAiDebug('Location context added to AI environment');
            }
          }
        } catch (e) {
          AppLogger.error(
              '[AI_LOCATION_DEBUG] Error in location processing: $e');
        }
      } else {
        _logAiDebug('Skipping location context enrichment (low-spec device)');
      }
      _logAiDebug('AI environment prepared for OpenAI generation');

      final messageStartTime = DateTime.now();
      String? message;
      try {
        // Use LOCAL OpenAI service with full context (session, weather, location, history)
        message = await _openAIService.generateMessage(
          context: context,
          personality: _aiCheerleaderPersonality!,
          explicitContent: _aiCheerleaderExplicitContent,
        );
        _logAiDebug('OpenAI generated message: $message');
      } catch (e) {
        AppLogger.error(
            '[AI_CHEERLEADER_DEBUG] Local OpenAI service failed: $e');
        message = null;
      }
      final messageEndTime = DateTime.now();
      final generationTimeMs =
          messageEndTime.difference(messageStartTime).inMilliseconds;

      if (message != null && message.isNotEmpty) {
        _logAiDebug('AI cheerleader message ready for playback');

        // 4. Synthesize speech with ElevenLabs
        Uint8List? audioBytes;
        int? synthesisTimeMs;
        bool synthesisSuccess = false;

        if (!_skipAIAudioPipeline) {
          final synthesisStartTime = DateTime.now();
          audioBytes = await _elevenLabsService.synthesizeSpeech(
            text: message,
            personality: _aiCheerleaderPersonality!,
          );
          final synthesisEndTime = DateTime.now();
          synthesisTimeMs =
              synthesisEndTime.difference(synthesisStartTime).inMilliseconds;
          synthesisSuccess = audioBytes != null;

          if (audioBytes != null) {
            _logAiDebug('ElevenLabs synthesis succeeded');

            // 5. Play audio through audio service
            final playbackSuccess = await _audioService.playCheerleaderAudio(
              audioBytes: audioBytes,
              fallbackText: message,
              personality: _aiCheerleaderPersonality!,
            );

            if (playbackSuccess) {
              _logAiDebug('Cheerleader audio playback finished');
            } else {
              AppLogger.warning('[AI_CHEERLEADER] Audio playback failed');
              await _reportAICheerleaderIssue(
                'ai_cheerleader_audio_playback_failed',
                Exception('AI cheerleader audio playback failed'),
                state: state,
                trigger: trigger,
                extraContext: {
                  'personality': _aiCheerleaderPersonality,
                  'synthesis_time_ms': synthesisTimeMs,
                },
                severity: ErrorSeverity.warning,
              );
            }
          } else {
            AppLogger.warning(
                '[AI_CHEERLEADER] Audio synthesis failed, skipping playback (TTS disabled)');
            await _reportAICheerleaderIssue(
              'ai_cheerleader_audio_synthesis_failed',
              Exception('AI cheerleader audio synthesis returned null bytes'),
              state: state,
              trigger: trigger,
              extraContext: {
                'personality': _aiCheerleaderPersonality,
              },
              severity: ErrorSeverity.warning,
            );
          }
        } else {
          _logAiDebug('Skipping audio synthesis/playback on low-spec device');
        }

        // 5. Log interaction to analytics
        try {
          final aiAnalyticsService = GetIt.instance<AIAnalyticsService>();
          final triggerCtx = context['trigger'] is Map
              ? Map<String, dynamic>.from(context['trigger'] as Map)
              : {
                  'type': trigger.type.name,
                  'data': trigger.data,
                };
          final sessionCtx = context['session'] is Map
              ? Map<String, dynamic>.from(context['session'] as Map)
              : <String, dynamic>{};
          final distanceCtx = sessionCtx['distance'] is Map
              ? Map<String, dynamic>.from(sessionCtx['distance'] as Map)
              : <String, dynamic>{};
          final elapsedCtx = sessionCtx['elapsedTime'] is Map
              ? Map<String, dynamic>.from(sessionCtx['elapsedTime'] as Map)
              : <String, dynamic>{};
          final promptSummary = jsonEncode({
            'trigger': triggerCtx,
            'distance': distanceCtx['primaryValue'],
            'elapsed_seconds': elapsedCtx['elapsedSeconds'],
            'personality': _aiCheerleaderPersonality,
          });

          await aiAnalyticsService.logInteraction(
            sessionId: state.sessionId,
            userId: _currentUser!.userId,
            personality: _aiCheerleaderPersonality!,
            triggerType: trigger.type.toString(),
            openaiPrompt: promptSummary,
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
          _logAiDebug('AI analytics interaction logged');
        } catch (e) {
          AppLogger.error(
              '[AI_ANALYTICS] Failed to log automatic trigger interaction: $e');
          await _reportAICheerleaderIssue(
            'ai_cheerleader_analytics_logging_failed',
            e,
            state: state,
            trigger: trigger,
            extraContext: {
              'generation_time_ms': generationTimeMs,
              'synthesis_success': synthesisSuccess,
              'synthesis_time_ms': synthesisTimeMs,
            },
            severity: ErrorSeverity.warning,
          );
        }
        _aiCheerleaderFailureCount = 0;
        // Return the generated message for optional UI display
        return message;
      } else {
        AppLogger.warning('[AI_CHEERLEADER] Text generation failed');
        await _reportAICheerleaderIssue(
          'ai_cheerleader_empty_response',
          Exception('AI cheerleader returned an empty response'),
          state: state,
          trigger: trigger,
          extraContext: {
            'context_char_count': context.length,
            'generation_time_ms': generationTimeMs,
          },
          severity: ErrorSeverity.warning,
        );
      }

      return null;
    } catch (e, stackTrace) {
      // Increment failure count and track time
      _aiCheerleaderFailureCount++;
      _lastAiFailureTime = DateTime.now();

      // Check if we've exceeded the failure threshold
      if (_aiCheerleaderFailureCount >= _maxAiCheerleaderFailures) {
        AppLogger.warning(
            '[AI_CHEERLEADER] Circuit breaker triggered - disabling AI after $_aiCheerleaderFailureCount failures');
        _aiCheerleaderEnabled = false;
        await _reportAICheerleaderIssue(
          'ai_cheerleader_circuit_breaker_triggered',
          Exception(
              'AI cheerleader circuit breaker triggered after $_aiCheerleaderFailureCount failures'),
          state: state,
          trigger: trigger,
          extraContext: {
            'last_error': e.toString(),
          },
          severity: ErrorSeverity.error,
        );

        // Clean up audio resources
        try {
          await _audioService.stop();
          await _audioService.dispose();
        } catch (cleanupError) {
          AppLogger.error(
              '[AI_CHEERLEADER] Failed to clean up audio service: $cleanupError');
        }
      }

      AppLogger.error(
          '[AI_CHEERLEADER] Pipeline processing failed ($_aiCheerleaderFailureCount/$_maxAiCheerleaderFailures): $e');
      AppLogger.error('[AI_CHEERLEADER] Stack trace: $stackTrace');
      await _reportAICheerleaderIssue(
        'ai_cheerleader_pipeline_exception',
        e,
        state: state,
        trigger: trigger,
        extraContext: {
          'stack_trace': stackTrace.toString(),
          'failure_count': _aiCheerleaderFailureCount,
        },
        severity: ErrorSeverity.error,
      );
      return null;
    }
  }

  Future<void> _reportAICheerleaderIssue(
    String operation,
    dynamic error, {
    ActiveSessionRunning? state,
    CheerleaderTrigger? trigger,
    Map<String, dynamic>? extraContext,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    try {
      final context = _buildAICheerleaderSentryContext(
        state: state,
        trigger: trigger,
        extra: extraContext,
      );
      await AppErrorHandler.handleError(
        operation,
        error,
        context: context,
        userId: _currentUser?.userId,
        severity: severity,
      );
    } catch (loggingError) {
      AppLogger.error(
          '[AI_CHEERLEADER] Failed to report issue ($operation): $loggingError');
    }
  }

  Map<String, String> _buildAICheerleaderSentryContext({
    ActiveSessionRunning? state,
    CheerleaderTrigger? trigger,
    Map<String, dynamic>? extra,
  }) {
    final memoryInfo = MemoryMonitorService.getCurrentMemoryInfo();

    String stringify(dynamic value) {
      if (value == null) return 'null';
      if (value is double) {
        if (value.isNaN) return 'NaN';
        return value.toStringAsFixed(3);
      }
      return value.toString();
    }

    final context = <String, String>{
      'session_id': state?.sessionId ?? 'unknown',
      'session_distance_km':
          state != null ? stringify(state.distanceKm) : 'null',
      'session_elapsed_seconds':
          state != null ? stringify(state.elapsedSeconds) : 'null',
      'ai_enabled': _aiCheerleaderEnabled.toString(),
      'ai_failure_count': _aiCheerleaderFailureCount.toString(),
      'ai_personality': _aiCheerleaderPersonality ?? 'unknown',
      'ai_explicit_content': _aiCheerleaderExplicitContent.toString(),
      'ai_trigger_type': trigger?.type.name ?? 'unknown',
      'ai_trigger_data': trigger?.data?.toString() ?? 'null',
      'device_low_spec': _devicePerformanceService.isLowSpecDevice.toString(),
      'device_android_sdk':
          _devicePerformanceService.androidSdkInt?.toString() ?? 'null',
      'device_ios_version':
          _devicePerformanceService.iosSystemVersion ?? 'null',
      'memory_usage_mb': stringify(memoryInfo['memory_usage_mb']),
      'memory_soft_limit_mb': stringify(_aiCheerleaderMemorySoftLimitMb),
      'throttle_interval_seconds':
          _aiCheerleaderThrottleInterval.inSeconds.toString(),
      'history_cached': (_cachedCheerHistory != null).toString(),
      'coaching_cached': (_cachedCoachingContext != null).toString(),
      'skip_location_context': _skipLocationContextEnrichment.toString(),
      'skip_ai_audio': _skipAIAudioPipeline.toString(),
    };

    if (extra != null) {
      extra.forEach((key, value) {
        context['extra_$key'] = stringify(value);
      });
    }

    return context;
  }

  void _startLocationUpdates(String sessionId) {
    _locationSubscription?.cancel();
    _batchLocationSubscription?.cancel();

    _locationSubscription = _locationService.startLocationTracking().listen(
      (locationPoint) {
        add(LocationUpdated(locationPoint));
        _lastLocationTimestamp =
            DateTime.now(); // Update last location timestamp
      },
      onError: (error) {
        AppLogger.warning(
            'Location tracking error (continuing session without GPS): $error');
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
        AppLogger.warning(
            'Batch location tracking error (continuing session without GPS): $error');
        // Don't stop the session - continue in offline mode without location updates
        // This allows users to ruck indoors, on airplanes, or in poor GPS areas
      },
    );

    AppLogger.debug('Location tracking started for session $sessionId.');
  }

  Future<void> _onBatchLocationUpdated(
      BatchLocationUpdated event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug(
        'Batch location update received: ${event.locationPoints.length} points');

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
  Future<void> _processBatchLocationUpload(
      String sessionId, List<LocationPoint> locationPoints) async {
    AppLogger.info(
        'Uploading batch of ${locationPoints.length} location points');

    final locationData = locationPoints.map((point) => point.toJson()).toList();

    try {
      await _apiClient.addLocationPoints(sessionId, locationData);
      AppLogger.info(
          'Successfully uploaded ${locationPoints.length} location points');
    } catch (e) {
      if (e.toString().contains('401') ||
          e.toString().contains('Already Used')) {
        AppLogger.warning(
            '[SESSION_RECOVERY] Location batch sync failed due to auth issue, will retry: $e');
        // Don't kill the session - continue tracking locally
      } else {
        AppLogger.warning('Failed to send location batch to backend: $e');
      }
    }
  }

  Future<void> _onTimerStarted(
      TimerStarted event, Emitter<ActiveSessionState> emit) async {
    // Timers are coordinated by SessionLifecycleManager's TimerCoordinator.
    // Avoid starting redundant bloc-level timers to reduce wakeups and crashes on older devices.
    AppLogger.debug(
        '[SESSION] Skipping bloc timers; TimerCoordinator manages ticks/watchdog/persistence/uploads');
  }

  void _stopTickerAndWatchdog() {
    _ticker?.cancel();
    _ticker = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _sessionPersistenceTimer?.cancel();
    _sessionPersistenceTimer = null;
    _batchUploadTimer?.cancel();
    _batchUploadTimer = null;
    AppLogger.debug(
        'Master timer, watchdog, session persistence, and batch upload timers stopped.');
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
    AppLogger.info(
        'Batch upload timer started - uploading data every ${_batchUploadInterval.inMinutes} minutes');
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
    AppLogger.debug(
        '[OLD_BLOC] Tick event received - main bloc is processing events');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for tick processing');
    }
  }

  Future<void> _onSessionPaused(
      SessionPaused event, Emitter<ActiveSessionState> emit) async {
    AppLogger.info(
        '[OLD_BLOC] ===== SESSION PAUSE EVENT RECEIVED IN HANDLER =====');
    AppLogger.info('[OLD_BLOC] ===== SESSION PAUSE EVENT RECEIVED =====');
    AppLogger.info('[OLD_BLOC] Pausing session with delegation to coordinator');
    AppLogger.info('[OLD_BLOC] Coordinator exists: ${_coordinator != null}');
    AppLogger.info('[OLD_BLOC] Event source: ${event.source}');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.info(
          '[OLD_BLOC] Delegating SessionPaused event to coordinator...');
      _coordinator!.add(event);
      AppLogger.info('[OLD_BLOC] SessionPaused event delegated successfully');
    } else {
      AppLogger.warning(
          '[OLD_BLOC] No coordinator available for session pause');
      emit(ActiveSessionFailure(
          errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionResumed(
      SessionResumed event, Emitter<ActiveSessionState> emit) async {
    AppLogger.info('[OLD_BLOC] ===== SESSION RESUME EVENT RECEIVED =====');
    AppLogger.info(
        '[OLD_BLOC] Resuming session with delegation to coordinator');
    AppLogger.info('[OLD_BLOC] Coordinator exists: ${_coordinator != null}');
    AppLogger.info('[OLD_BLOC] Event source: ${event.source}');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.info(
          '[OLD_BLOC] Delegating SessionResumed event to coordinator...');
      _coordinator!.add(event);
      AppLogger.info('[OLD_BLOC] SessionResumed event delegated successfully');
    } else {
      AppLogger.warning(
          '[OLD_BLOC] No coordinator available for session resume');
      emit(ActiveSessionFailure(
          errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionCompleted(
      SessionCompleted event, Emitter<ActiveSessionState> emit) async {
    print('🚀🚀🚀 MAIN BLOC SESSION COMPLETION STARTED 🚀🚀🚀');
    AppLogger.error(
        '[OLD_BLOC] ===== MAIN BLOC SESSION COMPLETION STARTED =====');
    AppLogger.info('[OLD_BLOC] Session completion requested');
    AppLogger.info('[OLD_BLOC] Current state: ${state.runtimeType}');
    AppLogger.info('[OLD_BLOC] Session completed event: $event');
    AppLogger.error(
        '[OLD_BLOC] Coordinator null check: _coordinator == null? ${_coordinator == null}');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      AppLogger.error('[OLD_BLOC] ===== DELEGATING TO COORDINATOR =====');
      AppLogger.info('[OLD_BLOC] Delegating to coordinator');
      _coordinator!.add(event);
      AppLogger.info(
          '[OLD_BLOC] Event sent to coordinator, waiting for state update');
      AppLogger.error('[OLD_BLOC] ===== DELEGATION COMPLETE =====');
    } else {
      AppLogger.error('[OLD_BLOC] ===== NO COORDINATOR AVAILABLE =====');
      AppLogger.error(
          '[OLD_BLOC] No coordinator available for session completion');
      emit(ActiveSessionFailure(
          errorMessage: 'Session coordinator not initialized'));
    }
  }

  Future<void> _onSessionFailed(
    SessionFailed event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.error('Session failed with delegation to coordinator',
        exception: Exception(event.errorMessage));

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for session failure');
      emit(ActiveSessionFailure(
          errorMessage: event.errorMessage, sessionDetails: null));
    }
  }

  // Heart rate monitoring start/stop is now handled by HeartRateManager
  Future<void> _startHeartRateMonitoring(String sessionId) async {
    AppLogger.debug('Starting heart rate monitoring through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!
          .add(HeartRateMonitoringStartRequested(sessionId: sessionId));
    } else {
      AppLogger.warning(
          'No coordinator available for heart rate monitoring start');
    }
  }

  Future<void> _stopHeartRateMonitoring() async {
    AppLogger.debug('Stopping heart rate monitoring through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(HeartRateMonitoringStopRequested());
    } else {
      AppLogger.warning(
          'No coordinator available for heart rate monitoring stop');
    }
  }

  Future<void> _onHeartRateUpdated(
      HeartRateUpdated event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Heart rate updated: ${event.sample.bpm} bpm');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning('No coordinator available for heart rate update');
    }
  }

  Future<void> _onHeartRateBufferProcessed(
      HeartRateBufferProcessed event, Emitter<ActiveSessionState> emit) async {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;

      // Apply the same 30-second throttling to API uploads as we do for local storage
      final now = DateTime.now();
      final shouldSendToApi = _lastApiHeartRateTime == null ||
          now.difference(_lastApiHeartRateTime!).inSeconds >= 30;

      if (shouldSendToApi) {
        // Delegate to coordinator for heart rate batch upload
        if (_coordinator != null) {
          _coordinator!
              .add(HeartRateBatchUploadRequested(samples: event.samples));
        } else {
          AppLogger.warning(
              'No coordinator available for heart rate batch upload');
        }
        _lastApiHeartRateTime = now;
      } else {
        AppLogger.debug(
            '[HR_API_THROTTLE] Skipped sending ${event.samples.length} heart rate samples to API (throttled)');
      }
      // Optionally emit state if UI needs to reflect that a batch was sent, though usually not needed.
    }
  }

  // Heart rate API calls now handled by HeartRateManager

  Future<void> _onFetchSessionPhotosRequested(FetchSessionPhotosRequested event,
      Emitter<ActiveSessionState> emit) async {
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

      AppLogger.debug(
          'Successfully fetched ${photos.length} photos for ruck ${event.ruckId}, emitted SessionPhotosLoadedForId state');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch session photos for ruck ${event.ruckId}',
          exception: e);

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
      UploadSessionPhotosRequested event,
      Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Uploading session photos through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning(
          'No coordinator available for photo uploading, creating coordinator');

      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();

      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  Future<void> _onDeleteSessionPhotoRequested(DeleteSessionPhotoRequested event,
      Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Deleting session photo through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning(
          'No coordinator available for photo deletion, creating coordinator');

      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();

      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  void _onClearSessionPhotos(
      ClearSessionPhotos event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photos: []));
    }
  }

  Future<void> _onTakePhotoRequested(
      TakePhotoRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Taking photo through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning(
          'No coordinator available for photo taking, creating coordinator');

      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();

      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  Future<void> _onPickPhotoRequested(
      PickPhotoRequested event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Picking photo through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning(
          'No coordinator available for photo picking, creating coordinator');

      // Create coordinator if it doesn't exist
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();

      // Now delegate to the newly created coordinator
      _coordinator!.add(event);
    }
  }

  Future<void> _onLoadSessionForViewing(
      LoadSessionForViewing event, Emitter<ActiveSessionState> emit) async {
    AppLogger.debug('Loading session for viewing through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      try {
        AppLogger.debug(
            'Attempting to delegate LoadSessionForViewing to coordinator');
        _coordinator!.add(event);
      } catch (e) {
        AppLogger.error(
            'Failed to delegate LoadSessionForViewing to coordinator: $e');
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

  void _onUpdateStateWithSessionPhotos(
      UpdateStateWithSessionPhotos event, Emitter<ActiveSessionState> emit) {
    // Cast List<dynamic> to List<RuckPhoto> to fix type mismatch
    final List<RuckPhoto> typedPhotos = event.photos
        .map((photo) => photo is RuckPhoto
            ? photo
            : RuckPhoto.fromJson(photo as Map<String, dynamic>))
        .toList();

    if (state is ActiveSessionRunning) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(photos: typedPhotos, isPhotosLoading: false));
    } else if (state is SessionSummaryGenerated) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(photos: typedPhotos, isPhotosLoading: false));
    }
  }

  void _onSessionErrorCleared(
      SessionErrorCleared event, Emitter<ActiveSessionState> emit) {
    if (state is ActiveSessionFailure) {
      final failureState = state as ActiveSessionFailure;

      // Try to recover to running state if we have session data
      AppLogger.info(
          '[SESSION_RECOVERY] Attempting to restore session from failure state');

      // First, check for crashed session recovery
      add(const CheckForCrashedSession());

      // If no crashed session found, try to transition to initial state
      // The CheckForCrashedSession will either restore a session or emit initial state
    } else if (state is ActiveSessionRunning &&
        (state as ActiveSessionRunning).errorMessage != null) {
      final currentState = state as ActiveSessionRunning;
      emit(currentState.copyWith(clearErrorMessage: true));
    } else if (state is SessionSummaryGenerated &&
        (state as SessionSummaryGenerated).errorMessage != null) {
      final currentState = state as SessionSummaryGenerated;
      emit(currentState.copyWith(clearErrorMessage: true));
    }
  }

  Future<void> _onSessionRecoveryRequested(
    SessionRecoveryRequested event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.debug('Requesting session recovery through coordinator');

    // Create coordinator if it doesn't exist
    if (_coordinator == null) {
      AppLogger.info('Creating coordinator for session recovery');
      _coordinator = _createCoordinator();
      _setupCoordinatorSubscription();
    }

    // Delegate to coordinator
    _coordinator!.add(event);
  }

  Future<void> _onSessionReset(
      SessionReset event, Emitter<ActiveSessionState> emit) async {
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
        secondLastPoint.latitude,
        secondLastPoint.longitude,
        lastPoint.latitude,
        lastPoint.longitude,
      );

      final timeDiff =
          lastPoint.timestamp.difference(secondLastPoint.timestamp).inSeconds;
      if (timeDiff <= 0 || distance <= 0) return null;

      // Return pace in minutes per km
      return (timeDiff / 60) / (distance / 1000);
    } catch (e) {
      return null;
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
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
      AppLogger.warning(
          'No coordinator available for completion payload building');
    }
    return {}; // Placeholder - actual data will come through coordinator
  }

  // Connectivity monitoring is now handled by LocationTrackingManager
  void _startConnectivityMonitoring(String sessionId) {
    AppLogger.debug('Starting connectivity monitoring through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!
          .add(ConnectivityMonitoringStartRequested(sessionId: sessionId));
    } else {
      AppLogger.warning('No coordinator available for connectivity monitoring');
    }
  }

  // Location tracking ensurance is now handled by LocationTrackingManager
  void _ensureLocationTrackingActive(String sessionId) {
    AppLogger.debug('Ensuring location tracking through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!
          .add(LocationTrackingEnsureActiveRequested(sessionId: sessionId));
    } else {
      AppLogger.warning(
          'No coordinator available for location tracking ensurance');
    }
  }

  // Offline session sync is now handled by UploadManager
  Future<void> _attemptOfflineSessionSync(String sessionId) async {
    AppLogger.debug('Attempting offline session sync through coordinator');

    // Delegate to coordinator if it exists
    if (_coordinator != null) {
      _coordinator!
          .add(OfflineSessionSyncAttemptRequested(sessionId: sessionId));
    } else {
      AppLogger.warning(
          'No coordinator available for offline session sync attempt');
    }
  }

  // All diagnostic methods removed - now handled by managers

  Future<void> _onMemoryPressureDetected(
    MemoryPressureDetected event,
    Emitter<ActiveSessionState> emit,
  ) async {
    AppLogger.warning('Memory pressure detected - taking defensive actions');

    // Temporarily suspend AI cheerleader during memory pressure
    // Note: We don't permanently disable it - just stop current audio
    if (_aiCheerleaderEnabled) {
      AppLogger.warning(
          '[MEMORY_PRESSURE] Temporarily suspending AI cheerleader to conserve memory');

      // Stop any currently playing audio but don't disable the feature
      try {
        await _audioService.stop();
        AppLogger.info('[MEMORY_PRESSURE] AI audio stopped to free memory');
      } catch (e) {
        AppLogger.error('[MEMORY_PRESSURE] Failed to stop audio service: $e');
      }

      // Track this as a failure to trigger circuit breaker if it keeps happening
      _aiCheerleaderFailureCount++;
      _lastAiFailureTime = DateTime.now();
    }

    // Delegate to coordinator for additional cleanup
    if (_coordinator != null) {
      _coordinator!.add(event);
    } else {
      AppLogger.warning(
          'No coordinator available for memory pressure handling');
    }
  }

  /// Handle coordinator state forwarding
  void _onCoordinatorStateForwarded(
    _CoordinatorStateForwarded event,
    Emitter<ActiveSessionState> emit,
  ) {
    // Debug timer updates
    if (event.state is ActiveSessionRunning) {
      final running = event.state as ActiveSessionRunning;
      print(
          '[TIMER_FIX] Emitting state with elapsedSeconds: ${running.elapsedSeconds}');
    }
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

  Future<void> _onSessionRecovered(
      SessionRecovered event, Emitter<ActiveSessionState> emit) async {
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
