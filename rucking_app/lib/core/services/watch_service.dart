import 'dart:async';
import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/data/heart_rate_sample_storage.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'rucking_api_handler.dart';

/// Service for managing communication with Apple Watch companion app
class WatchService {
  final LocationService _locationService;
  final HealthService _healthService;
  final AuthService _authService;

  // Session state
  bool _isSessionActive = false;
  bool _isPaused = false;
  double _currentDistance = 0.0;
  Duration _currentDuration = Duration.zero;
  double _currentPace = 0.0;
  double? _currentHeartRate;
  double _ruckWeight = 0.0;
  int _currentCalories = 0;
  double _currentElevationGain = 0.0;
  double _currentElevationLoss = 0.0;

  // Method channels
  late MethodChannel _watchSessionChannel;
  late EventChannel _heartRateEventChannel;

  // Stream controllers for watch events
  final _sessionEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _healthDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _heartRateController = StreamController<double>.broadcast();
  StreamSubscription? _nativeHeartRateSubscription;
  
  // Constants for heart rate sampling
  static const Duration _heartRateSampleInterval = Duration(seconds: 30); // Sample every 30 seconds
  static const int _heartRateSignificantChangeBpm = 10; // Consider changes of 10+ BPM significant
  
  // Heart rate sampling variables
  DateTime? _lastHeartRateSampleTime;
  double? _lastSampledHeartRate;
  
  // Flag to track if we've attempted to reconnect the heart rate listener
  bool _isReconnectingHeartRate = false;
  int _heartRateReconnectAttempts = 0;
  Timer? _heartRateWatchdogTimer;
  DateTime? _lastHeartRateUpdateTime;

  // Heart rate samples list
  List<HeartRateSample> _currentSessionHeartRateSamples = [];

  WatchService(this._locationService, this._healthService, this._authService) {
    // Watch service initialization
    _initPlatformChannels();
    // Watch service initialized
  }

  void _initPlatformChannels() {
    // Initialize platform channels
    _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');
    _heartRateEventChannel = const EventChannel('com.getrucky.gfy/heartRateStream');

    // Setup method call handlers
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);

    // Setup heart rate event channel
    _setupNativeHeartRateListener();
    _startHeartRateWatchdog();

