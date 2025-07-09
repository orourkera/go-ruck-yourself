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
import '../../../../../core/utils/app_logger.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../domain/models/ruck_session.dart';
import '../events/session_events.dart' as manager_events;
import '../active_session_bloc.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages session lifecycle operations (start, stop, pause, resume)
class SessionLifecycleManager implements SessionManager {
  final SessionRepository _sessionRepository;
  final AuthService _authService;
  final WatchService _watchService;
  final StorageService _storageService;
  final ApiClient _apiClient;
  
  final StreamController<SessionLifecycleState> _stateController;
  SessionLifecycleState _currentState;
  
  DateTime? _sessionStartTime;
  String? _activeSessionId;
  Timer? _ticker;
  
  SessionLifecycleManager({
    required SessionRepository sessionRepository,
    required AuthService authService,
    required WatchService watchService,
    required StorageService storageService,
    required ApiClient apiClient,
  })  : _sessionRepository = sessionRepository,
        _authService = authService,
        _watchService = watchService,
        _storageService = storageService,
        _apiClient = apiClient,
        _stateController = StreamController<SessionLifecycleState>.broadcast(),
        _currentState = const SessionLifecycleState();

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
      
      _updateState(_currentState.copyWith(isLoading: true));
      
      // Create session ID
      final sessionId = event.sessionId ?? const Uuid().v4();
      _activeSessionId = sessionId;
      _sessionStartTime = DateTime.now();
      
      // Create initial session
      await _createInitialSession(
        sessionId: sessionId,
        ruckWeightKg: event.ruckWeightKg ?? 0.0,
        userWeightKg: event.userWeightKg ?? 70.0, // Default user weight
        notes: null, // Optional field - can be passed in future versions
        eventId: null, // Optional field - can be passed in future versions
      );
      
      // Get user metric preference
      final preferMetric = await _getUserMetricPreference();
      
      // Start watch session
      await _watchService.startSessionOnWatch(event.ruckWeightKg ?? 0.0, isMetric: preferMetric);
      await _watchService.sendSessionIdToWatch(sessionId);
      
      _updateState(_currentState.copyWith(
        isActive: true,
        sessionId: sessionId,
        startTime: _sessionStartTime,
        duration: Duration.zero,
        isLoading: false,
        errorMessage: null,
      ));
      
      AppLogger.debug('Session lifecycle started successfully: $sessionId');
      
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
      AppLogger.info('Stopping ruck session');
      
      _updateState(_currentState.copyWith(isSaving: true));
      
      // Cancel timers
      _ticker?.cancel();
      _ticker = null;
      
      // Stop watch session
      await _watchService.endSessionOnWatch();
      
      // Clear active session
      _activeSessionId = null;
      _sessionStartTime = null;
      
      _updateState(const SessionLifecycleState());
      
      AppLogger.info('Session lifecycle stopped successfully');
      
    } catch (e) {
      AppLogger.error('Error stopping session: $e');
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
    ));
  }

  Future<void> _onSessionResumed(manager_events.SessionResumed event) async {
    if (_currentState.isActive) return;
    
    AppLogger.info('Resuming session');
    
    // Resume timers
    _startTimer();
    
    // Update watch
    await _watchService.resumeSessionOnWatch();
    
    _updateState(_currentState.copyWith(
      isActive: true,
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

  Future<void> _createInitialSession({
    required String sessionId,
    required double ruckWeightKg,
    required double userWeightKg,
    String? notes,
    String? eventId,
  }) async {
    try {
      // Create session in backend
      await _apiClient.post('/sessions', {
        'id': sessionId,
        'ruck_weight_kg': ruckWeightKg,
        'user_weight_kg': userWeightKg,
        'notes': notes,
        'event_id': eventId,
        'platform': Platform.isIOS ? 'iOS' : 'Android',
        'start_time': _sessionStartTime!.toIso8601String(),
      });
      
      AppLogger.info('Initial session created in backend: $sessionId');
    } catch (e) {
      AppLogger.warning('Failed to create initial session in backend: $e');
      // Continue with offline session
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
  Future<void> dispose() async {
    _ticker?.cancel();
    await _stateController.close();
  }

  // Getters for other managers to access session info
  String? get activeSessionId => _activeSessionId;
  DateTime? get sessionStartTime => _sessionStartTime;
  bool get isSessionActive => _currentState.isActive;
  bool get isPaused => !_currentState.isActive && _activeSessionId != null;
}
