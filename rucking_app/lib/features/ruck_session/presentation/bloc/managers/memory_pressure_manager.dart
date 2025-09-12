import 'dart:async';
import 'dart:io';

import '../../../../../core/services/location_service.dart' as location_service;
import '../../../../../core/utils/app_logger.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages memory pressure detection and adaptive system behavior
class MemoryPressureManager implements SessionManager {
  final location_service.LocationService _locationService;
  final StreamController<MemoryPressureState> _stateController;
  MemoryPressureState _currentState;

  // Memory monitoring
  Timer? _memoryCheckTimer;
  static const Duration _memoryCheckInterval = Duration(seconds: 30);

  // Adaptive behavior tracking
  LocationTrackingMode? _lastLocationMode;
  DateTime? _lastLocationModeChange;
  Timer? _adaptiveUploadTimer;

  // Session tracking
  String? _activeSessionId;
  bool _isSessionActive = false;

  MemoryPressureManager({
    required location_service.LocationService locationService,
  })  : _locationService = locationService,
        _stateController = StreamController<MemoryPressureState>.broadcast(),
        _currentState = const MemoryPressureState();

  @override
  Stream<MemoryPressureState> get stateStream => _stateController.stream;

  @override
  MemoryPressureState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is MemoryPressureDetected) {
      await _onMemoryPressureDetected(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _isSessionActive = true;

    // Start memory monitoring
    _startMemoryMonitoring();

    _updateState(_currentState.copyWith(
      isActive: true,
      sessionId: event.sessionId,
    ));
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    // Stop memory monitoring
    _memoryCheckTimer?.cancel();
    _memoryCheckTimer = null;

    // Reset adaptive behavior
    _adaptiveUploadTimer?.cancel();
    _adaptiveUploadTimer = null;

    _activeSessionId = null;
    _isSessionActive = false;

    _updateState(const MemoryPressureState());
  }

  /// Handle system memory pressure events (triggered by Flutter's didHaveMemoryPressure)
  Future<void> _onMemoryPressureDetected(MemoryPressureDetected event) async {
    AppLogger.critical(
        'System memory pressure detected - executing emergency data preservation');

    try {
      if (_isSessionActive && _activeSessionId != null) {
        // CRITICAL: Preserve data at all costs
        AppLogger.info(
            'Memory pressure: Emergency upload for session $_activeSessionId');

        // Emergency upload handled by UploadManager through coordinator pattern
        // The coordinator will trigger batch uploads when memory pressure is detected

        // Force garbage collection to free memory
        _forceGarbageCollection();

        // Reduce location tracking frequency to save memory and battery
        _adjustLocationTrackingForMemoryPressure();

        // Increase upload frequency to prevent data loss
        _increaseUploadFrequency();

        AppLogger.info(
            'Memory pressure: Emergency data preservation completed');
      } else {
        AppLogger.info(
            'Memory pressure: No active session - system cleanup only');
        _forceGarbageCollection();
      }
    } catch (e) {
      AppLogger.error('Memory pressure handling failed: $e');

      // Report memory pressure handling failure
      AppLogger.critical(
        'memory_pressure_handling_failed',
        exception: {
          'error': e.toString(),
          'session_id': _activeSessionId,
          'is_session_active': _isSessionActive,
        }.toString(),
      );
    }

    _updateState(_currentState.copyWith(
      lastPressureDetected: DateTime.now(),
      pressureLevel: MemoryPressureLevel.critical,
    ));
  }

  void _startMemoryMonitoring() {
    _memoryCheckTimer?.cancel();
    _memoryCheckTimer = Timer.periodic(_memoryCheckInterval, (_) {
      _checkMemoryPressure();
    });
  }

  /// Check for memory pressure and take preventive action WITHOUT losing data
  void _checkMemoryPressure() {
    try {
      final memoryInfo = _getMemoryInfo();
      final memoryUsageMb = memoryInfo['memory_usage_mb'] as double;

      MemoryPressureLevel level = MemoryPressureLevel.normal;

      // Determine pressure level and take action
      if (memoryUsageMb > 500.0) {
        level = MemoryPressureLevel.critical;
        AppLogger.critical('CRITICAL MEMORY USAGE',
            exception: {
              'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
              'session_id': _activeSessionId,
            }.toString());

        // Emergency mode for critical memory pressure
        _adjustLocationTrackingMode(LocationTrackingMode.emergency);
        _forceGarbageCollection();
      } else if (memoryUsageMb > 400.0) {
        level = MemoryPressureLevel.high;
        AppLogger.warning(
            'High memory pressure detected: memory_usage_mb=${memoryUsageMb.toStringAsFixed(1)}, session_id=$_activeSessionId');

        // Switch to power save mode for aggressive memory conservation
        _adjustLocationTrackingMode(LocationTrackingMode.powerSave);
      } else if (memoryUsageMb > 350.0) {
        level = MemoryPressureLevel.moderate;
        _increaseUploadFrequency();
        // Switch to power save mode for moderate memory conservation
        _adjustLocationTrackingMode(LocationTrackingMode.powerSave);
      } else if (memoryUsageMb > 300.0) {
        level = MemoryPressureLevel.low;
        // Proactive: Switch to balanced mode before pressure becomes critical
        _adjustLocationTrackingMode(LocationTrackingMode.balanced);
      } else if (memoryUsageMb < 200.0) {
        level = MemoryPressureLevel.normal;
        // Recovery: Return to high accuracy when memory is available
        _adjustLocationTrackingMode(LocationTrackingMode.highAccuracy);
      }

      _updateState(_currentState.copyWith(
        memoryUsageMb: memoryUsageMb,
        pressureLevel: level,
        lastCheckTime: DateTime.now(),
      ));
    } catch (e) {
      AppLogger.error('Failed to check memory pressure: $e');
    }
  }

  /// Get current memory usage information
  Map<String, dynamic> _getMemoryInfo() {
    try {
      // Get current process memory usage
      final processInfo = ProcessInfo.currentRss;
      final memoryUsageMb = processInfo / (1024 * 1024); // Convert bytes to MB

      return {
        'memory_usage_mb': memoryUsageMb,
      };
    } catch (e) {
      AppLogger.warning('Failed to get memory info: $e');
      return {
        'memory_usage_mb': 0.0,
      };
    }
  }

  /// Force garbage collection to free memory
  void _forceGarbageCollection() {
    try {
      // Trigger garbage collection indirectly by creating/destroying objects
      // Note: Dart doesn't provide direct GC control for user code
      for (int i = 0; i < 3; i++) {
        // Create temporary objects to encourage GC
        final temp = List.generate(1000, (index) => index);
        temp.clear();
      }

      AppLogger.debug('Garbage collection encouragement completed');
    } catch (e) {
      AppLogger.error('Error during garbage collection attempt: $e');
    }
  }

  /// Adjust location tracking frequency to reduce memory pressure
  void _adjustLocationTrackingForMemoryPressure() {
    try {
      AppLogger.info(
          '📍 Reducing location tracking frequency due to memory pressure');

      // Switch to power save mode to reduce GPS frequency and memory usage
      _locationService.adjustTrackingFrequency(
          location_service.LocationTrackingMode.powerSave);

      AppLogger.info(
          '✅ Location tracking frequency reduced to power save mode');
    } catch (e) {
      AppLogger.error('Failed to adjust location tracking frequency: $e');
    }
  }

  /// Smart location tracking mode adjustment with debouncing
  /// Convert manager state LocationTrackingMode to location service LocationTrackingMode
  location_service.LocationTrackingMode _convertToLocationServiceMode(
      LocationTrackingMode mode) {
    switch (mode) {
      case LocationTrackingMode.highAccuracy:
        return location_service.LocationTrackingMode.high;
      case LocationTrackingMode.balanced:
        return location_service.LocationTrackingMode.balanced;
      case LocationTrackingMode.powerSave:
        return location_service.LocationTrackingMode.powerSave;
      case LocationTrackingMode.emergency:
        return location_service.LocationTrackingMode.emergency;
    }
  }

  void _adjustLocationTrackingMode(LocationTrackingMode targetMode) {
    try {
      // Debounce rapid mode changes (don't change more than once per 30 seconds)
      final now = DateTime.now();
      if (_lastLocationModeChange != null &&
          now.difference(_lastLocationModeChange!).inSeconds < 30 &&
          _lastLocationMode == targetMode) {
        return; // Skip redundant changes
      }

      // Only adjust if the mode is actually different
      if (_lastLocationMode != targetMode) {
        AppLogger.info(
            '🎯 Adjusting location tracking mode: ${_lastLocationMode ?? "unknown"} → $targetMode');

        _locationService
            .adjustTrackingFrequency(_convertToLocationServiceMode(targetMode));
        _lastLocationMode = targetMode;
        _lastLocationModeChange = now;

        AppLogger.info('✅ Location tracking mode adjusted to: $targetMode');

        _updateState(_currentState.copyWith(
          currentLocationMode: targetMode,
          lastModeChange: now,
        ));
      }
    } catch (e) {
      AppLogger.error(
          'Failed to adjust location tracking mode to $targetMode: $e');
    }
  }

  /// Increase upload frequency during high memory usage
  void _increaseUploadFrequency() {
    try {
      _adaptiveUploadTimer?.cancel();

      // Switch to 2-minute uploads during memory pressure
      // Upload frequency coordination handled by UploadManager integration
      AppLogger.info(
          '⏱️ Increased upload frequency to 2 minutes due to memory pressure');

      _updateState(_currentState.copyWith(
        isAdaptiveUploadActive: true,
        adaptiveUploadInterval: const Duration(minutes: 2),
      ));
    } catch (e) {
      AppLogger.error('Failed to increase upload frequency: $e');
    }
  }

  void _updateState(MemoryPressureState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> dispose() async {
    _memoryCheckTimer?.cancel();
    _adaptiveUploadTimer?.cancel();
    await _stateController.close();
  }

  // Getters for other managers
  double get currentMemoryUsageMb =>
      _getMemoryInfo()['memory_usage_mb'] as double;
  MemoryPressureLevel get currentPressureLevel => _currentState.pressureLevel;
  bool get isHighMemoryPressure =>
      _currentState.pressureLevel.index >= MemoryPressureLevel.high.index;

  @override
  Future<void> checkForCrashedSession() async {
    // No-op: This manager doesn't handle session recovery
  }

  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: This manager doesn't handle crash recovery data
  }
}
