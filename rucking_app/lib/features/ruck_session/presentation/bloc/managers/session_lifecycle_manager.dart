import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:get_it/get_it.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/managers/timer_coordinator.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/models/location_point.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service_consolidated.dart';
import '../../../../../core/services/storage_service.dart';
import '../../../../../core/services/watch_service.dart';
import '../../../../../core/services/connectivity_service.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/services/app_error_handler.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../domain/models/ruck_session.dart';
import '../events/session_events.dart' as manager_events;
import '../active_session_bloc.dart';
import 'timer_coordinator.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages session lifecycle operations (start, stop, pause, resume)
class SessionLifecycleManager implements SessionManager {
  final SessionRepository _sessionRepository;
  final AuthService _authService;
  final WatchService _watchService;
  final StorageService _storageService;
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;

  final StreamController<SessionLifecycleState> _stateController;
  SessionLifecycleState _currentState;

  // Callback for notifying recovery completion
  Function(Map<String, dynamic>)? _onRecoveryCompleted;

  // Callback for getting completion data from coordinator
  Map<String, dynamic>? Function()? _getCompletionData;

  DateTime? _sessionStartTime;
  String? _activeSessionId;
  Timer? _ticker;
  Timer? _sessionPersistenceTimer;
  StreamSubscription? _connectivitySubscription;

  // Sophisticated timer coordination
  late TimerCoordinator _timerCoordinator;

  SessionLifecycleManager({
    required SessionRepository sessionRepository,
    required AuthService authService,
    required WatchService watchService,
    required StorageService storageService,
    required ApiClient apiClient,
    required ConnectivityService connectivityService,
  })  : _sessionRepository = sessionRepository,
        _authService = authService,
        _watchService = watchService,
        _storageService = storageService,
        _apiClient = apiClient,
        _connectivityService = connectivityService,
        _stateController = StreamController<SessionLifecycleState>.broadcast(),
        _currentState = const SessionLifecycleState() {
    // Initialize sophisticated timer coordinator
    _timerCoordinator = TimerCoordinator(
      onMainTick: _onMainTick,
      onWatchdogTick: _onWatchdogTick,
      onPersistenceTick: _onPersistenceTick,
      onBatchUploadTick: _onBatchUploadTick,
      onConnectivityCheck: _onConnectivityCheck,
      onMemoryCheck: _onMemoryCheck,
      onPaceCalculation: _onPaceCalculation,
    );
  }

  @override
  Stream<SessionLifecycleState> get stateStream => _stateController.stream;

  @override
  SessionLifecycleState get currentState => _currentState;

  /// Set recovery completion callback
  void setRecoveryCallback(Function(Map<String, dynamic>) callback) {
    _onRecoveryCompleted = callback;
  }

  /// Set completion data callback
  void setCompletionDataCallback(Map<String, dynamic>? Function() callback) {
    _getCompletionData = callback;
  }

  @override
  Future<void> handleEvent(manager_events.ActiveSessionEvent event) async {
    if (event is manager_events.SessionStartRequested) {
      await _onSessionStartRequested(event);
    } else if (event is manager_events.SessionStopRequested) {
      await _onSessionStopRequested(event);
    } else if (event is manager_events.SessionPaused) {
      await _onSessionPaused(event);
    } else if (event is manager_events.SessionResumed) {
      await _onSessionResumed(event);
    } else if (event is manager_events.SessionReset) {
      await _onSessionReset(event);
    } else if (event is manager_events.TimerStarted) {
      await _onTimerStarted(event);
    } else if (event is manager_events.TimerStopped) {
      await _onTimerStopped(event);
    } else if (event is manager_events.Tick) {
      await _onTick(event);
    }
  }

  Future<void> _onSessionStartRequested(
      manager_events.SessionStartRequested event) async {
    try {
      AppLogger.info(
          '[LIFECYCLE] Starting ruck session with weight: ${event.ruckWeightKg ?? 0.0}kg');

      // CRITICAL: Clear any existing session recovery cache to prevent data mixing
      try {
        await _storageService.remove('active_session_data');
        AppLogger.info(
            '[LIFECYCLE] Cleared session recovery cache before starting new session');
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Failed to clear session recovery cache: $e');
      }

      // Optimistically mark session as active before backend confirmation
      _updateState(_currentState.copyWith(
        isActive: true,
        sessionId: null, // will set after ID generation below
        // keep isLoading false to avoid showing initializing screen
        // isLoading: true,
      ));

      // Phone-only session creation: prefer existing sessionId but allow fallback creation
      final sessionId = event.sessionId;
      String finalSessionId;

      if (sessionId != null && sessionId.isNotEmpty) {
        AppLogger.info('[LIFECYCLE] Starting existing session: $sessionId');
        finalSessionId = sessionId;
      } else {
        // Fallback: create session directly (no watch logic)
        AppLogger.warning(
            '[LIFECYCLE] No sessionId provided - creating session directly');

        try {
          final createResponse = await _apiClient.post('/rucks', {
            'ruck_weight_kg': event.ruckWeightKg ?? 0.0,
            'user_weight_kg': event.userWeightKg ?? 70.0,
            'is_manual': false,
          });

          finalSessionId = createResponse['id'].toString();
          AppLogger.info(
              '[LIFECYCLE] Created fallback session: $finalSessionId');
        } catch (e) {
          AppLogger.error('[LIFECYCLE] Failed to create fallback session: $e');
          rethrow;
        }
      }

      _activeSessionId = finalSessionId;
      _sessionStartTime = DateTime.now().toUtc();

      // CRITICAL: Set session ID in watch service BEFORE starting watch session
      _watchService.setCurrentSessionId(finalSessionId);

      // Get user metric preference
      final preferMetric = await _getUserMetricPreference();

      // Ensure backend session transitions from 'created' -> 'in_progress'
      try {
        AppLogger.info(
            '[LIFECYCLE] Starting session on backend: $finalSessionId');

        final startPayload = {
          'started_at':
              (_sessionStartTime ?? DateTime.now()).toUtc().toIso8601String(),
          'ruck_weight_kg': event.ruckWeightKg ?? 0.0,
          'user_weight_kg': event.userWeightKg ?? 70.0,
        };

        AppLogger.info('[LIFECYCLE] Start payload: $startPayload');

        final startResponse =
            await _apiClient.post('/rucks/$finalSessionId/start', startPayload);

        AppLogger.info(
            '[LIFECYCLE] Backend session start confirmed for $finalSessionId');
      } catch (e) {
        AppLogger.error('[LIFECYCLE] Failed to start session on backend: $e');
        AppLogger.error(
            '[LIFECYCLE] Session ID: $finalSessionId, SessionStartTime: $_sessionStartTime');
        rethrow;
      }

      AppLogger.info(
          '[LIFECYCLE] Starting watch session with weight: ${event.ruckWeightKg ?? 0.0}kg');
      await _watchService.startSessionOnWatch(event.ruckWeightKg ?? 0.0,
          isMetric: preferMetric);
      AppLogger.info('[LIFECYCLE] Watch session start completed');

      _startTimer();
      _startSophisticatedTimerSystem();
      _startSessionPersistenceTimer();
      _startConnectivityMonitoring();

      _updateState(_currentState.copyWith(
        isActive: true,
        sessionId: finalSessionId,
        startTime: _sessionStartTime,
        duration: Duration.zero,
        ruckWeightKg: event.ruckWeightKg ?? 0.0,
        userWeightKg: event.userWeightKg ?? 70.0,
        isLoading: false,
        errorMessage: null,
      ));

      AppLogger.debug(
          'Session lifecycle started successfully: $finalSessionId');
    } catch (e, stackTrace) {
      AppLogger.error('Error starting session: $e\n$stackTrace');

      final errorMessage =
          ErrorHandler.getUserFriendlyMessage(e, 'Session Start');
      _updateState(_currentState.copyWith(
        isLoading: false,
        errorMessage: errorMessage,
      ));

      // Monitor session start failures
      await AppErrorHandler.handleCriticalError(
        'session_start',
        e,
        context: {
          'session_type': 'ruck_session',
          'has_location_permission':
              false, // Will be checked by location manager
          'is_authenticated': _authService.isAuthenticated(),
        },
      );
    }
  }

