import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it/get_it.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:rucking_app/core/services/firebase_messaging_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/models/location_point.dart';

/// Service for detecting when a user has likely stopped rucking and should complete their session
class SessionCompletionDetectionService {
  static final SessionCompletionDetectionService _instance = SessionCompletionDetectionService._internal();
  factory SessionCompletionDetectionService() => _instance;
  SessionCompletionDetectionService._internal();

  // Monitoring state
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  
  // Sensor data streams
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  
  // Heart rate data (if available from HealthKit/Health Connect)
  double? _currentHeartRate;
  double? _restingHeartRate;
  double? _workoutAverageHeartRate;
  
  // Movement detection
  List<double> _recentMovementMagnitudes = [];
  DateTime? _lastSignificantMovement;
  
  // GPS tracking
  LocationPoint? _lastKnownPosition;
  DateTime? _lastPositionUpdate;
  double _totalDistanceAtLastCheck = 0.0;
  
  // Session context
  DateTime? _sessionStartTime;
  String? _currentSessionId;
  bool _hasHeartRateData = false;
  
  // Detection thresholds (personalized over time)
  double _movementThreshold = 0.15; // g-force threshold for stationary detection
  double _heartRateDropThreshold = 20.0; // BPM drop from workout average
  int _stationaryTimeThreshold = 300; // 5 minutes in seconds
  int _confirmationTimeThreshold = 420; // 7 minutes in seconds
  int _autoCompleteTimeThreshold = 600; // 10 minutes in seconds
  final Duration _minSessionDurationForIdle = const Duration(minutes: 10); // avoid early prompts

  // Smoothed GPS speed (EWMA) and sampling for robust idle detection
  double _speedEwmaMs = 0.0;
  static const double _ewmaAlpha = 0.2; // smoothing factor
  DateTime? _lastDistanceSampleTime;
  double? _lastDistanceSampleKm;

  // Require consecutive stationary windows to engage detection
  int _consecutiveStationaryWindows = 0;
  final int _requiredStationaryWindows = 3; // 3 x 30s = 90s stability before prompting
  
  // Notification state
  bool _hasShownInitialPrompt = false;
  bool _hasShownConfirmationPrompt = false;
  DateTime? _firstDetectionTime;

  // Hysteresis/cooldown to prevent over-triggering
  DateTime? _lastPromptAt;
  final Duration _promptCooldown = const Duration(minutes: 10);
  bool _rearmRequired = false; // require movement/distance before next prompt
  double? _distanceAtLastPrompt;

