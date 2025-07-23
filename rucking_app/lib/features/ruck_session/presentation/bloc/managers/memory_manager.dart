import 'dart:async';

import '../../../../../core/services/storage_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages session memory including data persistence and restoration
class MemoryManager implements SessionManager {
  final StorageService _storageService;
  
  final StreamController<MemoryState> _stateController;
  MemoryState _currentState;
  
  // Memory state
  String? _activeSessionId;
  final Map<String, dynamic> _sessionData = {};
  bool _autoSaveEnabled = true;
  Timer? _autoSaveTimer;
  
  static const Duration _autoSaveInterval = Duration(seconds: 30);
  static const String _sessionDataKeyPrefix = 'session_data_';
  static const String _lastSessionKey = 'last_active_session';
  
  MemoryManager({
    required StorageService storageService,
  })  : _storageService = storageService,
        _stateController = StreamController<MemoryState>.broadcast(),
        _currentState = const MemoryState();

  @override
  Stream<SessionManagerState> get stateStream => _stateController.stream;

  @override
  SessionManagerState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is SessionPaused) {
      await _onSessionPaused(event);
    } else if (event is SessionResumed) {
      await _onSessionResumed(event);
    } else if (event is MemoryUpdated) {
      await _onMemoryUpdated(event);
    } else if (event is RestoreSessionRequested) {
      await _onRestoreSessionRequested(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _sessionData.clear();
    
    // Initialize session data
    _sessionData['sessionId'] = _activeSessionId;
    _sessionData['startTime'] = DateTime.now().toIso8601String();
    _sessionData['ruckWeightKg'] = event.ruckWeightKg;
    _sessionData['userWeightKg'] = event.userWeightKg;
    
    // Save as last active session
    await _storageService.setString(_lastSessionKey, _activeSessionId ?? '');
    
    // Start auto-save timer
    _startAutoSaveTimer();
    
    _updateState(_currentState.copyWith(
      hasActiveSession: true,
      lastSaveTime: DateTime.now(),
      errorMessage: null,
    ));
    
    AppLogger.info('[MEMORY_MANAGER] Session started: $_activeSessionId');
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    // Final save before stopping
    await _saveSessionData();
    
    // Clear last active session
    await _storageService.remove(_lastSessionKey);
    
    // Stop auto-save timer
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    
    _activeSessionId = null;
    _sessionData.clear();
    
    _updateState(const MemoryState());
    
    AppLogger.info('[MEMORY_MANAGER] Session stopped and cleared');
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    _sessionData['isPaused'] = true;
    _sessionData['pauseTime'] = DateTime.now().toIso8601String();
    
    await _saveSessionData();
    
    AppLogger.debug('[MEMORY_MANAGER] Session paused');
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    _sessionData['isPaused'] = false;
    _sessionData.remove('pauseTime');
    
    await _saveSessionData();
    
    AppLogger.debug('[MEMORY_MANAGER] Session resumed');
  }

  Future<void> _onMemoryUpdated(MemoryUpdated event) async {
    _sessionData[event.key] = event.value;
    
    // Save immediately for important updates
    if (event.immediate) {
      await _saveSessionData();
    }
    
    AppLogger.debug('[MEMORY_MANAGER] Memory updated: ${event.key}');
  }

  Future<void> _onRestoreSessionRequested(RestoreSessionRequested event) async {
    _updateState(_currentState.copyWith(isRestoring: true));
    
    try {
      String? sessionId = event.sessionId;
      
      // If no session ID provided, try to get last active session
      if (sessionId == null) {
        sessionId = await _storageService.getString(_lastSessionKey);
      }
      
      if (sessionId == null || sessionId.isEmpty) {
        throw Exception('No session to restore');
      }
      
      // Load session data
      final key = '$_sessionDataKeyPrefix$sessionId';
      final data = await _storageService.getObject(key);
      
      if (data == null) {
        throw Exception('Session data not found');
      }
      
      _activeSessionId = sessionId;
      _sessionData.clear();
      _sessionData.addAll(data);
      
      // Start auto-save timer
      _startAutoSaveTimer();
      
      _updateState(_currentState.copyWith(
        hasActiveSession: true,
        isRestoring: false,
        restoredData: Map<String, dynamic>.from(_sessionData),
      ));
      
      AppLogger.info('[MEMORY_MANAGER] Session restored: $sessionId');
      
    } catch (e) {
      AppLogger.error('[MEMORY_MANAGER] Failed to restore session: $e');
      _updateState(_currentState.copyWith(
        isRestoring: false,
        errorMessage: 'Failed to restore session: $e',
      ));
    }
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    
    if (!_autoSaveEnabled) return;
    
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      _saveSessionData();
    });
  }

  Future<void> _saveSessionData() async {
    if (_activeSessionId == null) return;
    
    try {
      final key = '$_sessionDataKeyPrefix$_activeSessionId';
      await _storageService.setObject(key, _sessionData);
      
      _updateState(_currentState.copyWith(
        lastSaveTime: DateTime.now(),
      ));
      
      AppLogger.debug('[MEMORY_MANAGER] Session data saved');
      
    } catch (e) {
      AppLogger.error('[MEMORY_MANAGER] Failed to save session data: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to save session data',
      ));
    }
  }

  /// Get a value from session memory
  T? getValue<T>(String key) {
    return _sessionData[key] as T?;
  }

  /// Set a value in session memory
  void setValue(String key, dynamic value, {bool immediate = false}) {
    handleEvent(MemoryUpdated(key: key, value: value, immediate: immediate));
  }

  /// Clear all session data
  Future<void> clearSessionData() async {
    if (_activeSessionId == null) return;
    
    final key = '$_sessionDataKeyPrefix$_activeSessionId';
    await _storageService.remove(key);
    
    _sessionData.clear();
    
    AppLogger.info('[MEMORY_MANAGER] Session data cleared');
  }



  /// Enable or disable auto-save
  void setAutoSaveEnabled(bool enabled) {
    _autoSaveEnabled = enabled;
    
    if (enabled && _activeSessionId != null) {
      _startAutoSaveTimer();
    } else {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
    }
  }

  void _updateState(MemoryState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> dispose() async {
    await _saveSessionData();
    _autoSaveTimer?.cancel();
    await _stateController.close();
  }

  @override
  Future<void> checkForCrashedSession() async {
    // No-op: This manager doesn't handle session recovery
    return;
  }
  
  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: This manager doesn't handle crash recovery data
    return;
  }

  // Getters for coordinator
  bool get hasActiveSession => _currentState.hasActiveSession;
  Map<String, dynamic> get sessionData => Map.unmodifiable(_sessionData);
}