  Future<void> _onSessionStopRequested(
      manager_events.SessionStopRequested event) async {
    try {
      AppLogger.info(
          '[LIFECYCLE] Stopping ruck session - sessionId: $_activeSessionId');
      AppLogger.info(
          '[LIFECYCLE] Current state before stop: isActive=${_currentState.isActive}, sessionId=${_currentState.sessionId}, pausedAt=${_currentState.pausedAt}');

      // CRITICAL: Cancel timers FIRST to prevent race condition with _onTick
      _ticker?.cancel();
      _ticker = null;
      AppLogger.info(
          '[LIFECYCLE] Timer cancelled to prevent duration override');

      // CRITICAL FIX: Clear pausedAt to prevent showing paused state during completion
      // This ensures the coordinator doesn't emit a paused state while transitioning to completed
      _updateState(_currentState.copyWith(
        isSaving: true,
        pausedAt: null, // Clear paused state immediately when stopping
        isActive:
            false, // Mark session as inactive to prevent further state changes
      ));

      // Stop watch session - do this AFTER marking session inactive to prevent race conditions
      try {
        await _watchService.endSessionOnWatch();
        AppLogger.info('[LIFECYCLE] Watch session ended successfully');
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Watch session end failed (non-critical): $e');
        // Continue with completion even if watch fails
      }

      // Calculate final duration at exact moment of stop
      final finalDuration = _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!)
          : Duration.zero;
      AppLogger.info(
          '[LIFECYCLE] Final session duration: ${finalDuration.inSeconds}s (${finalDuration.inMinutes}m ${finalDuration.inSeconds % 60}s)');

      // ENHANCED: Collect comprehensive session completion data
      Map<String, dynamic> completionData = {
        'duration_seconds': finalDuration.inSeconds,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'end_time': DateTime.now().toUtc().toIso8601String(),
      };

      // Add start time if available
      if (_sessionStartTime != null) {
        completionData['start_time'] = _sessionStartTime!.toIso8601String();
      }

      // Add weight data from current state
      if (_currentState.ruckWeightKg > 0.0) {
        completionData['ruck_weight_kg'] = _currentState.ruckWeightKg;
      }
      if (_currentState.userWeightKg > 0.0) {
        completionData['weight_kg'] = _currentState.userWeightKg;
      }

      // Get comprehensive metrics from coordinator completion data
      try {
        final coordinatorData = _getCompletionData?.call();
        AppLogger.info(
            '[LIFECYCLE] Getting completion data from coordinator: $coordinatorData');

        if (coordinatorData != null) {
          // Merge coordinator data with completion data
          coordinatorData.forEach((key, value) {
            if (value != null) {
              completionData[key] = value;
            }
          });

          AppLogger.info(
              '[LIFECYCLE] SUCCESS: Enhanced completion data from coordinator with ${completionData.keys.length} fields');
          AppLogger.info('[LIFECYCLE] Final completion data: $completionData');
          // Explicit HR metrics visibility for debugging
          final avgHr = completionData['avg_heart_rate'];
          final minHr = completionData['min_heart_rate'];
          final maxHr = completionData['max_heart_rate'];
          AppLogger.info(
              '[LIFECYCLE] HR_METRICS in payload -> avg: ${avgHr}, min: ${minHr}, max: ${maxHr}');
        } else {
          AppLogger.warning(
              '[LIFECYCLE] No completion data available from coordinator - using basic completion data');
        }
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Failed to get completion data from coordinator: $e - continuing with basic data');
      }

      // CRITICAL: Call completion API with comprehensive data and retry logic
      bool completionSuccessful = false;
      String? completionError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          AppLogger.info(
              '[LIFECYCLE] Sending completion data (attempt $attempt): ${completionData.keys.join(", ")}');
          AppLogger.info(
              '[LIFECYCLE] CALORIES_DEBUG: Sending calories_burned=${completionData['calories_burned']} to backend');
          // Add timeout to prevent hanging on slow API responses
          await _apiClient
              .post('/rucks/$_activeSessionId/complete', completionData)
              .timeout(const Duration(seconds: 15), onTimeout: () {
            throw Exception('Session completion API timeout after 15 seconds');
          });
          completionSuccessful = true;
          AppLogger.info(
              '[LIFECYCLE] Session completion successful with comprehensive data');
          break;
        } catch (e) {
          completionError = e.toString();
          AppLogger.warning(
              '[LIFECYCLE] Completion attempt $attempt failed: $e');

          // Check for 404/405 errors indicating session doesn't exist in backend
          if (e.toString().contains('404') || e.toString().contains('405')) {
            AppLogger.error(
                '[LIFECYCLE] Session $_activeSessionId does not exist in backend (404/405). Attempting recovery...');

            // Try to recreate the session before giving up
            if (attempt == 1) {
              try {
                AppLogger.info(
                    '[LIFECYCLE] Attempting to recreate lost session $_activeSessionId');

                // Create new session with current data
                final recreateResponse = await _apiClient.post('/rucks', {
                  'ruck_weight_kg': completionData['ruck_weight_kg'] ?? 0.0,
                  'user_weight_kg': completionData['user_weight_kg'] ?? 70.0,
                  'is_manual': false,
                  'distance_km': completionData['distance_km'] ?? 0.0,
                  'duration_seconds': completionData['duration_seconds'] ?? 0,
                  'elevation_gain_m': completionData['elevation_gain_m'] ?? 0.0,
                  'start_time': completionData['start_time'] ??
                      DateTime.now().toUtc().toIso8601String(),
                });

                final newSessionId = recreateResponse['id'].toString();
                AppLogger.info(
                    '[LIFECYCLE] Recreated session as: $newSessionId');

                // Update session ID and try completion again
                _activeSessionId = newSessionId;
                completionData['session_id'] = newSessionId;

                // Try completing the recreated session
                final completeResponse = await _apiClient.post(
                    '/rucks/$newSessionId/complete', completionData);
                AppLogger.info(
                    '[LIFECYCLE] Successfully completed recreated session: $newSessionId');
                completionSuccessful = true;
                break; // Exit retry loop
              } catch (recreateError) {
                AppLogger.error(
                    '[LIFECYCLE] Failed to recreate session: $recreateError');
                // Continue with normal error handling
              }
            }

            // If recreation failed or we've already tried, clean up
            if (!completionSuccessful) {
              AppLogger.error(
                  '[LIFECYCLE] Session recreation failed. Cleaning up local state.');

              // Store error context for debugging
              await _storageService.setObject('lost_session_context', {
                'original_session_id': _activeSessionId,
                'error': e.toString(),
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'completion_data': completionData,
              });

              // Clear all local session data
              await _storageService.remove('active_session_data');
              await _storageService
                  .remove('pending_completion_$_activeSessionId');

              // Reset state to initial to trigger navigation to homepage
              _updateState(const SessionLifecycleState(
                isActive: false,
                sessionId: null,
                startTime: null,
              ));
              _activeSessionId = null;

              return; // Exit early - don't retry
            }
          }

          await Future.delayed(Duration(seconds: attempt * 2)); // Backoff
        }
      }

      if (!completionSuccessful) {
        // Persist comprehensive data for later retry
        await _storageService.setObject(
            'pending_completion_$_activeSessionId', completionData);
        AppLogger.error(
            '[LIFECYCLE] All completion attempts failed, persisted comprehensive data for retry: $completionError');
      } else {
        // Clear any previous pending
        await _storageService.remove('pending_completion_$_activeSessionId');
      }

      final newState = _currentState.copyWith(
        isActive: false,
        // Keep the sessionId so downstream managers & UI can access it
        sessionId: _activeSessionId,
        duration: finalDuration, // Use the calculated final duration
        isSaving: false,
      );

      AppLogger.info(
          '[LIFECYCLE] Updating state: isActive=${newState.isActive}, sessionId=${newState.sessionId}');
      _updateState(newState);
      AppLogger.info('[LIFECYCLE] State updated successfully');

      // NOTE: we intentionally keep _activeSessionId & _sessionStartTime until the
      // coordinator has emitted an `ActiveSessionCompleted` state. They will be
      // cleared when the coordinator is closed.

      AppLogger.info('[LIFECYCLE] Session lifecycle stopped successfully');

      // Clear crash recovery data since session completed normally
      await clearCrashRecoveryData();
    } catch (e) {
      AppLogger.error('[LIFECYCLE] Error stopping session: $e');
      _updateState(_currentState.copyWith(
        isSaving: false,
        errorMessage: 'Failed to stop session',
      ));
    }
  }

  Future<void> _onSessionPaused(manager_events.SessionPaused event) async {
    if (!_currentState.isActive) {
      AppLogger.warning(
          '[LIFECYCLE] Pause requested but session not active - ignoring');
      return;
    }

    AppLogger.info('[LIFECYCLE] ===== PAUSING SESSION =====');
    AppLogger.info(
        '[LIFECYCLE] Pausing session - keeping session active but paused');
    AppLogger.info(
        '[LIFECYCLE] Current state before pause: isActive=${_currentState.isActive}, pausedAt=${_currentState.pausedAt}');

    // Pause timers
    _ticker?.cancel();
    AppLogger.info('[LIFECYCLE] Timer cancelled for pause');

    // CRITICAL: Pause TimerCoordinator to stop duration increment
    _timerCoordinator.pauseTimerSystem();
    AppLogger.info('[LIFECYCLE] TimerCoordinator paused successfully');

    // Update watch (the watch service will handle avoiding duplicate calls)
    await _watchService.pauseSessionOnWatch();
    AppLogger.info('[LIFECYCLE] Watch pause command sent');

    _updateState(_currentState.copyWith(
      isActive: true, // Keep session active - just mark as paused
      pausedAt: DateTime.now().toUtc(), // Use pausedAt to indicate paused state
    ));

    AppLogger.info(
        '[LIFECYCLE] State updated - pausedAt: ${_currentState.pausedAt}');
    AppLogger.info('[LIFECYCLE] ===== SESSION PAUSED SUCCESSFULLY =====');
  }

  Future<void> _onSessionResumed(manager_events.SessionResumed event) async {
    if (!_currentState.isActive) {
      AppLogger.warning(
          '[LIFECYCLE] Resume requested but session not active - ignoring');
      return;
    }

    if (_currentState.pausedAt == null) {
      AppLogger.warning(
          '[LIFECYCLE] Resume requested but session not paused - ignoring');
      return;
    }

    AppLogger.info('[LIFECYCLE] ===== RESUMING SESSION =====');
    AppLogger.info('[LIFECYCLE] Resuming session from paused state');
    AppLogger.info(
        '[LIFECYCLE] Current state before resume: isActive=${_currentState.isActive}, pausedAt=${_currentState.pausedAt}');

    // Calculate pause duration
    final pausedDuration = _currentState.pausedAt != null
        ? DateTime.now().difference(_currentState.pausedAt!)
        : Duration.zero;

    AppLogger.info(
        '[LIFECYCLE] Pause duration was: ${pausedDuration.inSeconds} seconds');

    // Resume timers
    _startTimer();
    AppLogger.info('[LIFECYCLE] Timer restarted for resume');

    // CRITICAL: Resume TimerCoordinator to restart duration increment
    _timerCoordinator.resumeTimerSystem();
    AppLogger.info('[LIFECYCLE] TimerCoordinator resumed successfully');

    // Update watch
    await _watchService.resumeSessionOnWatch();
    AppLogger.info('[LIFECYCLE] Watch resume command sent');

    _updateState(_currentState.copyWith(
      isActive: true,
      pausedAt: null, // Clear paused state
      totalPausedDuration: _currentState.totalPausedDuration + pausedDuration,
    ));

    AppLogger.info(
        '[LIFECYCLE] State updated - pausedAt: ${_currentState.pausedAt}');
    AppLogger.info('[LIFECYCLE] ===== SESSION RESUMED SUCCESSFULLY =====');
  }

  Future<void> _onTimerStarted(manager_events.TimerStarted event) async {
    _startTimer();
  }

  Future<void> _onTimerStopped(manager_events.TimerStopped event) async {
    _ticker?.cancel();
    _ticker = null;
  }

  static int _tickCount = 0;

  Future<void> _onTick(manager_events.Tick event) async {
    _tickCount++;
    if (_tickCount % 5 == 0) {
      print('[FUCK_TIMER] _onTick called $_tickCount times');
    }

    if (_currentState.isActive &&
        _sessionStartTime != null &&
        _currentState.pausedAt == null) {
      // Only update duration when NOT paused (pausedAt is null)
      final newDuration = DateTime.now().difference(_sessionStartTime!);
      _updateState(_currentState.copyWith(duration: newDuration));

      if (_tickCount % 5 == 0) {
        print('[FUCK_TIMER] Duration updated to ${newDuration.inSeconds} seconds');
      }
    }
    // When paused (pausedAt is not null), duration should remain frozen - no updates
  }

  Future<bool> _getUserMetricPreference() async {
    bool preferMetric = false; // Default to imperial

    final authState = GetIt.I<AuthBloc>().state;
    AppLogger.info(
        '[SESSION_LIFECYCLE] AuthBloc state type: ${authState.runtimeType}');

    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
      AppLogger.info(
          '[SESSION_LIFECYCLE] User preferMetric: ${authState.user.preferMetric}');
    } else {
      AppLogger.warning(
          '[SESSION_LIFECYCLE] User not authenticated, checking storage for preference');

      // Fallback: Try to get user preference from storage
      try {
        final storedUserData =
            await _storageService.getObject(AppConfig.userProfileKey);
        if (storedUserData != null &&
            storedUserData.containsKey('preferMetric')) {
          preferMetric = storedUserData['preferMetric'] as bool;
          AppLogger.info(
              '[SESSION_LIFECYCLE] Found stored user preference: $preferMetric');
        } else {
          AppLogger.warning(
              '[SESSION_LIFECYCLE] No stored user preference found, defaulting to imperial (false)');
        }
      } catch (e) {
        AppLogger.error(
            '[SESSION_LIFECYCLE] Error reading stored user preference: $e');
        AppLogger.warning('[SESSION_LIFECYCLE] Defaulting to imperial (false)');
      }
    }

    AppLogger.info(
        '[SESSION_LIFECYCLE] Final preferMetric value: $preferMetric');
    return preferMetric;
  }

  void _startTimer() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      handleEvent(const manager_events.Tick());
    });
  }

  void _updateState(SessionLifecycleState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override

  /// Check for and recover active session on app startup
  Future<void> checkForCrashedSession() async {
    try {
      print('[RECOVERY_DEBUG] Starting session recovery check');
      print(
          '[RECOVERY_DEBUG] Storage service type: ${_storageService.runtimeType}');

      // Check if storage service is working at all
      try {
        await _storageService.setObject('recovery_test', {'test': 'value'});
        final testRead = await _storageService.getObject('recovery_test');
        print('[RECOVERY_DEBUG] Storage test - wrote and read: $testRead');
        await _storageService.remove('recovery_test');
      } catch (e) {
        print('[RECOVERY_DEBUG] Storage service not working: $e');
      }

      Map<String, dynamic>? sessionData;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          print(
              '[RECOVERY_DEBUG] Attempting storage read $attempt for key: active_session_data');
          sessionData = await _storageService.getObject('active_session_data');
          print('[RECOVERY_DEBUG] Raw data on attempt $attempt: $sessionData');
          print(
              '[RECOVERY_DEBUG] Data type: ${sessionData?.runtimeType}, keys: ${sessionData?.keys}');
          break;
        } catch (e) {
          print('[RECOVERY_DEBUG] Storage read failed on attempt $attempt: $e');
          print('[RECOVERY_DEBUG] Error type: ${e.runtimeType}');
          await Future.delayed(Duration(seconds: attempt));
        }
      }

      // Try alternative keys in case there's a mismatch
      if (sessionData == null) {
        print('[RECOVERY_DEBUG] Trying alternative storage keys...');
        try {
          final altData1 = await _storageService.getObject('session_data');
          print('[RECOVERY_DEBUG] Alternative key session_data: $altData1');
          final altData2 = await _storageService.getObject('active_session');
          print('[RECOVERY_DEBUG] Alternative key active_session: $altData2');
        } catch (e) {
          print('[RECOVERY_DEBUG] Alternative key check failed: $e');
        }
      }

      if (sessionData == null) {
        print(
            '[RECOVERY_DEBUG] No data found after 3 attempts and alternative keys');
        return;
      }

      final sessionId = sessionData['session_id']?.toString();
      final startTimeStr = sessionData['session_start_time'] as String?;
      // If we have session data, assume it was active when stored
      final isActive = sessionData['session_id'] != null;

      if (!isActive || sessionId == null || startTimeStr == null) {
        AppLogger.info('[RECOVERY] Session data incomplete or inactive');
        await _storageService.remove('active_session_data');
        return;
      }

      final startTime = DateTime.parse(startTimeStr);
      final crashDuration = DateTime.now().difference(startTime);

      // If session was started more than 6 hours ago, probably abandon it
      if (crashDuration.inHours > 6) {
        AppLogger.info(
            '[RECOVERY] Session too old (${crashDuration.inHours}h), abandoning');
        await _storageService.remove('active_session_data');
        return;
      }

      // CRITICAL: Validate session exists in backend before recovery
      try {
        AppLogger.info(
            '[RECOVERY] Validating session $sessionId exists in backend...');
        final resp = await _apiClient.get('/rucks/$sessionId');
        // ApiClient throws on non-2xx. If we reach here, just sanity-check shape.
        if (resp == null) {
          throw Exception('Session validation failed: null response');
        }
        if (resp is Map && resp.isEmpty) {
          throw Exception('Session validation failed: empty payload');
        }
        AppLogger.info('[RECOVERY] ✅ Session $sessionId validated in backend');
      } catch (e) {
        AppLogger.error(
            '[RECOVERY] ❌ Session $sessionId does not exist in backend: $e');
        AppLogger.error(
            '[RECOVERY] Clearing orphaned session data and aborting recovery');
        await _storageService.remove('active_session_data');
        return;
      }

      // Check if we're already running a LIVE active session with different ID - don't override
      // Only skip if we have an active session AND it's different from the recovered session
      if (_currentState.isActive &&
          _currentState.sessionId != null &&
          _currentState.sessionId != sessionId &&
          _ticker != null &&
          _ticker!.isActive) {
        AppLogger.info(
            '[RECOVERY] Already running LIVE session ${_currentState.sessionId}, found recovery for different session ${sessionId} - skipping recovery');
        await _storageService
            .remove('active_session_data'); // Clean up stale recovery data
        return;
      }

      AppLogger.warning(
          '🔥 CRASH RECOVERY: Found active session from ${crashDuration.inMinutes} minutes ago');

      // Restore session state
      _activeSessionId = sessionId;
      _sessionStartTime = startTime;

      final ruckWeight =
          (sessionData['ruck_weight_kg'] as num?)?.toDouble() ?? 0.0;
      final userWeight = 70.0; // Default weight if not stored
      final lastDuration = Duration(
          seconds: (sessionData['elapsed_seconds'] as num?)?.toInt() ?? 0);

      final totalDistance =
          (sessionData['distance_km'] as num?)?.toDouble() ?? 0.0;
      final elevationGain =
          (sessionData['elevation_gain'] as num?)?.toDouble() ?? 0.0;
      final elevationLoss =
          (sessionData['elevation_loss'] as num?)?.toDouble() ?? 0.0;
      final caloriesBurned =
          (sessionData['calories'] as num?)?.toDouble() ?? 0.0;

      // Calculate gap distance from last saved location to current location
      double gapDistance = 0.0;
      LocationPoint? lastSavedLocation;
      try {
        final lastLocationData =
            sessionData['last_location'] as Map<String, dynamic>?;
        if (lastLocationData != null) {
          lastSavedLocation = LocationPoint.fromJson(lastLocationData);
          AppLogger.info(
              '[LIFECYCLE] Last saved location: ${lastSavedLocation.latitude}, ${lastSavedLocation.longitude}');

          // Get current location to calculate gap distance
          gapDistance = await _calculateGapDistance(lastSavedLocation);
          AppLogger.info(
              '[LIFECYCLE] Calculated gap distance: ${gapDistance}km');
        }
      } catch (e) {
        AppLogger.warning('[LIFECYCLE] Could not calculate gap distance: $e');
      }

      final recoveredDistance = totalDistance + gapDistance;
      AppLogger.info(
          '[LIFECYCLE] Recovery data - Distance: ${totalDistance}km + gap: ${gapDistance}km = ${recoveredDistance}km, Elevation: ${elevationGain}m gain/${elevationLoss}m loss, Calories: $caloriesBurned');

      _updateState(SessionLifecycleState(
        isActive: true,
        sessionId: sessionId,
        startTime: startTime,
        duration: lastDuration,
        ruckWeightKg: ruckWeight,
        userWeightKg: userWeight,
        errorMessage: '🔄 Session recovered from unexpected app closure',
        isLoading: false,
        isSaving: false,
        currentSession: null,
        totalPausedDuration: Duration.zero,
        pausedAt: null,
        isRecovered: true,
      ));

      // Send recovery data to coordinator so it can initialize managers
      // Send recovery data to coordinator - but mark it as recovery data
      _notifyRecoveryCompleted({
        'is_crash_recovery': true, // Mark as actual crash recovery
        'session_id': sessionId,
        'start_time': startTimeStr,
        'ruck_weight_kg': ruckWeight,
        'user_weight_kg': userWeight,
        'distance_km': recoveredDistance, // Restore accumulated distance
        'elevation_gain': elevationGain,
        'elevation_loss': elevationLoss,
        'calories': caloriesBurned, // Restore accumulated calories
        'last_location': lastSavedLocation?.toJson(),
        'gap_distance_km': gapDistance,
        'recovery_duration_minutes': crashDuration.inMinutes,
      });

      // Restart timers and services
      _startTimer();
      _startSessionPersistenceTimer();
      _startSophisticatedTimerSystem();
      _startConnectivityMonitoring();

      // Check for pending completions
      final pendingKeys = await _storageService.getAllKeys().then((keys) =>
          keys.where((k) => k.startsWith('pending_completion_')).toList());
      for (final key in pendingKeys) {
        final data = await _storageService.getObject(key);
        if (data != null) {
          final sessionId = key.split('_').last;
          try {
            await _apiClient.post('/rucks/$sessionId/complete', data);
            await _storageService.remove(key);
            AppLogger.info(
                '[RECOVERY] Successfully completed pending session $sessionId');
          } catch (e) {
            AppLogger.warning(
                '[RECOVERY] Failed to complete pending session $sessionId: $e');
            // Leave for next try
          }
        }
      }

      AppLogger.info('✅ Session recovery complete: $sessionId');
    } catch (e) {
      AppLogger.error('[RECOVERY] Failed to recover crashed session: $e');
      await _storageService.remove('active_session_data');
    }
  }

  /// Clear the crash recovery data when session completes normally
  Future<void> clearCrashRecoveryData() async {
    try {
      await _storageService.remove('active_session_data');
      AppLogger.debug('[RECOVERY] Cleared crash recovery data');
    } catch (e) {
      AppLogger.error('[RECOVERY] Failed to clear recovery data: $e');
    }
  }

  Future<void> dispose() async {
    _ticker?.cancel();
    _sessionPersistenceTimer?.cancel();
    _connectivitySubscription?.cancel();
    _timerCoordinator.dispose();
    await _stateController.close();
  }

  // Getters for other managers to access session info
  String? get activeSessionId => _activeSessionId;
  DateTime? get sessionStartTime => _sessionStartTime;
  Future<void> _onSessionReset(manager_events.SessionReset event) async {
    try {
      AppLogger.info('[LIFECYCLE] Session reset requested');

      // Cancel any active timers
      _ticker?.cancel();
      _ticker = null;

      // Clear session identifiers and state
      _activeSessionId = null;
      _sessionStartTime = null;

      // Reset to initial state
      _updateState(const SessionLifecycleState(
        isActive: false,
        sessionId: null,
        startTime: null,
        duration: Duration.zero,
        totalPausedDuration: Duration.zero,
        pausedAt: null,
        ruckWeightKg: 0.0,
        userWeightKg: 0.0,
        errorMessage: null,
        isSaving: false,
        isLoading: false,
        currentSession: null,
      ));

      AppLogger.info('[LIFECYCLE] Session reset completed successfully');
    } catch (e) {
      AppLogger.error('[LIFECYCLE] Error resetting session: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to reset session: $e',
      ));
    }
  }

  bool get isSessionActive => _currentState.isActive;
  // A session is considered paused when it's active but has a non-null pausedAt timestamp
  // We deliberately keep the session active during pause, so rely on pausedAt to signal pause state
  bool get isPaused => _currentState.pausedAt != null;
  Duration get totalPausedDuration => _currentState.totalPausedDuration;

  /// Public method to reset the session lifecycle manager
  Future<void> reset() async {
    await _onSessionReset(const manager_events.SessionReset());
  }

  /// Start session persistence timer for autosave - 30s for crash protection
  void _startSessionPersistenceTimer() {
    _sessionPersistenceTimer?.cancel();
    _sessionPersistenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_currentState.isActive) {
        _persistSessionInBackground();
      }
    });

    AppLogger.info(
        '[LIFECYCLE] 🛡️ Crash protection: Session autosave every 30 seconds');
  }

  /// Persist session data in background
  void _persistSessionInBackground() {
    // Run persistence in background without blocking UI
    Timer(const Duration(milliseconds: 100), () async {
      try {
        await _persistSessionData();
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Background session persistence failed: $e');
      }
    });
  }

  /// Persist session data for crash recovery - includes all metrics
  Future<void> _persistSessionData() async {
    if (!_currentState.isActive || _activeSessionId == null) return;

    double totalDistance = 0.0;
    double elevationGain = 0.0;
    double elevationLoss = 0.0;
    double calories = 0.0;

    LocationPoint? lastLocationPoint;
    try {
      final blocState = GetIt.I<ActiveSessionBloc>().state;
      if (blocState is ActiveSessionRunning) {
        totalDistance = blocState.distanceKm;
        elevationGain = blocState.elevationGain;
        elevationLoss = blocState.elevationLoss;
        calories = blocState.calories;
        // Save the last location point for gap calculation on recovery
        if (blocState.locationPoints.isNotEmpty) {
          lastLocationPoint = blocState.locationPoints.last;
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to get metrics for persistence: $e');
    }

    final sessionData = {
      'session_id': _activeSessionId, // Align with user's key
      'session_start_time': _sessionStartTime?.toIso8601String(),
      'ruck_weight_kg': _currentState.ruckWeightKg,
      'user_weight_kg': _currentState.userWeightKg,
      'is_active': _currentState.isActive,
      'elapsed_seconds': _currentState.duration.inSeconds,
      'total_paused_duration_seconds':
          _currentState.totalPausedDuration.inSeconds,
      'last_persisted_at': DateTime.now().toUtc().toIso8601String(),
      'distance_km': totalDistance,
      'elevation_gain': elevationGain,
      'elevation_loss': elevationLoss,
      'calories': calories,
      // Save last location for gap distance calculation
      'last_location': lastLocationPoint?.toJson(),
    };

    bool saved = false;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _storageService.setObject('active_session_data', sessionData);
        // Confirm save
        final savedData =
            await _storageService.getObject('active_session_data');
        if (savedData != null) {
          saved = true;
          AppLogger.info(
              '[LIFECYCLE] 💾 Session data persisted successfully (${totalDistance.toStringAsFixed(2)}km, ${calories.toInt()}cal)');
          break;
        }
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Persistence attempt $attempt failed: $e');
      }
      await Future.delayed(Duration(seconds: attempt));
    }
    if (!saved)
      AppLogger.error('[LIFECYCLE] Failed to persist after 3 attempts');
  }

  /// Start connectivity monitoring for offline session sync
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _connectivityService.connectivityStream.listen((isConnected) {
      // Only handle connectivity changes if we're in a valid session state
      if (!_currentState.isActive) {
        AppLogger.debug(
            '[LIFECYCLE] Ignoring connectivity change - session not active');
        return;
      }

      if (isConnected) {
        AppLogger.info(
            '[LIFECYCLE] Connectivity restored for session: $_activeSessionId');

        // Add slight delay to prevent race conditions with UI rebuilds
        Timer(const Duration(milliseconds: 100), () async {
          if (_currentState.isActive) {
            // Only attempt sync if session is still offline
            if (_activeSessionId != null &&
                _activeSessionId!.startsWith('offline_')) {
              await _attemptOfflineSessionSync(_activeSessionId!);
            }

            // Also sync any stored offline sessions
            // _syncOfflineSessionsInBackground(); // TEMPORARILY DISABLED to fix duplicate session creation
          }
        });
      } else {
        AppLogger.warning(
            '[LIFECYCLE] Connectivity lost for session: $_activeSessionId, switching to offline mode...');

        // Only switch to offline mode if we're not already offline
        if (_activeSessionId != null &&
            !_activeSessionId!.startsWith('offline_')) {
          // Log info message instead of error to avoid Sentry reporting
          AppLogger.info(
              '[SESSION_LIFECYCLE] Network unavailable - session continues in offline mode');

          // Emit informational message (not error) to inform user
          _updateState(_currentState.copyWith(
            errorMessage: 'Session continues in offline mode',
          ));

          // Clear the message after 3 seconds
          Timer(const Duration(seconds: 3), () {
            if (_currentState.isActive) {
              _updateState(_currentState.copyWith(
                errorMessage: null,
              ));
            }
          });
        }
      }
    });
  }

  /// Attempt to sync offline session to backend
  Future<void> _attemptOfflineSessionSync(String sessionId) async {
    if (!sessionId.startsWith('offline_')) return;

    try {
      AppLogger.info(
          '[LIFECYCLE] Attempting to sync offline session to backend...');

      // Create session with current session data
      final createResponse = await _apiClient.post('/rucks', {
        'ruck_weight_kg': _currentState.ruckWeightKg,
        'user_weight_kg': _currentState.userWeightKg,
        'notes': '', // Empty notes for now
        'is_manual': false, // This is an active session that was offline
      }).timeout(const Duration(seconds: 5));

      final newSessionId = createResponse['id']?.toString();
      if (newSessionId != null && newSessionId.isNotEmpty) {
        AppLogger.info(
            '[LIFECYCLE] Successfully synced offline session. New session ID: $newSessionId');

        // CRITICAL: Complete the session with calculated metrics
        try {
          final completionData = _getCompletionData?.call();
          if (completionData != null) {
            AppLogger.info(
                '[LIFECYCLE] Completing offline session with metrics: ${completionData.keys.join(", ")}');
            await _apiClient.post(
                '/rucks/$newSessionId/complete', completionData);
            AppLogger.info(
                '[LIFECYCLE] Offline session completed with metrics successfully');
          } else {
            AppLogger.warning(
                '[LIFECYCLE] No completion data available for offline session - session created but not completed');
          }
        } catch (e) {
          AppLogger.error(
              '[LIFECYCLE] Failed to complete offline session with metrics: $e');
        }

        // Check if session is still active and update state atomically
        if (_currentState.isActive && _activeSessionId == sessionId) {
          _activeSessionId = newSessionId;

          // Emit state update
          _updateState(_currentState.copyWith(
            sessionId: newSessionId,
            errorMessage: 'Connected - session synced to server',
          ));

          // Clear validation message after 2 seconds
          Timer(const Duration(seconds: 2), () {
            if (_currentState.isActive) {
              _updateState(_currentState.copyWith(
                errorMessage: null,
              ));
            }
          });

          // Notify watch with new session ID
          await _watchService.sendSessionIdToWatch(newSessionId);
        } else {
          AppLogger.warning(
              '[LIFECYCLE] Session changed during sync, skipping state update');
        }
      }
    } catch (e) {
      AppLogger.warning(
          '[LIFECYCLE] Failed to sync offline session: $e. Will retry on next connectivity event.');

      // Emit error state if session is still active
      if (_currentState.isActive) {
        _updateState(_currentState.copyWith(
          errorMessage: 'Sync failed - continuing in offline mode',
        ));

        Timer(const Duration(seconds: 3), () {
          if (_currentState.isActive) {
            _updateState(_currentState.copyWith(
              errorMessage: null,
            ));
          }
        });
      }
    }
  }

  /// Sync offline sessions to backend when connectivity is restored
  void _syncOfflineSessionsInBackground() {
    // Run sync in background without blocking UI
    Timer(const Duration(seconds: 2), () async {
      try {
        await _syncOfflineSessions();
      } catch (e) {
        AppLogger.warning(
            '[LIFECYCLE] Background offline session sync failed: $e');
        // Schedule retry in 30 seconds
        Timer(const Duration(seconds: 30),
            () => _syncOfflineSessionsInBackground());
      }
    });
  }

  /// Sync stored offline sessions to backend
  Future<void> _syncOfflineSessions() async {
    try {
      final offlineSessionsData =
          await _storageService.getObject('offline_sessions');
      if (offlineSessionsData == null) {
        AppLogger.info('[LIFECYCLE] No offline sessions to sync');
        return;
      }

      final offlineSessions = offlineSessionsData is Map &&
              offlineSessionsData.containsKey('sessions')
          ? List<Map<String, dynamic>>.from(
              offlineSessionsData['sessions'] as List)
          : offlineSessionsData is List
              ? List<Map<String, dynamic>>.from(offlineSessionsData as List)
              : [offlineSessionsData as Map<String, dynamic>];
      if (offlineSessions.isEmpty) {
        AppLogger.info('[LIFECYCLE] No offline sessions to sync');
        return;
      }

      AppLogger.info(
          '[LIFECYCLE] Found ${offlineSessions.length} offline sessions to sync');

      for (final sessionData in offlineSessions) {
        try {
          // Create session with stored session data
          final createResponse = await _apiClient.post('/rucks', {
            'ruck_weight_kg': sessionData['ruckWeightKg'],
            'user_weight_kg': sessionData['userWeightKg'],
            'notes': sessionData['notes'] ?? '',
            'is_manual': false, // These are active sessions that were offline
          });

          final newSessionId = createResponse['id']?.toString();
          if (newSessionId != null && newSessionId.isNotEmpty) {
            AppLogger.info(
                '[LIFECYCLE] Successfully synced offline session. New session ID: $newSessionId');

            // Remove from offline sessions list
            offlineSessions.removeWhere(
                (session) => session['sessionId'] == sessionData['sessionId']);
          }
        } catch (e) {
          AppLogger.warning(
              '[LIFECYCLE] Failed to sync offline session: $e. Will retry on next connectivity event.');
        }
      }

      // Update stored offline sessions
      await _storageService
          .setObject('offline_sessions', {'sessions': offlineSessions});
    } catch (e) {
      AppLogger.error('[LIFECYCLE] Error during offline session sync: $e');
      rethrow;
    }
  }

  /// Start sophisticated timer system using TimerCoordinator
  void _startSophisticatedTimerSystem() {
    AppLogger.info('[LIFECYCLE] Starting sophisticated timer system');
    _timerCoordinator.startTimerSystem();
  }

  /// Stop sophisticated timer system
  void _stopSophisticatedTimerSystem() {
    AppLogger.info('[LIFECYCLE] Stopping sophisticated timer system');
    _timerCoordinator.stopTimerSystem();
  }

  int _mainTickCount = 0;

  /// Main tick callback - called every second
  void _onMainTick() {
    if (!_currentState.isActive) return;

    // CRITICAL: Don't update duration when paused - respect pausedAt state
    if (_currentState.pausedAt != null) {
      AppLogger.debug(
          '[LIFECYCLE] _onMainTick: Session paused, not updating duration');
      return;
    }

    _mainTickCount++;
    final now = DateTime.now();
    final newDuration = _sessionStartTime != null
        ? now.difference(_sessionStartTime!)
        : Duration.zero;

    _updateState(_currentState.copyWith(
      duration: newDuration,
    ));

    // Log to verify timer is actually ticking
    if (_mainTickCount % 5 == 0) {
      AppLogger.info('[LIFECYCLE] Timer tick #$_mainTickCount: ${newDuration.inSeconds}s');
    }
  }

  /// Watchdog tick callback - called every 30 seconds
  void _onWatchdogTick() {
    if (!_currentState.isActive) return;

    // Watchdog logic for session health monitoring
    final now = DateTime.now();
    final sessionUptime = _sessionStartTime != null
        ? now.difference(_sessionStartTime!).inSeconds
        : 0;

    if (sessionUptime > 300) {
      // After 5 minutes
      // Check if we're still getting location updates
      AppLogger.debug(
          '[LIFECYCLE] Watchdog: Session health check at ${sessionUptime}s uptime');

      // Add session health validation here
      _validateSessionHealth();
    }
  }

  /// Persistence tick callback - called every minute
  void _onPersistenceTick() {
    if (!_currentState.isActive) return;
    _persistSessionInBackground();
  }

  /// Batch upload tick callback - called every 2 minutes
  void _onBatchUploadTick() {
    if (!_currentState.isActive) return;

    // Trigger batch upload of session data
    _triggerBatchUpload();
  }

  /// Connectivity check callback - called every 15 seconds
  void _onConnectivityCheck() {
    if (!_currentState.isActive) return;

    // Check connectivity status and trigger actions if needed
    _checkConnectivityStatus();
  }

  /// Memory check callback - called every 30 seconds
  void _onMemoryCheck() {
    if (!_currentState.isActive) return;

    // Check memory usage and cleanup if needed
    _checkMemoryUsage();
  }

  /// Pace calculation callback - called every 5 seconds
  void _onPaceCalculation() {
    if (!_currentState.isActive) return;

    // Trigger pace recalculation in location manager
    AppLogger.debug('[LIFECYCLE] Triggering pace recalculation');
    // This would be communicated to the location manager
  }

  /// Validate session health
  void _validateSessionHealth() {
    // Add session health validation logic here
    // - Check if location manager is responding
    // - Check if heart rate manager is responding
    // - Check if upload queues are growing too large
    // - Check if memory usage is excessive

    AppLogger.debug('[LIFECYCLE] Session health validation completed');
  }

  /// Trigger batch upload
  void _triggerBatchUpload() {
    // Coordinate with upload manager to trigger batch upload
    AppLogger.debug('[LIFECYCLE] Triggering batch upload');
    // This would be communicated to the upload manager
  }

  /// Check connectivity status
  void _checkConnectivityStatus() {
    // Additional connectivity checks beyond the main subscription
    AppLogger.debug('[LIFECYCLE] Checking connectivity status');
  }

  /// Check memory usage
  void _checkMemoryUsage() {
    // Monitor memory usage and trigger cleanup if needed
    AppLogger.debug('[LIFECYCLE] Checking memory usage');
  }

  /// Get timer system statistics
  Map<String, dynamic> getTimerStats() {
    return _timerCoordinator.getTimerStats();
  }

  /// Update timer intervals for performance optimization
  void updateTimerIntervals({
    Duration? mainInterval,
    Duration? watchdogInterval,
    Duration? persistenceInterval,
    Duration? batchUploadInterval,
  }) {
    _timerCoordinator.updateTimerIntervals(
      mainInterval: mainInterval,
      watchdogInterval: watchdogInterval,
      persistenceInterval: persistenceInterval,
      batchUploadInterval: batchUploadInterval,
    );
  }

  /// Notify coordinator of recovery completion with metrics
  void _notifyRecoveryCompleted(Map<String, dynamic> recoveredMetrics) {
    if (_onRecoveryCompleted != null) {
      _onRecoveryCompleted!(recoveredMetrics);
      AppLogger.info(
          '[LIFECYCLE] Recovery metrics sent to coordinator: $recoveredMetrics');
    } else {
      AppLogger.warning(
          '[LIFECYCLE] No recovery callback set - metrics not sent');
    }
  }

  /// Calculate distance between last saved location and current location
  Future<double> _calculateGapDistance(LocationPoint lastSavedLocation) async {
    try {
      // Get the location service from the service locator
      final locationService = GetIt.I<LocationService>();

      // Check location permission first
      bool hasPermission = await locationService.hasLocationPermission();
      if (!hasPermission) {
        AppLogger.warning(
            '[LIFECYCLE] Location permission not available for gap calculation');
        return 0.0;
      }

      // Get current position with extended timeout for crash recovery scenarios
      final currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      // Calculate distance using Haversine formula
      final distance = _haversineDistance(
        lastSavedLocation.latitude,
        lastSavedLocation.longitude,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      AppLogger.info(
          '[LIFECYCLE] Gap distance from (${lastSavedLocation.latitude}, ${lastSavedLocation.longitude}) '
          'to (${currentPosition.latitude}, ${currentPosition.longitude}): ${distance}km');

      return distance;
    } catch (e) {
      AppLogger.warning(
          '[LIFECYCLE] Could not get current location for gap calculation: $e');
      return 0.0;
    }
  }

  /// Calculate distance between two GPS points using Haversine formula
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371.0; // Earth radius in kilometers

    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
}
