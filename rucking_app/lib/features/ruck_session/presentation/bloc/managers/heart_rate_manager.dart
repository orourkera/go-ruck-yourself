import 'dart:async';

import '../../../../../core/services/watch_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../domain/services/heart_rate_service.dart';
import '../../../domain/models/heart_rate_sample.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages heart rate monitoring and BLE device connections
class HeartRateManager implements SessionManager {
  final HeartRateService _heartRateService;
  final WatchService _watchService;
  
  final StreamController<HeartRateState> _stateController;
  HeartRateState _currentState;
  
  // Heart rate tracking state
  StreamSubscription<HeartRateSample>? _heartRateSubscription;
  final List<int> _heartRateSamples = [];
  final List<HeartRateSample> _heartRateSampleObjects = [];
  
  // Session info
  String? _activeSessionId;
  bool _isMonitoring = false;
  
  HeartRateManager({
    required HeartRateService heartRateService,
    required WatchService watchService,
  })  : _heartRateService = heartRateService,
        _watchService = watchService,
        _stateController = StreamController<HeartRateState>.broadcast(),
        _currentState = const HeartRateState();

  @override
  Stream<HeartRateState> get stateStream => _stateController.stream;

  @override
  HeartRateState get currentState => _currentState;

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
    } else if (event is HeartRateUpdated) {
      await _onHeartRateUpdated(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId;
    _heartRateSamples.clear();
    _heartRateSampleObjects.clear();
    
    await _startHeartRateMonitoring();
    
    _updateState(_currentState.copyWith(
      heartRateSamples: [],
      currentHeartRate: null,
      averageHeartRate: 0.0,
      maxHeartRate: 0,
      minHeartRate: 0,
      errorMessage: null,
    ));
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    await _stopHeartRateMonitoring();
    
    _activeSessionId = null;
    _heartRateSamples.clear();
    _heartRateSampleObjects.clear();
    
    _updateState(const HeartRateState());
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    // Continue monitoring heart rate during pause
    AppLogger.info('[HEART_RATE_MANAGER] Session paused, continuing heart rate monitoring');
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    AppLogger.info('[HEART_RATE_MANAGER] Session resumed');
  }

  Future<void> _onHeartRateUpdated(HeartRateUpdated event) async {
    if (_activeSessionId == null) return;
    
    final heartRate = event.heartRate;
    AppLogger.debug('[HEART_RATE_MANAGER] Heart rate updated: $heartRate bpm');
    
    // Add to samples
    _heartRateSamples.add(heartRate);
    
    // Calculate statistics
    final stats = _calculateHeartRateStats();
    
    // Note: Heart rate sync to watch is handled by WatchService integration
    
    _updateState(_currentState.copyWith(
      heartRateSamples: List.from(_heartRateSamples),
      currentHeartRate: heartRate,
      averageHeartRate: stats.average,
      maxHeartRate: stats.max,
      minHeartRate: stats.min,
    ));
  }

  Future<void> _startHeartRateMonitoring() async {
    AppLogger.info('[HEART_RATE_MANAGER] Starting heart rate monitoring');
    _isMonitoring = true;
    
    try {
      // Subscribe to heart rate updates from the service
      _heartRateSubscription = _heartRateService.heartRateStream.listen(
        (sample) {
          if (sample.bpm > 0) {
            _heartRateSampleObjects.add(sample);
            handleEvent(HeartRateUpdated(
              heartRate: sample.bpm,
              timestamp: sample.timestamp,
            ));
          }
        },
        onError: (error) {
          AppLogger.error('[HEART_RATE_MANAGER] Heart rate stream error: $error');
          _updateState(_currentState.copyWith(
            errorMessage: 'Heart rate monitoring error',
          ));
        },
      );
      
      // Start the heart rate service
      await _heartRateService.startHeartRateMonitoring();
      
      // Update state to indicate monitoring started
      _updateState(_currentState.copyWith(
        isConnected: true, // Assume connected when monitoring starts
      ));
      
      AppLogger.info('[HEART_RATE_MANAGER] Heart rate monitoring started.');
      
    } catch (e) {
      AppLogger.error('[HEART_RATE_MANAGER] Failed to start heart rate monitoring: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to start heart rate monitoring',
        isConnected: false,
      ));
    }
  }

  Future<void> _stopHeartRateMonitoring() async {
    AppLogger.info('[HEART_RATE_MANAGER] Stopping heart rate monitoring');
    _isMonitoring = false;
    
    await _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
    
    _heartRateService.stopHeartRateMonitoring();
  }

  ({double average, int max, int min}) _calculateHeartRateStats() {
    if (_heartRateSamples.isEmpty) {
      return (average: 0.0, max: 0, min: 0);
    }
    
    int sum = 0;
    int max = _heartRateSamples.first;
    int min = _heartRateSamples.first;
    
    for (final hr in _heartRateSamples) {
      sum += hr;
      if (hr > max) max = hr;
      if (hr < min) min = hr;
    }
    
    final average = sum / _heartRateSamples.length;
    
    return (average: average, max: max, min: min);
  }

  void _updateState(HeartRateState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> dispose() async {
    await _stopHeartRateMonitoring();
    await _stateController.close();
  }

  // Getters for other managers
  int? get currentHeartRate => _currentState.currentHeartRate;
  double get averageHeartRate => _currentState.averageHeartRate;
  List<int> get heartRateSamples => List.unmodifiable(_heartRateSamples);
  List<HeartRateSample> get heartRateSampleObjects => List.unmodifiable(_heartRateSampleObjects);
  bool get isConnected => _currentState.isConnected;
}
