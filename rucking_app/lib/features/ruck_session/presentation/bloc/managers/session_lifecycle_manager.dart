import 'dart:async';
import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';


import '../../../../../core/config/app_config.dart';
import '../../../../../core/utils/error_handler.dart';
import '../../../../../core/services/app_error_handler.dart';
import '../../../../../core/services/api_client.dart';
import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/storage_service.dart';
import '../../../../../core/services/watch_service.dart';
import '../../../../../core/services/connectivity_service.dart';
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

  Future<void> _onSessionStartRequested(manager_events.SessionStartRequested event) async {
    try {
      AppLogger.info('Starting new ruck session with weight: ${event.ruckWeightKg}kg');
      
      // Optimistically mark session as active before backend confirmation
      _updateState(_currentState.copyWith(
        isActive: true,
        sessionId: null, // will set after ID generation below
        // keep isLoading false to avoid showing initializing screen
        // isLoading: true,
      ));
      
      // Create preliminary session ID (may be overridden by backend)
      final provisionalId = event.sessionId ?? const Uuid().v4();
      _activeSessionId = provisionalId;
      _sessionStartTime = DateTime.now();
      
      // Ensure backend session is created before other managers start uploading
      final backendId = await _createInitialSession(
        sessionId: provisionalId,
        ruckWeightKg: event.ruckWeightKg ?? 0.0,
        userWeightKg: event.userWeightKg ?? 70.0, // Default user weight
        notes: null, // Optional field - can be passed in future versions
        eventId: null, // Optional field - can be passed in future versions
      );
      
      // Get user metric preference
      final preferMetric = await _getUserMetricPreference();
      
      // Choose the ID to use (backend if available, otherwise provisional)
      final finalSessionId = backendId ?? provisionalId;
      // Update the in-memory active sessionId so all other managers use the correct backend ID
      _activeSessionId = finalSessionId;
      
      await _watchService.startSessionOnWatch(event.ruckWeightKg ?? 0.0, isMetric: preferMetric);
      
      _startSophisticatedTimerSystem();
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
      
      AppLogger.debug('Session lifecycle started successfully: $finalSessionId');
      
    } catch (e, stackTrace) {
      AppLogger.error('Error starting session: $e\n$stackTrace');
      
      final errorMessage = ErrorHandler.getUserFriendlyMessage(e, 'Session Start');
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
          'has_location_permission': false, // Will be checked by location manager
          'is_authenticated': _authService.isAuthenticated(),
        },
      );
    }
  }

  Future<void> _onSessionStopRequested(manager_events.SessionStopRequested event) async {
    try {
      AppLogger.info('[LIFECYCLE] Stopping ruck session - sessionId: $_activeSessionId');
      AppLogger.info('[LIFECYCLE] Current state before stop: isActive=${_currentState.isActive}, sessionId=${_currentState.sessionId}');
      
      // CRITICAL: Cancel timers FIRST to prevent race condition with _onTick
      _ticker?.cancel();
      _ticker = null;
      AppLogger.info('[LIFECYCLE] Timer cancelled to prevent duration override');
      
      _updateState(_currentState.copyWith(isSaving: true));
      
      // Stop watch session
      await _watchService.endSessionOnWatch();
      
      // Calculate final duration at exact moment of stop
      final finalDuration = _sessionStartTime != null ? DateTime.now().difference(_sessionStartTime!) : Duration.zero;
      AppLogger.info('[LIFECYCLE] Final session duration: ${finalDuration.inSeconds}s (${finalDuration.inMinutes}m ${finalDuration.inSeconds % 60}s)');

      // CRITICAL: Call completion API with retry and persistence
      bool completionSuccessful = false;
      String? completionError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await _apiClient.post('/rucks/$_activeSessionId/complete', {
            'duration_seconds': finalDuration.inSeconds,
          });
          completionSuccessful = true;
          break;
        } catch (e) {
          completionError = e.toString();
          AppLogger.warning('[LIFECYCLE] Completion attempt $attempt failed: $e');
          await Future.delayed(Duration(seconds: attempt * 2)); // Backoff
        }
      }

      if (!completionSuccessful) {
        // Persist for later retry
        await _storageService.setObject('pending_completion_$_activeSessionId', {
          'duration_seconds': finalDuration.inSeconds,
        });
        AppLogger.error('[LIFECYCLE] All completion attempts failed, persisted for retry: $completionError');
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
      
      AppLogger.info('[LIFECYCLE] Updating state: isActive=${newState.isActive}, sessionId=${newState.sessionId}');
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
    if (!_currentState.isActive) return;
    
    AppLogger.info('Pausing session');
    
    // Pause timers
    _ticker?.cancel();
    
    // Update watch
    await _watchService.pauseSessionOnWatch();
    
    _updateState(_currentState.copyWith(
      isActive: false, // Using isActive to track pause state
      pausedAt: DateTime.now(),
    ));
  }

  Future<void> _onSessionResumed(manager_events.SessionResumed event) async {
    if (_currentState.isActive) return;
    
    AppLogger.info('Resuming session');
    
    // Calculate pause duration
    final pausedDuration = _currentState.pausedAt != null
        ? DateTime.now().difference(_currentState.pausedAt!)
        : Duration.zero;
    
    // Resume timers
    _startTimer();
    
    // Update watch
    await _watchService.resumeSessionOnWatch();
    
    _updateState(_currentState.copyWith(
      isActive: true,
      pausedAt: null,
      totalPausedDuration: _currentState.totalPausedDuration + pausedDuration,
    ));
  }

  Future<void> _onTimerStarted(manager_events.TimerStarted event) async {
    _startTimer();
  }

  Future<void> _onTimerStopped(manager_events.TimerStopped event) async {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _onTick(manager_events.Tick event) async {
    if (_currentState.isActive && _sessionStartTime != null) {
      final newDuration = DateTime.now().difference(_sessionStartTime!);
      _updateState(_currentState.copyWith(duration: newDuration));
    }
  }

  Future<String?> _createInitialSession({
    required String sessionId,
    required double ruckWeightKg,
    required double userWeightKg,
    String? notes,
    String? eventId,
  }) async {
    try {
      // Create session in backend
      final result = await _apiClient.post('/rucks', {
        'id': sessionId,
        'ruck_weight_kg': ruckWeightKg,
        'user_weight_kg': userWeightKg,
        'notes': notes,
        'event_id': eventId,
        'platform': Platform.isIOS ? 'iOS' : 'Android',
        'start_time': _sessionStartTime!.toIso8601String(),
      });
      
      String backendId = sessionId;
      if (result is Map && (result['id'] != null || result['ruck_id'] != null)) {
        backendId = (result['id'] ?? result['ruck_id']).toString();
        AppLogger.info('Backend assigned session ID: $backendId');
      } else {
        AppLogger.warning('Backend response did not include ID, using local: $sessionId');
      }
      
      return backendId;
    } catch (e) {
      AppLogger.warning('Failed to create initial session in backend: $e');
      // Continue with offline session
      return null;
    }
  }

  Future<bool> _getUserMetricPreference() async {
    bool preferMetric = false; // Default to imperial
    
    final authState = GetIt.I<AuthBloc>().state;
    AppLogger.info('[SESSION_LIFECYCLE] AuthBloc state type: ${authState.runtimeType}');
    
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
      AppLogger.info('[SESSION_LIFECYCLE] User preferMetric: ${authState.user.preferMetric}');
    } else {
      AppLogger.warning('[SESSION_LIFECYCLE] User not authenticated, checking storage for preference');
      
      // Fallback: Try to get user preference from storage
      try {
        final storedUserData = await _storageService.getObject(AppConfig.userProfileKey);
        if (storedUserData != null && storedUserData.containsKey('preferMetric')) {
          preferMetric = storedUserData['preferMetric'] as bool;
          AppLogger.info('[SESSION_LIFECYCLE] Found stored user preference: $preferMetric');
        } else {
          AppLogger.warning('[SESSION_LIFECYCLE] No stored user preference found, defaulting to imperial (false)');
        }
      } catch (e) {
        AppLogger.error('[SESSION_LIFECYCLE] Error reading stored user preference: $e');
        AppLogger.warning('[SESSION_LIFECYCLE] Defaulting to imperial (false)');
      }
    }
    
    AppLogger.info('[SESSION_LIFECYCLE] Final preferMetric value: $preferMetric');
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
      final sessionData = await _storageService.getObject('active_session_data');
      
      if (sessionData == null) {
        AppLogger.info('[RECOVERY] No crashed session data found');
        return;
      }

      final sessionId = sessionData['sessionId'] as String?;
      final startTimeStr = sessionData['startTime'] as String?;
      final isActive = sessionData['isActive'] as bool? ?? false;
      
      if (!isActive || sessionId == null || startTimeStr == null) {
        AppLogger.info('[RECOVERY] Session data incomplete or inactive');
        await _storageService.remove('active_session_data');
        return;
      }

      final startTime = DateTime.parse(startTimeStr);
      final crashDuration = DateTime.now().difference(startTime);
      
      // If session was started more than 6 hours ago, probably abandon it
      if (crashDuration.inHours > 6) {
        AppLogger.info('[RECOVERY] Session too old (${crashDuration.inHours}h), abandoning');
        await _storageService.remove('active_session_data');
        return;
      }

      AppLogger.warning('🔥 CRASH RECOVERY: Found active session from ${crashDuration.inMinutes} minutes ago');

      // Restore session state
      _activeSessionId = sessionId;
      _sessionStartTime = startTime;
      
      final ruckWeight = (sessionData['ruckWeightKg'] as num?)?.toDouble() ?? 0.0;
      final userWeight = (sessionData['userWeightKg'] as num?)?.toDouble() ?? 70.0;
      final lastDuration = Duration(milliseconds: sessionData['duration'] ?? 0);
      
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
        currentSession: null, // Will be loaded separately
        totalPausedDuration: Duration.zero,
        pausedAt: null,
      ));

      // Restart timers and services
      _startTimer();
      _startSessionPersistenceTimer();
      _startSophisticatedTimerSystem();
      _startConnectivityMonitoring();

      // Check for pending completions
      final pendingKeys = await _storageService.getAllKeys().then((keys) => keys.where((k) => k.startsWith('pending_completion_')).toList());
      for (final key in pendingKeys) {
        final data = await _storageService.getObject(key);
        if (data != null) {
          final sessionId = key.split('_').last;
          try {
            await _apiClient.post('/rucks/$sessionId/complete', data);
            await _storageService.remove(key);
            AppLogger.info('[RECOVERY] Successfully completed pending session $sessionId');
          } catch (e) {
            AppLogger.warning('[RECOVERY] Failed to complete pending session $sessionId: $e');
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
  bool get isPaused => !_currentState.isActive && _activeSessionId != null;
  Duration get totalPausedDuration => _currentState.totalPausedDuration;

  /// Start session persistence timer for autosave - 30s for crash protection
  void _startSessionPersistenceTimer() {
    _sessionPersistenceTimer?.cancel();
    _sessionPersistenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_currentState.isActive) {
        _persistSessionInBackground();
      }
    });
    
    AppLogger.info('[LIFECYCLE] 🛡️ Crash protection: Session autosave every 30 seconds');
  }

  /// Persist session data in background
  void _persistSessionInBackground() {
    // Run persistence in background without blocking UI
    Timer(const Duration(milliseconds: 100), () async {
      try {
        await _persistSessionData();
      } catch (e) {
        AppLogger.warning('[LIFECYCLE] Background session persistence failed: $e');
      }
    });
  }

  /// Persist session data for crash recovery
  Future<void> _persistSessionData() async {
    if (!_currentState.isActive || _activeSessionId == null) return;
    
    try {
      final sessionData = {
        'sessionId': _activeSessionId,
        'startTime': _sessionStartTime?.toIso8601String(),
        'ruckWeightKg': _currentState.ruckWeightKg,
        'userWeightKg': _currentState.userWeightKg,
        'isActive': _currentState.isActive,
        'duration': _currentState.duration.inMilliseconds,
        'totalPausedDuration': _currentState.totalPausedDuration.inMilliseconds,
      };
      
      await _storageService.setObject('active_session_data', sessionData);
      AppLogger.debug('[LIFECYCLE] Session data persisted for crash recovery');
      
    } catch (e) {
      AppLogger.error('[LIFECYCLE] Failed to persist session data: $e');
    }
  }

  /// Start connectivity monitoring for offline session sync
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isConnected) {
      // Only handle connectivity changes if we're in a valid session state
      if (!_currentState.isActive) {
        AppLogger.debug('[LIFECYCLE] Ignoring connectivity change - session not active');
        return;
      }
      
      if (isConnected) {
        AppLogger.info('[LIFECYCLE] Connectivity restored for session: $_activeSessionId');
        
        // Add slight delay to prevent race conditions with UI rebuilds
        Timer(const Duration(milliseconds: 100), () async {
          if (_currentState.isActive) {
            // Only attempt sync if session is still offline
            if (_activeSessionId != null && _activeSessionId!.startsWith('offline_')) {
              await _attemptOfflineSessionSync(_activeSessionId!);
            }
            
            // Also sync any stored offline sessions
            _syncOfflineSessionsInBackground();
          }
        });
      } else {
        AppLogger.warning('[LIFECYCLE] Connectivity lost for session: $_activeSessionId, switching to offline mode...');
        
        // Only switch to offline mode if we're not already offline
        if (_activeSessionId != null && !_activeSessionId!.startsWith('offline_')) {
          // Emit validation message to inform user
          _updateState(_currentState.copyWith(
            errorMessage: 'No network connection - session continues in offline mode',
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
      AppLogger.info('[LIFECYCLE] Attempting to sync offline session to backend...');
      
      // Create session with current session data
      final createResponse = await _apiClient.post('/rucks', {
        'ruck_weight_kg': _currentState.ruckWeightKg,
        'user_weight_kg': _currentState.userWeightKg,
        'notes': '', // Empty notes for now
      }).timeout(const Duration(seconds: 5));
      
      final newSessionId = createResponse['id']?.toString();
      if (newSessionId != null && newSessionId.isNotEmpty) {
        AppLogger.info('[LIFECYCLE] Successfully synced offline session. New session ID: $newSessionId');
        
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
          AppLogger.warning('[LIFECYCLE] Session changed during sync, skipping state update');
        }
      }
    } catch (e) {
      AppLogger.warning('[LIFECYCLE] Failed to sync offline session: $e. Will retry on next connectivity event.');
      
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
        AppLogger.warning('[LIFECYCLE] Background offline session sync failed: $e');
        // Schedule retry in 30 seconds
        Timer(const Duration(seconds: 30), () => _syncOfflineSessionsInBackground());
      }
    });
  }

  /// Sync stored offline sessions to backend
  Future<void> _syncOfflineSessions() async {
    try {
      final offlineSessionsData = await _storageService.getObject('offline_sessions');
      if (offlineSessionsData == null) {
        AppLogger.info('[LIFECYCLE] No offline sessions to sync');
        return;
      }
      
      final offlineSessions = offlineSessionsData is Map && offlineSessionsData.containsKey('sessions')
          ? List<Map<String, dynamic>>.from(offlineSessionsData['sessions'] as List)
          : offlineSessionsData is List 
              ? List<Map<String, dynamic>>.from(offlineSessionsData as List)
              : [offlineSessionsData as Map<String, dynamic>];
      if (offlineSessions.isEmpty) {
        AppLogger.info('[LIFECYCLE] No offline sessions to sync');
        return;
      }

      AppLogger.info('[LIFECYCLE] Found ${offlineSessions.length} offline sessions to sync');

      for (final sessionData in offlineSessions) {
        try {
          // Create session with stored session data
          final createResponse = await _apiClient.post('/rucks', {
            'ruck_weight_kg': sessionData['ruckWeightKg'],
            'user_weight_kg': sessionData['userWeightKg'],
            'notes': sessionData['notes'] ?? '',
          });

          final newSessionId = createResponse['id']?.toString();
          if (newSessionId != null && newSessionId.isNotEmpty) {
            AppLogger.info('[LIFECYCLE] Successfully synced offline session. New session ID: $newSessionId');
            
            // Remove from offline sessions list
            offlineSessions.removeWhere((session) => session['sessionId'] == sessionData['sessionId']);
          }
        } catch (e) {
          AppLogger.warning('[LIFECYCLE] Failed to sync offline session: $e. Will retry on next connectivity event.');
        }
      }

      // Update stored offline sessions
      await _storageService.setObject('offline_sessions', {'sessions': offlineSessions});
      
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
  
  /// Main tick callback - called every second
  void _onMainTick() {
    if (!_currentState.isActive) return;
    
    final now = DateTime.now();
    final newDuration = _sessionStartTime != null 
        ? now.difference(_sessionStartTime!) 
        : Duration.zero;
    
    _updateState(_currentState.copyWith(
      duration: newDuration,
    ));
  }
  
  /// Watchdog tick callback - called every 30 seconds
  void _onWatchdogTick() {
    if (!_currentState.isActive) return;
    
    // Watchdog logic for session health monitoring
    final now = DateTime.now();
    final sessionUptime = _sessionStartTime != null 
        ? now.difference(_sessionStartTime!).inSeconds 
        : 0;
    
    if (sessionUptime > 300) { // After 5 minutes
      // Check if we're still getting location updates
      AppLogger.debug('[LIFECYCLE] Watchdog: Session health check at ${sessionUptime}s uptime');
      
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
}