  /// Start monitoring for session completion
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    try {
      AppLogger.info('[SESSION_COMPLETION] Starting session completion monitoring');
      
      _isMonitoring = true;
      _resetDetectionState();
      
      // Initialize session context
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      final currentState = activeSessionBloc.state;
      
      if (currentState is ActiveSessionRunning) {
        _sessionStartTime = currentState.originalSessionStartTimeUtc;
        _totalDistanceAtLastCheck = currentState.distanceKm;
        AppLogger.info('[SESSION_COMPLETION] Session started at: $_sessionStartTime');
      }
      
      // Start sensor monitoring
      await _startSensorMonitoring();
      
      // Start periodic analysis
      _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _analyzeSessionCompletion();
      });
      
      AppLogger.info('[SESSION_COMPLETION] Monitoring started successfully');
      
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Failed to start monitoring: $e');
      _isMonitoring = false;
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    AppLogger.info('[SESSION_COMPLETION] Stopping session completion monitoring');
    
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    
    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;
    
    _resetDetectionState();
  }

  /// Start sensor monitoring for movement detection
  Future<void> _startSensorMonitoring() async {
    try {
      // Monitor accelerometer for movement detection
      _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
        final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z) - 9.8; // Remove gravity
        final adjustedMagnitude = magnitude.abs();
        
        // Track recent movement magnitudes (last 2 minutes)
        _recentMovementMagnitudes.add(adjustedMagnitude);
        if (_recentMovementMagnitudes.length > 240) { // 2 minutes at ~2Hz
          _recentMovementMagnitudes.removeAt(0);
        }
        
        // Check if this qualifies as significant movement
        if (adjustedMagnitude > _movementThreshold) {
          _lastSignificantMovement = DateTime.now();
        }
      });
      
      // Monitor gyroscope for rotation detection
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        final rotationMagnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        
        // Significant rotation also counts as movement
        if (rotationMagnitude > 0.2) { // radians/second
          _lastSignificantMovement = DateTime.now();
        }
      });
      
      AppLogger.info('[SESSION_COMPLETION] Sensor monitoring started');
      
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Failed to start sensor monitoring: $e');
    }
  }

  /// Analyze current conditions for session completion
  Future<void> _analyzeSessionCompletion() async {
    if (!_isMonitoring) return;
    
    try {
      final now = DateTime.now();
      
      // Get current session state
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      final currentState = activeSessionBloc.state;
      
      if (currentState is! ActiveSessionRunning) {
        stopMonitoring();
        return;
      }
      
      final session = currentState;
      
      // Update GPS data
      await _updateGPSData();
      
      // Update smoothed speed from distance deltas
      _updateSmoothedSpeed(now);

      // Avoid idle prompts early in the session
      if (_sessionStartTime != null) {
        final sessionAge = now.difference(_sessionStartTime!);
        if (sessionAge < _minSessionDurationForIdle) {
          _resetDetectionState();
          return;
        }
      }

      // Check movement criteria
      final isStationary = _checkMovementCriteria(now);
      
      // Check heart rate criteria (if available)
      final heartRateIndicatesRest = _checkHeartRateCriteria();
      
      // Check GPS criteria
      final gpsIndicatesStationary = _checkGPSCriteria();
      
      // Determine detection confidence
      final detectionConfidence = _calculateDetectionConfidence(
        isStationary, 
        heartRateIndicatesRest, 
        gpsIndicatesStationary
      );
      
      AppLogger.debug('[SESSION_COMPLETION] Detection confidence: $detectionConfidence');
      
      // Require consecutive stability windows to avoid flapping
      if (isStationary && gpsIndicatesStationary) {
        _consecutiveStationaryWindows = (_consecutiveStationaryWindows + 1).clamp(0, 1000);
      } else {
        _consecutiveStationaryWindows = 0;
      }

      // Cooldown / rearm gating to avoid over-triggering
      final inCooldown = _lastPromptAt != null && now.difference(_lastPromptAt!).compareTo(_promptCooldown) < 0;
      if (_rearmRequired) {
        // Rearm when distance increases meaningfully after last prompt
        final double distanceSincePrompt = _distanceAtLastPrompt == null ? 0.0 : (session.distanceKm - _distanceAtLastPrompt!);
        if (distanceSincePrompt >= 0.05) { // 50 meters
          _rearmRequired = false;
          _resetDetectionState();
        }
      }

      // Handle detection state transitions
      final hasStableWindows = _consecutiveStationaryWindows >= _requiredStationaryWindows;
      if (!inCooldown && !_rearmRequired && hasStableWindows && detectionConfidence >= 0.6) {
        await _handleDetectionStateChange(now, detectionConfidence, session.distanceKm);
      } else {
        // Reset detection if conditions no longer met
        _resetDetectionState();
      }
      
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Analysis error: $e');
    }
  }

  /// Check movement-based criteria for session completion
  bool _checkMovementCriteria(DateTime now) {
    // Check time since last significant movement
    if (_lastSignificantMovement == null) return false;
    
    final timeSinceMovement = now.difference(_lastSignificantMovement!);
    
    // Check recent movement magnitude average
    if (_recentMovementMagnitudes.isNotEmpty) {
      final avgMovement = _recentMovementMagnitudes.reduce((a, b) => a + b) / _recentMovementMagnitudes.length;
      
      // User is stationary if low movement for required time
      return avgMovement < _movementThreshold && 
             timeSinceMovement.inSeconds >= _stationaryTimeThreshold;
    }
    
    return timeSinceMovement.inSeconds >= _stationaryTimeThreshold;
  }

  /// Check heart rate criteria (if available)
  bool? _checkHeartRateCriteria() {
    if (!_hasHeartRateData || _currentHeartRate == null) return null;
    
    // Compare to resting heart rate
    if (_restingHeartRate != null) {
      final heartRateRange = _currentHeartRate! - _restingHeartRate!;
      return heartRateRange < 25.0; // Close to resting rate
    }
    
    // Compare to workout average
    if (_workoutAverageHeartRate != null) {
      final dropFromAverage = _workoutAverageHeartRate! - _currentHeartRate!;
      return dropFromAverage >= _heartRateDropThreshold;
    }
    
    return null;
  }

  /// Check GPS-based criteria
  bool _checkGPSCriteria() {
    if (_lastKnownPosition == null || _lastPositionUpdate == null) return false;
    
    final now = DateTime.now();
    final timeSinceUpdate = now.difference(_lastPositionUpdate!);
    
    // If GPS data is stale, can't use it for detection
    if (timeSinceUpdate.inMinutes > 2) return false;
    
    // Check if distance accumulation has stopped
    final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
    final currentState = activeSessionBloc.state;
    
    if (currentState is ActiveSessionRunning) {
      final currentDistance = currentState.distanceKm;
      final distanceChange = currentDistance - _totalDistanceAtLastCheck;
      
      // Update for next check
      _totalDistanceAtLastCheck = currentDistance;
      
      // No significant distance change indicates stationary (less than 10m per 30s)
      final distanceStopped = distanceChange < 0.01;
      // Also require smoothed speed below threshold to reduce false positives
      final speedStopped = _speedEwmaMs < 0.5; // < 0.5 m/s (~1.1 mph)
      return distanceStopped && speedStopped;
    }
    
    return false;
  }

  /// Update smoothed speed using EWMA of distance deltas
  void _updateSmoothedSpeed(DateTime now) {
    try {
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      final currentState = activeSessionBloc.state;
      if (currentState is! ActiveSessionRunning) return;

      final currentKm = currentState.distanceKm;
      if (_lastDistanceSampleTime != null && _lastDistanceSampleKm != null) {
        final dt = now.difference(_lastDistanceSampleTime!).inMilliseconds / 1000.0;
        if (dt >= 5.0) { // only sample when >=5s elapsed to reduce noise
          final dk = (currentKm - _lastDistanceSampleKm!) * 1000.0; // meters
          final instSpeed = dk > 0 && dt > 0 ? (dk / dt) : 0.0; // m/s
          _speedEwmaMs = _ewmaAlpha * instSpeed + (1 - _ewmaAlpha) * _speedEwmaMs;
          _lastDistanceSampleTime = now;
          _lastDistanceSampleKm = currentKm;
          return;
        }
      }
      // Initialize sampling
      _lastDistanceSampleTime ??= now;
      _lastDistanceSampleKm ??= currentKm;
    } catch (_) {
      // best-effort; ignore errors
    }
  }

  /// Calculate overall detection confidence (0.0 - 1.0)
  double _calculateDetectionConfidence(bool isStationary, bool? heartRateRest, bool gpsStationary) {
    double confidence = 0.0;
    int criteriaCount = 0;
    
    // Movement criteria (weight: 0.4)
    if (isStationary) {
      confidence += 0.4;
    }
    criteriaCount++;
    
    // Heart rate criteria (weight: 0.3)
    if (heartRateRest != null) {
      if (heartRateRest) {
        confidence += 0.3;
      }
      criteriaCount++;
    }
    
    // GPS criteria (weight: 0.3)
    if (gpsStationary) {
      confidence += 0.3;
    }
    criteriaCount++;
    
    // If we don't have heart rate, redistribute its weight to movement
    if (heartRateRest == null && isStationary) {
      confidence += 0.15; // Half of heart rate weight
    }
    
    return confidence;
  }

  /// Handle state changes in detection
  Future<void> _handleDetectionStateChange(DateTime now, double confidence, double currentDistance) async {
    // First detection
    if (_firstDetectionTime == null) {
      _firstDetectionTime = now;
      AppLogger.info('[SESSION_COMPLETION] First detection at: $now (confidence: $confidence)');
      return;
    }
    
    final detectionDuration = now.difference(_firstDetectionTime!);
    
    // Initial prompt (3-5 minutes of detection)
    if (!_hasShownInitialPrompt && 
        detectionDuration.inSeconds >= _stationaryTimeThreshold && 
        confidence >= 0.7) {
      
      await _showSessionCompletionPrompt('initial', currentDistance);
      _hasShownInitialPrompt = true;
    }
    
    // Confirmation prompt (7 minutes of detection)
    if (!_hasShownConfirmationPrompt && 
        detectionDuration.inSeconds >= _confirmationTimeThreshold && 
        confidence >= 0.8) {
      
      await _showSessionCompletionPrompt('confirmation', currentDistance);
      _hasShownConfirmationPrompt = true;
    }
    
    // Auto-complete suggestion (10 minutes of detection)
    if (detectionDuration.inSeconds >= _autoCompleteTimeThreshold && 
        confidence >= 0.9) {
      
      await _showSessionCompletionPrompt('auto_complete', currentDistance);
      // Reset to prevent repeated notifications
      _resetDetectionState();
    }
  }

  /// Show session completion notification
  Future<void> _showSessionCompletionPrompt(String promptType, double distance) async {
    try {
      final firebaseMessaging = GetIt.instance<FirebaseMessagingService>();
      
      String title;
      String body;
      int notificationId;
      
      switch (promptType) {
        case 'initial':
          title = 'Finish your ruck?';
          body = 'You\'ve been stationary for a few minutes. Ready to complete your ${distance.toStringAsFixed(1)} km session?';
          notificationId = 10001;
          break;
        case 'confirmation':
          title = 'Still rucking?';
          body = 'Tap to complete your session or continue if you\'re still active.';
          notificationId = 10002;
          break;
        case 'auto_complete':
          title = 'Complete Session?';
          body = 'You\'ve been inactive for 10+ minutes. Tap to finish your ${distance.toStringAsFixed(1)} km ruck.';
          notificationId = 10003;
          break;
        default:
          return;
      }
      
      // Show local notification (works on phone and watch)
      await firebaseMessaging.showNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: 'session_completion_prompt',
      );
      
      // Also create database notification for consistency
      await _createDatabaseNotification(
        type: 'session_completion_prompt',
        title: title,
        body: body,
        sessionId: _currentSessionId,
        promptType: promptType,
      );
      
      AppLogger.info('[SESSION_COMPLETION] Showed $promptType notification');

      // Record cooldown and require rearm before next prompt
      _lastPromptAt = DateTime.now();
      _rearmRequired = true;
      _distanceAtLastPrompt = distance;
      
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Failed to show notification: $e');
    }
  }

  /// Update GPS data
  Future<void> _updateGPSData() async {
    try {
      final locationService = GetIt.instance<LocationService>();
      final position = await locationService.getCurrentLocation();
      
      if (position != null) {
        _lastKnownPosition = position;
        _lastPositionUpdate = DateTime.now();
      }
    } catch (e) {
      AppLogger.debug('[SESSION_COMPLETION] GPS update failed: $e');
    }
  }

  /// Reset detection state
  void _resetDetectionState() {
    _hasShownInitialPrompt = false;
    _hasShownConfirmationPrompt = false;
    _firstDetectionTime = null;
    // Note: do not clear _lastPromptAt or _rearmRequired here; cooldown spans detection windows
  }

  /// Update heart rate data (to be called by health integration)
  void updateHeartRateData({
    required double currentHeartRate,
    double? restingHeartRate,
    double? workoutAverage,
  }) {
    _currentHeartRate = currentHeartRate;
    _restingHeartRate = restingHeartRate;
    _workoutAverageHeartRate = workoutAverage;
    _hasHeartRateData = true;
  }

  /// Personalize thresholds based on user behavior
  void personalizeThresholds({
    double? movementThreshold,
    double? heartRateDropThreshold,
    int? stationaryTimeThreshold,
  }) {
    if (movementThreshold != null) _movementThreshold = movementThreshold;
    if (heartRateDropThreshold != null) _heartRateDropThreshold = heartRateDropThreshold;
    if (stationaryTimeThreshold != null) _stationaryTimeThreshold = stationaryTimeThreshold;
    
    AppLogger.info('[SESSION_COMPLETION] Thresholds personalized');
  }

  /// Get current monitoring status
  bool get isMonitoring => _isMonitoring;
  
  /// Get detection state for debugging
  Map<String, dynamic> get debugInfo => {
    'isMonitoring': _isMonitoring,
    'hasHeartRateData': _hasHeartRateData,
    'lastSignificantMovement': _lastSignificantMovement?.toIso8601String(),
    'inactivityDuration': _lastSignificantMovement != null 
      ? DateTime.now().difference(_lastSignificantMovement!).inMinutes
      : null,
  };

  /// Create database notification record for consistency with other notifications
  Future<void> _createDatabaseNotification({
    required String type,
    required String title,
    required String body,
    required String? sessionId,
    required String promptType,
  }) async {
    try {
      if (sessionId == null) {
        AppLogger.warning('[SESSION_COMPLETION] Cannot create notification - no session ID');
        return;
      }
      
      final apiClient = GetIt.instance<ApiClient>();
      
      await apiClient.post('/notifications', {
        'type': type,
        'title': title,
        'message': body,
        'data': {
          'session_id': sessionId,
          'prompt_type': promptType,
          'notification_source': 'session_completion_detection'
        },
      });
      
      AppLogger.info('[SESSION_COMPLETION] Created database notification record');
    } catch (e) {
      AppLogger.error('[SESSION_COMPLETION] Failed to create database notification: $e');
      // Don't throw - notification failure shouldn't break session completion detection
    }
  }
}
