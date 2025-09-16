import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../../../core/utils/app_logger.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages session diagnostics, performance monitoring, and metrics tracking
class DiagnosticsManager implements SessionManager {
  final StreamController<DiagnosticsState> _stateController;
  DiagnosticsState _currentState;

  // Diagnostic timers and intervals
  Timer? _diagnosticsTimer;
  static const Duration _diagnosticsReportInterval = Duration(minutes: 5);

  // Performance counters
  int _locationUpdatesCount = 0;
  int _heartRateUpdatesCount = 0;
  int _apiCallsCount = 0;
  int _failedApiCallsCount = 0;
  double _totalApiLatencyMs = 0.0;
  int _locationValidationFailures = 0;
  int _gpsAccuracyWarnings = 0;
  double _worstGpsAccuracy = 0.0;
  int _pauseCount = 0;
  Duration _totalPausedTime = Duration.zero;
  int _backgroundTransitions = 0;
  int _foregroundTransitions = 0;

  // Session tracking
  String? _activeSessionId;
  DateTime? _sessionStartTime;

  DiagnosticsManager()
      : _stateController = StreamController<DiagnosticsState>.broadcast(),
        _currentState = const DiagnosticsState();

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
    } else if (event is LocationUpdated) {
      await _onLocationUpdated(event);
    } else if (event is HeartRateUpdated) {
      await _onHeartRateUpdated(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _sessionStartTime = DateTime.now();

    // Reset all counters
    _resetCounters();

    // Start diagnostic reporting
    _startDiagnosticsReporting();

    _updateState(_currentState.copyWith(
      isActive: true,
      sessionId: event.sessionId,
      startTime: _sessionStartTime,
    ));
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    // Generate final report
    if (_activeSessionId != null) {
      _reportSessionDiagnostics(isFinalReport: true);
    }

    // Stop diagnostic reporting
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;

    _activeSessionId = null;
    _sessionStartTime = null;

    _updateState(const DiagnosticsState());
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    _pauseCount++;
    _backgroundTransitions++;

    _updateState(_currentState.copyWith(
      pauseCount: _pauseCount,
      backgroundTransitions: _backgroundTransitions,
    ));
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    _foregroundTransitions++;

    _updateState(_currentState.copyWith(
      foregroundTransitions: _foregroundTransitions,
    ));
  }

  Future<void> _onLocationUpdated(LocationUpdated event) async {
    _locationUpdatesCount++;

    // Track GPS accuracy
    final accuracy = event.position.accuracy;
    if (accuracy > _worstGpsAccuracy) {
      _worstGpsAccuracy = accuracy;
    }

    if (accuracy > 50.0) {
      _gpsAccuracyWarnings++;
    }

    _updateState(_currentState.copyWith(
      locationUpdatesCount: _locationUpdatesCount,
      worstGpsAccuracy: _worstGpsAccuracy,
      gpsAccuracyWarnings: _gpsAccuracyWarnings,
    ));
  }

  Future<void> _onHeartRateUpdated(HeartRateUpdated event) async {
    _heartRateUpdatesCount++;

    _updateState(_currentState.copyWith(
      heartRateUpdatesCount: _heartRateUpdatesCount,
    ));
  }

  void _startDiagnosticsReporting() {
    // In release builds, avoid periodic diagnostics to reduce wakeups on low-end devices.
    if (kReleaseMode) {
      AppLogger.debug(
          '[DIAGNOSTICS] Release mode: skipping periodic diagnostics timer');
      return;
    }

    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(_diagnosticsReportInterval, (_) {
      _reportSessionDiagnostics();
    });
  }

  /// Report comprehensive session diagnostics to Crashlytics
  void _reportSessionDiagnostics({bool isFinalReport = false}) {
    if (_activeSessionId == null || _sessionStartTime == null) return;

    final sessionDuration = DateTime.now().difference(_sessionStartTime!);
    final sessionDurationMinutes = sessionDuration.inMinutes;
    if (sessionDurationMinutes == 0 && !isFinalReport)
      return; // Avoid division by zero

    // Get memory usage information
    final memoryInfo = _getMemoryInfo();

    // Calculate rates and quality metrics
    final locationUpdatesPerMinute = sessionDurationMinutes > 0
        ? (_locationUpdatesCount / sessionDurationMinutes)
        : 0.0;
    final heartRateUpdatesPerMinute = sessionDurationMinutes > 0
        ? (_heartRateUpdatesCount / sessionDurationMinutes)
        : 0.0;
    final apiFailureRate = _apiCallsCount > 0
        ? (_failedApiCallsCount / _apiCallsCount * 100)
        : 0.0;
    final avgApiLatency =
        _apiCallsCount > 0 ? (_totalApiLatencyMs / _apiCallsCount) : 0.0;
    final locationValidationFailureRate = _locationUpdatesCount > 0
        ? (_locationValidationFailures / _locationUpdatesCount * 100)
        : 0.0;
    final gpsAccuracyWarningRate = _locationUpdatesCount > 0
        ? (_gpsAccuracyWarnings / _locationUpdatesCount * 100)
        : 0.0;

    // Send comprehensive diagnostics to Crashlytics
    final reportType =
        isFinalReport ? 'Final Session Report' : 'Session Performance Report';
    AppLogger.critical(reportType,
        exception: {
          'session_id': _activeSessionId!,
          'platform': Platform.isIOS ? 'iOS' : 'Android',
          'session_duration_minutes': sessionDurationMinutes,
          'location_updates_per_minute':
              locationUpdatesPerMinute.toStringAsFixed(2),
          'hr_updates_per_minute': heartRateUpdatesPerMinute.toStringAsFixed(2),
          'api_calls_total': _apiCallsCount,
          'api_failure_rate_percent': apiFailureRate.toStringAsFixed(1),
          'avg_api_latency_ms': avgApiLatency.toStringAsFixed(1),
          'worst_gps_accuracy_meters': _worstGpsAccuracy.toStringAsFixed(1),
          'location_validation_failure_rate_percent':
              locationValidationFailureRate.toStringAsFixed(1),
          'gps_accuracy_warning_rate_percent':
              gpsAccuracyWarningRate.toStringAsFixed(1),
          'pause_count': _pauseCount,
          'total_paused_minutes': _totalPausedTime.inMinutes,
          'background_transitions': _backgroundTransitions,
          'foreground_transitions': _foregroundTransitions,
          'memory_usage_mb': memoryInfo['memory_usage_mb'],
          'is_final_report': isFinalReport,
        }.toString());

    // Alert for poor performance metrics OR high memory usage
    final memoryUsageMb = memoryInfo['memory_usage_mb'] as double;
    if (locationUpdatesPerMinute < 1.0 ||
        apiFailureRate > 20.0 ||
        avgApiLatency > 5000.0 ||
        memoryUsageMb > 400.0) {
      AppLogger.critical('Poor Session Performance Detected',
          exception: {
            'session_id': _activeSessionId!,
            'low_location_rate': locationUpdatesPerMinute < 1.0,
            'high_api_failures': apiFailureRate > 20.0,
            'high_api_latency': avgApiLatency > 5000.0,
            'high_memory_usage': memoryUsageMb > 400.0,
            'location_rate': locationUpdatesPerMinute.toStringAsFixed(2),
            'api_failure_rate': apiFailureRate.toStringAsFixed(1),
            'avg_latency': avgApiLatency.toStringAsFixed(1),
            'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
          }.toString());
    }

    _updateState(_currentState.copyWith(
      lastReportTime: DateTime.now(),
      memoryUsageMb: memoryUsageMb,
      locationUpdatesPerMinute: locationUpdatesPerMinute,
      heartRateUpdatesPerMinute: heartRateUpdatesPerMinute,
      apiFailureRate: apiFailureRate,
      avgApiLatency: avgApiLatency,
    ));
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

  void _resetCounters() {
    _locationUpdatesCount = 0;
    _heartRateUpdatesCount = 0;
    _apiCallsCount = 0;
    _failedApiCallsCount = 0;
    _totalApiLatencyMs = 0.0;
    _locationValidationFailures = 0;
    _gpsAccuracyWarnings = 0;
    _worstGpsAccuracy = 0.0;
    _pauseCount = 0;
    _totalPausedTime = Duration.zero;
    _backgroundTransitions = 0;
    _foregroundTransitions = 0;
  }

  void _updateState(DiagnosticsState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> dispose() async {
    _diagnosticsTimer?.cancel();
    await _stateController.close();
  }

  @override
  Future<void> checkForCrashedSession() async {
    // No-op: This manager doesn't handle session recovery
  }

  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: This manager doesn't handle crash recovery data
  }

  // Public methods for other managers to track events
  void trackApiCall({required Duration latency, required bool success}) {
    _apiCallsCount++;
    _totalApiLatencyMs += latency.inMilliseconds;
    if (!success) {
      _failedApiCallsCount++;
    }
  }

  void trackLocationValidationFailure() {
    _locationValidationFailures++;
  }

  void trackPausedTime(Duration pauseDuration) {
    _totalPausedTime += pauseDuration;
  }

  // Getters for other managers
  double get memoryUsageMb => _getMemoryInfo()['memory_usage_mb'] as double;
  Map<String, dynamic> get performanceMetrics => {
        'location_updates_count': _locationUpdatesCount,
        'heart_rate_updates_count': _heartRateUpdatesCount,
        'api_calls_count': _apiCallsCount,
        'failed_api_calls_count': _failedApiCallsCount,
        'avg_api_latency_ms':
            _apiCallsCount > 0 ? (_totalApiLatencyMs / _apiCallsCount) : 0.0,
        'memory_usage_mb': memoryUsageMb,
      };
}