    // Register Pigeon handler
    RuckingApi.setUp(RuckingApiHandler(this));
    // Platform channels setup complete
  }

  /// Handle method calls from the watch session channel
  Future<dynamic> _handleWatchSessionMethod(MethodCall call) async {
    // Silent method call processing
    debugPrint('[PAUSE_DEBUG] WatchService: _handleWatchSessionMethod received call: ${call.method} with arguments: ${call.arguments}');
    switch (call.method) {
      case 'onWatchSessionUpdated':
        // Safely handle the arguments map with proper type casting
        if (call.arguments is! Map) {
          AppLogger.error('[WATCH] Invalid arguments type: ${call.arguments.runtimeType}');
          return;
        }
        
        // Convert from Map<Object?, Object?> to Map<String, dynamic>
        final rawMap = call.arguments as Map<Object?, Object?>;
        final data = <String, dynamic>{};
        rawMap.forEach((key, value) {
          if (key is String) {
            data[key] = value;
          }
        });
        
        AppLogger.info('[WATCH] Session updated with data: $data');
        _sessionEventController.add(data);
        
        // Get the command type from the message
        final command = data['command'] as String?;
        
        if (command == 'startSession') {
          debugPrint('[PAUSE_DEBUG] WatchService: _handleWatchSessionMethod -> startSession command received from watch');
          await _handleSessionStartedFromWatch(data);
        } else if (command == 'pauseSession') {
          debugPrint('[PAUSE_DEBUG] WatchService: _handleWatchSessionMethod -> pauseSession command received from watch');
          await pauseSessionFromWatchCallback();
        } else if (command == 'resumeSession') {
          debugPrint('[PAUSE_DEBUG] WatchService: _handleWatchSessionMethod -> resumeSession command received from watch');
          await resumeSessionFromWatchCallback();
        } else if (command == 'endSession') {
          debugPrint('[PAUSE_DEBUG] WatchService: _handleWatchSessionMethod -> endSession command received from watch');
          await _handleSessionEndedFromWatch(data);
        } else if (command == 'pingResponse') {
          AppLogger.info('[WATCH] Ping response received from watch: ${data['message']}');
        }

        return true;
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Handle a session started from the watch
  Future<void> _handleSessionStartedFromWatch(Map<String, dynamic> data) async {
    final double ruckWeight = (data['ruckWeight'] as num?)?.toDouble() ?? 10.0;
    // Handle session start from watch

    try {
      // Get current user
      final authState = await _authService.getCurrentUser();
      if (authState == null) {
        AppLogger.error('[WATCH] No authenticated user found - cannot create session from Watch');
        return;
      }
      // User authenticated

      // Create ruck session
      final response = await GetIt.instance<ApiClient>().post('/rucks', {
        'ruckWeight': ruckWeight,
      });

      AppLogger.debug('[WATCH] API response for session creation: $response');

      if (response == null || !response.containsKey('id')) {
        AppLogger.error('[WATCH] Failed to create session - invalid API response');
        return;
      }
      // Session created successfully

      final String sessionId = response['id'].toString();
      // Session ID extracted

      // Send session ID to watch
      await sendSessionIdToWatch(sessionId);

      // Start session on backend
      await GetIt.instance<ApiClient>().post('/rucks/$sessionId/start', {});

      // Notify watch of workout start
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        'sessionId': sessionId,
        'ruckWeight': ruckWeight,
      });

      // Update app state
      _isSessionActive = true;
      _ruckWeight = ruckWeight;
      _currentSessionHeartRateSamples = [];
      // Session started successfully
    } catch (e) {
      AppLogger.error('[ERROR] Failed to process session start from Watch: $e');
    }
  }

  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch(Map<String, dynamic> data) async {
    try {
      // Handle session end from watch
      // Save heart rate samples to storage
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
      // Heart rate samples sent successfully
    } catch (e) {
      AppLogger.error('[WATCH] Failed to handle session end from Watch: $e');
    }
  }

  /// Reset heart rate sampling tracking variables
  void _resetHeartRateSamplingVariables() {
    _lastHeartRateSampleTime = null;
    _lastSampledHeartRate = null;
    AppLogger.debug('[WATCH_SERVICE] Reset heart rate sampling variables');
  }

  /// Start a new rucking session on the watch
  Future<void> startSessionOnWatch(double ruckWeight) async {
    debugPrint('[PAUSE_DEBUG] WatchService: startSessionOnWatch called with ruckWeight: $ruckWeight. Setting _isSessionActive = true.');
    _isSessionActive = true;
    _isPaused = false;
    _ruckWeight = ruckWeight;
    _resetHeartRateSamplingVariables();
    _currentSessionHeartRateSamples = []; // Clear samples for the new session

    try {
      // Store ruckWeight locally for calorie calculations, but don't send to watch
      // to prevent it from being displayed on the watch face
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        // ruckWeight intentionally omitted to prevent display on watch
      });
    } catch (e) {
      AppLogger.error('[ERROR] Failed to start session on Watch: $e');
    }
  }

  /// Send the session ID to the watch
  Future<void> sendSessionIdToWatch(String sessionId) async {
    try {
      // Send session ID to watch
      await _sendMessageToWatch({
        'command': 'setSessionId',
        'sessionId': sessionId,
      });
      // Session ID sent
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send session ID to Watch: $e');
    }
  }

  /// Send a message to the watch via the session channel
  Future<void> _sendMessageToWatch(Map<String, dynamic> message) async {
    try {
      AppLogger.debug('[WATCH] Sending message to watch: ${message['command']}');
      await _watchSessionChannel.invokeMethod('sendMessage', message);
      AppLogger.debug('[WATCH] Message sent successfully');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send message to Watch: $e');
      AppLogger.error('[WATCH] Message details: $message');
    }
  }

  /// Test connectivity to watch by sending a ping message
  Future<void> pingWatch() async {
    // Ping watch for connectivity test
    try {
      await _sendMessageToWatch({
        'command': 'ping',
        'timestamp': DateTime.now().toIso8601String(),
      });
      // Ping sent
    } catch (e) {
      AppLogger.error('[WATCH] Error pinging watch: $e');
    }
  }

  /// Send a split notification to the watch
  Future<bool> sendSplitNotification({
    required double splitDistance,
    required Duration splitDuration,
    required double totalDistance,
    required Duration totalDuration,
    required bool isMetric,
  }) async {
    try {
      AppLogger.info(
          '[WATCH] Sending split notification: $splitDistance ${isMetric ? 'km' : 'mi'}, time: ${_formatDuration(splitDuration)}');

      final String formattedSplitDistance = '${splitDistance.toStringAsFixed(1)} ${isMetric ? 'km' : 'mi'}';
      final String formattedTotalDistance = '${totalDistance.toStringAsFixed(1)} ${isMetric ? 'km' : 'mi'}';

      await _sendMessageToWatch({
        'command': 'splitNotification',
        'splitDistance': formattedSplitDistance,
        'splitTime': _formatDuration(splitDuration),
        'totalDistance': formattedTotalDistance,
        'totalTime': _formatDuration(totalDuration),
        'isMetric': isMetric,
      });

      // Split notification sent
      return true;
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send split notification: $e');
      return false;
    }
  }

  /// Send updated metrics to the watch
  Future<void> updateMetricsOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
    required int calories,
    required double elevation,
    double? elevationLoss, // Optional parameter for elevation loss
    required bool isMetric, // Used to convert values before sending to watch
  }) async {
    try {
      AppLogger.info('[WATCH] Sending updated metrics to watch');
      // Convert km to miles if user prefers imperial units
      // distance is always stored in km in the app, but we send it in the user's preferred unit
      double displayDistance = isMetric ? distance : distance / 1.60934; // km to miles
      await _sendMessageToWatch({
        'command': 'updateMetrics',
        'metrics': {
          'distance': displayDistance,
          'duration': duration.inSeconds,
          'pace': pace,
          'isPaused': isPaused ? 1 : 0, // Convert bool to int for Swift compatibility
          'calories': calories,
          // Include both elevation formats for compatibility
          'elevation': elevation,
          'elevationGain': elevation,
          'elevationLoss': elevationLoss ?? 0.0, // Use provided loss or default to 0
          if (_currentHeartRate != null) 'heartRate': _currentHeartRate,
        },
      });
      AppLogger.debug('[WATCH] Metrics updated successfully with calories=$calories, elevation gain=$elevation, loss=${elevationLoss ?? 0.0}');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send metrics to watch: $e');
    }
  }

  /// Send updated session metrics to the watch.
  /// Primary method uses WatchConnectivity which is the reliable channel.
  Future<bool> updateSessionOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
    required double calories,
    required double elevationGain,
    required double elevationLoss,
    required bool isMetric, // Add user's metric preference
  }) async {
    // Attempt to update session on watch
    
    bool success = false;
    
    // Send via WatchConnectivity which is the channel that's working reliably
    try {
      debugPrint('[PAUSE_DEBUG] WatchService: updateSessionOnWatch called. isPaused: $isPaused, distance: $distance, duration: $duration, pace: $pace');
      _currentDistance = distance;
      _currentDuration = duration;
      // Use the enhanced updateMetricsOnWatch that includes both elevation gain and loss
      await updateMetricsOnWatch(
        distance: distance,
        duration: duration,
        pace: pace,
        isPaused: isPaused,
        calories: calories.toInt(), // Convert to int since updateMetricsOnWatch expects int
        elevation: elevationGain,    // This is for backward compatibility
        elevationLoss: elevationLoss, // Pass elevation loss directly
        isMetric: isMetric, // Pass user's unit preference
      );
      
      // Successfully sent metrics via WatchConnectivity
      success = true;
      
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to send metrics via WatchConnectivity: $e');
      success = false;
    }
    
    return success;
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  /// Format number to two digits
  String twoDigits(int n) => n.toString().padLeft(2, '0');

  /// Pause the session on the watch
  Future<bool> pauseSessionOnWatch() async {
    // If a session is active, pause it
    debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionOnWatch called. Current _isSessionActive: $_isSessionActive, _isPaused: $_isPaused');
    if (_isSessionActive && !_isPaused) {
      _isPaused = true;
      AppLogger.info('[WATCH] Sending pause command to watch');
      try {
        await _watchSessionChannel.invokeMethod('pauseSession');
        debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionOnWatch -> invokeMethod(\'pauseSession\') successful.');
        return true;
      } catch (e) {
        AppLogger.error('[WATCH] Error sending pause command to watch: $e');
        debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionOnWatch -> invokeMethod(\'pauseSession\') FAILED: $e');
        _isPaused = false; // Revert optimistic update
        return false;
      }
    } else {
      debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionOnWatch -> NO-OP. Session not active or already paused. _isSessionActive: $_isSessionActive, _isPaused: $_isPaused');
      // Return true if already paused, false if not active, to indicate desired state might be met or not applicable
      return _isPaused; 
    }
  }

  /// Resume the session on the watch
  Future<bool> resumeSessionOnWatch() async {
    // If a session is active and paused, resume it
    debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionOnWatch called. Current _isSessionActive: $_isSessionActive, _isPaused: $_isPaused');
    if (_isSessionActive && _isPaused) {
      _isPaused = false;
      AppLogger.info('[WATCH] Sending resume command to watch');
      try {
        await _watchSessionChannel.invokeMethod('resumeSession');
        debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionOnWatch -> invokeMethod(\'resumeSession\') successful.');
        return true;
      } catch (e) {
        AppLogger.error('[WATCH] Error sending resume command to watch: $e');
        debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionOnWatch -> invokeMethod(\'resumeSession\') FAILED: $e');
        _isPaused = true; // Revert optimistic update
        return false;
      }
    } else {
      debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionOnWatch -> NO-OP. Session not active or already running. _isSessionActive: $_isSessionActive, _isPaused: $_isPaused');
      // Return true if already resumed (not paused), false if not active
      return !_isPaused && _isSessionActive;
    }
  }

  /// End the session on the watch
  Future<bool> endSessionOnWatch() async {
    // Update local state
    _isSessionActive = false;
    _isPaused = false;
    _resetHeartRateSamplingVariables();
    
    // First save heart rate samples (outside the try-catch for the API call)
    try {
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
    } catch (e) {
      // Sending heart rate samples to API
      // Continue anyway, try to end the session on watch
    }
    
    bool success = false;
    try {
      // Create the API instance
      final api = FlutterRuckingApi();
      
      // Make the API call separately
      await api.endSessionOnWatch();
      
      // Set success flag if no exceptions
      success = true;
      // Session ended on watch
    } catch (e) {
      // Log the error
      AppLogger.error('[WATCH_SERVICE] Failed to end session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    // Update our local heart rate value
    _currentHeartRate = heartRate;
    // Add to heart rate stream for UI components (always update UI in real-time)
    _heartRateController.add(heartRate);
    
    // Add to session heart rate samples with throttling to reduce database load
    if (_isSessionActive) {
      final now = DateTime.now().toUtc();
      final int currentBpm = heartRate.toInt();
      
      // Determine if we should save this sample based on time interval or significant change
      bool shouldSaveSample = false;
      
      // Always save the first sample
      if (_lastHeartRateSampleTime == null || _lastSampledHeartRate == null) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving initial heart rate sample: $currentBpm BPM');
      } 
      // Save if enough time has passed since last sample
      else if (now.difference(_lastHeartRateSampleTime!) >= _heartRateSampleInterval) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving heart rate sample after interval: $currentBpm BPM');
      }
      // Save if there's a significant change in heart rate, even if interval hasn't passed
      else if (_lastSampledHeartRate != null && 
               (currentBpm - _lastSampledHeartRate!).abs() >= _heartRateSignificantChangeBpm) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving heart rate sample due to significant change: $currentBpm BPM (changed from ${_lastSampledHeartRate!.toInt()} BPM)');
      }
      
      // If we should save this sample, add it to our collection
      if (shouldSaveSample) {
        final sample = HeartRateSample(
          bpm: currentBpm,
          timestamp: now,
        );
        _currentSessionHeartRateSamples.add(sample);
        
        // Update our tracking variables
        _lastHeartRateSampleTime = now;
        _lastSampledHeartRate = heartRate;
        
        // Store heart rate samples for processing
        try {
          // Just add to our local list for now - we'll save the entire list later
          // HeartRateSampleStorage has static methods only, not instance methods
          // We'll call HeartRateSampleStorage.saveSamples() when the session ends
        } catch (e) {
          // Only log errors for heart rate storage
          AppLogger.error('[WATCH_SERVICE] Failed to store heart rate sample: $e');
        }
      }
    }
  }

  /// Stream to listen for heart rate updates from the Watch
  Stream<double> get onHeartRateUpdate => _heartRateController.stream;

  /// Get current heart rate
  double? getCurrentHeartRate() => _currentHeartRate;

  /// Get current session heart rate samples
  List<HeartRateSample> getCurrentSessionHeartRateSamples() => _currentSessionHeartRateSamples;

  // Callbacks for RuckingApiHandler
  void sessionStartedFromWatchCallback(double ruckWeight, dynamic response) {
    _isSessionActive = true;
    _isPaused = false;
    _ruckWeight = ruckWeight;
    // Session started via watch
  }

  /// Callback when session is paused from the watch
  /// This will update the internal state and dispatch the appropriate events to the ActiveSessionBloc
  Future<void> pauseSessionFromWatchCallback() async {
    debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionFromWatchCallback triggered.');
    // Regardless of current _isPaused value, forward the pause request – let the
    // ActiveSessionBloc decide if it is a duplicate. This prevents dropped
    // commands when our local flag drifts out-of-sync with the Bloc.
    if (!_isSessionActive) {
      debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionFromWatchCallback -> NO-OP. Session not active.');
      return;
    }

    // Dispatch pause event to ActiveSessionBloc if available
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionFromWatchCallback -> Dispatching SessionPaused(source: SessionActionSource.watch) to ActiveSessionBloc.');
      GetIt.I<ActiveSessionBloc>().add(const SessionPaused(source: SessionActionSource.watch));
    } else {
      debugPrint('[PAUSE_DEBUG] WatchService: pauseSessionFromWatchCallback -> ActiveSessionBloc not registered in GetIt.');
      AppLogger.warning('[WATCH_SERVICE] ActiveSessionBloc not ready in GetIt for pauseSessionFromWatchCallback');
    }

    // Update local flag after dispatching
    _isPaused = true;
  }

  /// Callback when session is resumed from the watch
  /// This will update the internal state and dispatch the appropriate events to the ActiveSessionBloc
  Future<void> resumeSessionFromWatchCallback() async {
    debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionFromWatchCallback triggered.');
    if (!_isSessionActive) {
      debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionFromWatchCallback -> NO-OP. Session not active.');
      return;
    }

    // Dispatch resume event regardless of local _isPaused – Bloc will ignore if necessary
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionFromWatchCallback -> Dispatching SessionResumed(source: SessionActionSource.watch) to ActiveSessionBloc.');
      GetIt.I<ActiveSessionBloc>().add(const SessionResumed(source: SessionActionSource.watch));
    } else {
      debugPrint('[PAUSE_DEBUG] WatchService: resumeSessionFromWatchCallback -> ActiveSessionBloc not registered in GetIt.');
      AppLogger.warning('[WATCH_SERVICE] ActiveSessionBloc not ready in GetIt for resumeSessionFromWatchCallback');
    }

    _isPaused = false;
  }

  void endSessionFromWatchCallback(int duration, double distance, double calories) {
    _isSessionActive = false;
    _isPaused = false;
    AppLogger.info(
        '[WATCH_SERVICE] Session ended via RuckingApiHandler callback. Duration: $duration, Distance: $distance, Calories: $calories');
  }

  void dispose() {
    _heartRateWatchdogTimer?.cancel();
    _nativeHeartRateSubscription?.cancel();
    _sessionEventController.close();
    _healthDataController.close();
    _heartRateController.close();
  }

  // ------------------------------------------------------------
  // Native heart-rate stream resilience helpers
  // ------------------------------------------------------------

  /// Start a watchdog timer to ensure heart rate updates are being received
  void _startHeartRateWatchdog() {
    _heartRateWatchdogTimer?.cancel();
    _heartRateWatchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final lastUpdateTime = _lastHeartRateUpdateTime;
      if (lastUpdateTime != null) {
        final timeSinceLastUpdate = DateTime.now().difference(lastUpdateTime);
        if (timeSinceLastUpdate > const Duration(seconds: 60) && !_isReconnectingHeartRate) {
          AppLogger.warning('[WATCH_SERVICE] No heart rate updates received for ${timeSinceLastUpdate.inSeconds} seconds - restarting listener');
          _restartNativeHeartRateListener();
        }
      }
    });
  }

  void _setupNativeHeartRateListener() {
    // Cancel any existing subscription first
    _nativeHeartRateSubscription?.cancel();
    _nativeHeartRateSubscription = null;
    
    // Setup heart rate listener
    
    try {
      _nativeHeartRateSubscription = _heartRateEventChannel.receiveBroadcastStream().listen(
        (dynamic heartRate) {
          if (heartRate is double) {
            _heartRateReconnectAttempts = 0; // Reset reconnect counter on successful update
            _lastHeartRateUpdateTime = DateTime.now();
            _isReconnectingHeartRate = false;
            // Silently handle heart rate update
            handleWatchHeartRateUpdate(heartRate);
          }
        },
        onError: _onNativeHeartRateError,
        onDone: _onNativeHeartRateDone,
        cancelOnError: false, // Don't cancel on error, let our error handler decide
      );
      
      // Notify native code that Flutter is ready to receive heart rate updates
      try {
        _watchSessionChannel.invokeMethod('flutterHeartRateListenerReady')
          .then((_) {})
          .catchError((error) {
            AppLogger.error('[WATCH_SERVICE] Error notifying native code about heart rate listener: $error');
          });
      } catch (e) {
        AppLogger.error('[WATCH_SERVICE] Failed to notify native about heart rate listener: $e');
      }
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to set up heart rate listener: $e');
      _scheduleHeartRateReconnect();
    }
  }

  void _onNativeHeartRateError(dynamic error) {
    AppLogger.error('[WATCH_SERVICE] Heart rate channel error: $error – scheduling restart');
    _scheduleHeartRateReconnect();
  }

  void _onNativeHeartRateDone() {
    AppLogger.warning('[WATCH_SERVICE] Heart rate channel closed – scheduling restart');
    _scheduleHeartRateReconnect();
  }

  void _scheduleHeartRateReconnect() {
    if (_isReconnectingHeartRate) {
      // Already reconnecting heart rate channel
      return;
    }
    
    _isReconnectingHeartRate = true;
    _heartRateReconnectAttempts++;
    
    // Exponential backoff for reconnection attempts
    final delaySeconds = math.min(30, math.pow(2, math.min(5, _heartRateReconnectAttempts)).toInt());
    // Schedule heart rate reconnect
    
    // Small delay to avoid tight reconnection loops
    Future.delayed(Duration(seconds: delaySeconds), () {
      _restartNativeHeartRateListener();
    });
  }

  void _restartNativeHeartRateListener() {
    // Restart heart rate listener
    _nativeHeartRateSubscription?.cancel();
    _setupNativeHeartRateListener();
  }
  
  /// Public method to force restart the heart rate monitoring from outside this class
  void restartHeartRateMonitoring() {
    // Manual restart of heart rate monitoring
    _heartRateReconnectAttempts = 0;
    _isReconnectingHeartRate = false;
    _restartNativeHeartRateListener();
  }
}