import 'dart:async';
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

  // Stream controllers for watch events
  final _sessionEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _healthDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _heartRateController = StreamController<double>.broadcast();

  // Heart rate samples list
  List<HeartRateSample> _currentSessionHeartRateSamples = [];

  WatchService(this._locationService, this._healthService, this._authService) {
    AppLogger.info('[WATCH_SERVICE] Initializing...');
    _initPlatformChannels();
    AppLogger.info('[WATCH_SERVICE] Initialized.');
  }

  void _initPlatformChannels() {
    AppLogger.info('[WATCH_SERVICE] Initializing platform channels...');
    _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');

    AppLogger.info('[WATCH_SERVICE] Setting up method call handlers for MethodChannel...');
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);

    AppLogger.info('[WATCH_SERVICE] Registering RuckingApi (Pigeon) handler...');
    RuckingApi.setUp(RuckingApiHandler(this));
    AppLogger.info('[WATCH_SERVICE] Platform channels and Pigeon handler initialized.');
  }

  /// Handle method calls from the watch session channel
  Future<dynamic> _handleWatchSessionMethod(MethodCall call) async {
    AppLogger.info('[WATCH] Received method call: ${call.method}');
    switch (call.method) {
      case 'onWatchSessionUpdated':
        final data = call.arguments as Map<String, dynamic>;
        AppLogger.info('[WATCH] Session updated with data: $data');
        _sessionEventController.add(data);

        if (data['action'] == 'startSession') {
          AppLogger.info('[WATCH] Starting session from watch');
          await _handleSessionStartedFromWatch(data);
        } else if (data['action'] == 'endSession') {
          AppLogger.info('[WATCH] Ending session from watch');
          await _handleSessionEndedFromWatch(data);
        } else if (data['action'] == 'pauseSession') {
          AppLogger.info('[WATCH] Pausing session from watch');
          _isPaused = true;
        } else if (data['action'] == 'resumeSession') {
          AppLogger.info('[WATCH] Resuming session from watch');
          _isPaused = false;
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
    AppLogger.info('[WATCH] Handling session start from watch with weight: ${ruckWeight}kg');

    try {
      AppLogger.info('[WATCH] Getting current user from auth service');
      final authState = await _authService.getCurrentUser();
      if (authState == null) {
        AppLogger.error('[WATCH] No authenticated user found - cannot create session from Watch');
        return;
      }
      AppLogger.info('[WATCH] User authenticated: ${authState.userId}');

      AppLogger.info('[WATCH] Creating ruck session via API');
      final response = await GetIt.instance<ApiClient>().post('/rucks', {
        'ruckWeight': ruckWeight,
      });

      AppLogger.debug('[WATCH] API response for session creation: $response');

      if (response == null || !response.containsKey('id')) {
        AppLogger.error('[WATCH] Failed to create session - invalid API response');
        return;
      }
      AppLogger.info('[WATCH] Session created successfully with ID: ${response['id']}');

      final String sessionId = response['id'].toString();
      AppLogger.info('[WATCH] Extracted session ID: $sessionId');

      AppLogger.info('[WATCH] Sending session ID to watch');
      await sendSessionIdToWatch(sessionId);

      AppLogger.info('[WATCH] Starting session on backend');
      await GetIt.instance<ApiClient>().post('/rucks/$sessionId/start', {});

      AppLogger.info('[WATCH] Notifying watch that workout has started');
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        'sessionId': sessionId,
        'ruckWeight': ruckWeight,
      });

      AppLogger.info('[WATCH] Updating app state - session active');
      _isSessionActive = true;
      _ruckWeight = ruckWeight;
      _currentSessionHeartRateSamples = [];
      AppLogger.info('[WATCH] Session started successfully');
    } catch (e) {
      AppLogger.error('[ERROR] Failed to process session start from Watch: $e');
    }
  }

  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch(Map<String, dynamic> data) async {
    try {
      AppLogger.info('[WATCH] Handling session end from watch');
      AppLogger.info('[WATCH] Saving ${_currentSessionHeartRateSamples.length} heart rate samples to storage');
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
      AppLogger.info('[WATCH] Heart rate samples saved successfully');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to handle session end from Watch: $e');
    }
  }

  /// Start a new rucking session on the watch
  Future<void> startSessionOnWatch(double ruckWeight) async {
    try {
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        'ruckWeight': ruckWeight,
      });
    } catch (e) {
      AppLogger.error('[ERROR] Failed to start session on Watch: $e');
    }
  }

  /// Send the session ID to the watch
  Future<void> sendSessionIdToWatch(String sessionId) async {
    try {
      AppLogger.info('[WATCH] Sending session ID to watch: $sessionId');
      await _sendMessageToWatch({
        'command': 'setSessionId',
        'sessionId': sessionId,
      });
      AppLogger.info('[WATCH] Session ID sent successfully');
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
    AppLogger.info('[WATCH] Pinging watch to test connectivity');
    try {
      await _sendMessageToWatch({
        'command': 'ping',
        'timestamp': DateTime.now().toIso8601String(),
      });
      AppLogger.info('[WATCH] Ping sent to watch');
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

      AppLogger.info('[WATCH] Split notification sent successfully');
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
  }) async {
    try {
      AppLogger.info('[WATCH] Sending updated metrics to watch');
      await _sendMessageToWatch({
        'command': 'updateMetrics',
        'metrics': {
          'distance': distance,
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
  }) async {
    // Log the attempt
    AppLogger.info('[WATCH_SERVICE] Attempting to update session on watch: ' +
        'distance=$distance, duration=${duration.inSeconds}s, pace=$pace, ' +
        'paused=$isPaused, calories=$calories, gain=$elevationGain, loss=$elevationLoss');
    
    bool success = false;
    
    // Send via WatchConnectivity which is the channel that's working reliably
    try {
      AppLogger.info('[WATCH] Sending updated metrics to watch');
      // Use the enhanced updateMetricsOnWatch that includes both elevation gain and loss
      await updateMetricsOnWatch(
        distance: distance,
        duration: duration,
        pace: pace,
        isPaused: isPaused,
        calories: calories.toInt(), // Convert to int since updateMetricsOnWatch expects int
        elevation: elevationGain,    // This is for backward compatibility
        elevationLoss: elevationLoss, // Pass elevation loss directly
      );
      
      // Successfully sent metrics via WatchConnectivity
      success = true;
      
      // Log detailed debug information
      AppLogger.debug('[WATCH_SERVICE] Sent metrics update with:');
      AppLogger.debug('[WATCH_SERVICE] - calories: ${calories.toInt()}');
      AppLogger.debug('[WATCH_SERVICE] - elevationGain: $elevationGain');
      AppLogger.debug('[WATCH_SERVICE] - elevationLoss: $elevationLoss');
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to send metrics via WatchConnectivity: $e');
      success = false;
    }
    
    // Note: We're intentionally not using the Pigeon API channel for now
    // as it's consistently failing with connection errors. When that's fixed,
    // this method can be updated to utilize both channels again.
    
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
    // Update local state
    _isPaused = true;
    AppLogger.info('[WATCH_SERVICE] Attempting to pause session on watch');
    
    bool success = false;
    try {
      // Create the API instance
      final api = FlutterRuckingApi();
      
      // Make the API call separately
      await api.pauseSessionOnWatch();
      
      // Set success flag if no exceptions
      success = true;
      AppLogger.info('[WATCH_SERVICE] Successfully paused session on watch');
    } catch (e) {
      // Log the error
      AppLogger.error('[WATCH_SERVICE] Failed to pause session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  /// Resume the session on the watch
  Future<bool> resumeSessionOnWatch() async {
    // Update local state
    _isPaused = false;
    AppLogger.info('[WATCH_SERVICE] Attempting to resume session on watch');
    
    bool success = false;
    try {
      // Create the API instance
      final api = FlutterRuckingApi();
      
      // Make the API call separately
      await api.resumeSessionOnWatch();
      
      // Set success flag if no exceptions
      success = true;
      AppLogger.info('[WATCH_SERVICE] Successfully resumed session on watch');
    } catch (e) {
      // Log the error
      AppLogger.error('[WATCH_SERVICE] Failed to resume session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  /// End the session on the watch
  Future<bool> endSessionOnWatch() async {
    // Update local state
    _isSessionActive = false;
    AppLogger.info('[WATCH_SERVICE] Attempting to end session on watch');
    
    // First save heart rate samples (outside the try-catch for the API call)
    try {
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to save heart rate samples: $e');
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
      AppLogger.info('[WATCH_SERVICE] Successfully ended session on watch');
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
    _currentHeartRate = heartRate;
    if (_isSessionActive) {
      _healthService.updateHeartRate(heartRate);
      final sample = HeartRateSample(
        timestamp: DateTime.now(),
        bpm: heartRate.toInt(),
      );
      _currentSessionHeartRateSamples.add(sample);
    }
    _heartRateController.add(heartRate);
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
    AppLogger.info('[WATCH_SERVICE] Session started via RuckingApiHandler callback. Weight: $ruckWeight');
  }

  void pauseSessionFromWatchCallback() {
    _isPaused = true;
    AppLogger.info('[WATCH_SERVICE] Session paused via RuckingApiHandler callback.');
  }

  void resumeSessionFromWatchCallback() {
    _isPaused = false;
    AppLogger.info('[WATCH_SERVICE] Session resumed via RuckingApiHandler callback.');
  }

  void endSessionFromWatchCallback(int duration, double distance, double calories) {
    _isSessionActive = false;
    _isPaused = false;
    AppLogger.info(
        '[WATCH_SERVICE] Session ended via RuckingApiHandler callback. Duration: $duration, Distance: $distance, Calories: $calories');
  }

  void dispose() {
    _sessionEventController.close();
    _healthDataController.close();
    _heartRateController.close();
  }
}