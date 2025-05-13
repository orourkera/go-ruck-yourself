import 'dart:async';
import 'dart:convert';
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
  
  // Method channels
  late MethodChannel _watchSessionChannel;
  late MethodChannel _watchHealthChannel;
  late MethodChannel _userPrefsChannel;
  
  // Stream controllers for watch events
  final _sessionEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _healthDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _heartRateController = StreamController<double>.broadcast();
  
  // Heart rate samples list
  List<HeartRateSample> _currentSessionHeartRateSamples = [];
  
  WatchService(this._locationService, this._healthService, this._authService) {
    AppLogger.info('[WATCH] Initializing WatchService');
    _initPlatformChannels();
    AppLogger.info('[WATCH] WatchService initialized');
  }
  
  void _initPlatformChannels() {
    AppLogger.info('[WATCH] Initializing platform channels');
    // Set up method channels
    _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');
    _watchHealthChannel = const MethodChannel('com.getrucky.gfy/watch_health');
    _userPrefsChannel = const MethodChannel('com.getrucky.gfy/user_preferences');
    
    AppLogger.info('[WATCH] Setting up method call handlers');
    // Set up method call handlers
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);
    _watchHealthChannel.setMethodCallHandler(_handleWatchHealthMethod);
    
    AppLogger.info('[WATCH] Registering RuckingApi handler');
    // Register the RuckingApi handler
    RuckingApi.setUp(RuckingApiHandler(this));
    AppLogger.info('[WATCH] Platform channels initialized successfully');
  }
  
  /// Handle method calls from the watch session channel
  Future<dynamic> _handleWatchSessionMethod(MethodCall call) async {
    AppLogger.info('[WATCH] Received method call: ${call.method}');
    switch (call.method) {
      case 'onWatchSessionUpdated':
        final data = call.arguments as Map<String, dynamic>;
        AppLogger.info('[WATCH] Session updated with data: $data');
        _sessionEventController.add(data);
        
        // Check if a session was started from the watch
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
  
  /// Handle method calls from the watch health channel
  Future<dynamic> _handleWatchHealthMethod(MethodCall call) async {
    AppLogger.debug('[WATCH] Health method call: ${call.method}');
    switch (call.method) {
      case 'onHealthDataUpdated':
        final data = call.arguments as Map<String, dynamic>;
        _healthDataController.add(data);
        
        // Update heart rate if needed
        if (data['type'] == 'heartRate') {
          _currentHeartRate = data['value'];
          AppLogger.debug('[WATCH] Received heart rate update: ${_currentHeartRate!.toStringAsFixed(1)} BPM');
          
          // If session is active, send to health service
          if (_isSessionActive) {
            AppLogger.debug('[WATCH] Updating health service with heart rate data');
            _healthService.updateHeartRate(_currentHeartRate!);
            // Store heart rate sample with timestamp
            final sample = HeartRateSample(
              timestamp: DateTime.now(),
              bpm: _currentHeartRate!.toInt(),
            );
            _currentSessionHeartRateSamples.add(sample);
            AppLogger.debug('[WATCH] Heart rate sample stored. Total samples: ${_currentSessionHeartRateSamples.length}');
          }
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
    // Extract ruckWeight or use a default
    final double ruckWeight = (data['ruckWeight'] as num?)?.toDouble() ?? 10.0;
    AppLogger.info('[WATCH] Handling session start from watch with weight: ${ruckWeight}kg');
    
    try {
      // Get current user
      AppLogger.info('[WATCH] Getting current user from auth service');
      final authState = await _authService.getCurrentUser();
      if (authState == null) {
        AppLogger.error('[WATCH] No authenticated user found - cannot create session from Watch');
        return;
      }
      AppLogger.info('[WATCH] User authenticated: ${authState.userId}');
      
      // Create ruck session
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
      
      // Extract session ID and start the session
      final String sessionId = response['id'].toString();
      AppLogger.info('[WATCH] Extracted session ID: $sessionId');
      
      // Send session ID to watch so it can include it in API calls
      AppLogger.info('[WATCH] Sending session ID to watch');
      await sendSessionIdToWatch(sessionId);

      // Start session on backend
      AppLogger.info('[WATCH] Starting session on backend');
      await GetIt.instance<ApiClient>().post('/rucks/$sessionId/start', {});

      // Notify the watch that the workout has started (so it updates UI and starts tracking)
      AppLogger.info('[WATCH] Notifying watch that workout has started');
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        'sessionId': sessionId,
        'ruckWeight': ruckWeight,
      });

      // Update app state
      AppLogger.info('[WATCH] Updating app state - session active');
      _isSessionActive = true;
      _ruckWeight = ruckWeight;
      _currentSessionHeartRateSamples = [];
      AppLogger.info('[WATCH] Session started successfully');

      // Send event to BLoC to update UI

    } catch (e) {
      debugPrint('[ERROR] Failed to process session start from Watch: $e');
    }
  }
  
  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch(Map<String, dynamic> data) async {
    try {
      AppLogger.info('[WATCH] Handling session end from watch');
      AppLogger.info('[WATCH] Saving ${_currentSessionHeartRateSamples.length} heart rate samples to storage');
      // Save heart rate samples to storage
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
      AppLogger.info('[WATCH] Heart rate samples saved successfully');
      
    } catch (e) {
      AppLogger.error('[WATCH] Failed to handle session end from Watch: $e');
    }
  }
  
  /// Handle a session pause from the watch
  Future<void> _handlePauseSessionFromWatch(Map<String, dynamic> data) async {
    try {
    } catch (e) {
      debugPrint('[ERROR] Failed to pause session from Watch: $e');
    }
  }
  
  /// Handle a session resume from the watch
  Future<void> _handleResumeSessionFromWatch(Map<String, dynamic> data) async {
    try {
    } catch (e) {
      debugPrint('[ERROR] Failed to resume session from Watch: $e');
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
      debugPrint('[ERROR] Failed to start session on Watch: $e');
    }
  }
  
  /// Send the session ID to the watch so it can include it in API calls
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
  
  /// Private helper to send a message to the watch via the session channel
  Future<void> _sendMessageToWatch(Map<String, dynamic> message) async {
    try {
      AppLogger.debug('[WATCH] Sending message to watch: ${message['command']}');
      await _watchSessionChannel.invokeMethod('sendMessage', message);
      AppLogger.debug('[WATCH] Message sent successfully');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send message to Watch: $e');
      AppLogger.error('[WATCH] Message details: $message');
      AppLogger.error('[WATCH] Error: $e');
    }
  }
  
  /// Test connectivity to watch by sending a ping message
  /// Use this to verify that the watch app can receive messages
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
  
  /// Send a split notification to the watch when a distance milestone is reached
  /// This will trigger a haptic feedback and notification on the watch
  Future<bool> sendSplitNotification({
    required double splitDistance, // Current milestone (e.g., 1.0 km or 1.0 mi)
    required Duration splitDuration, // Time taken for this split
    required double totalDistance, // Total distance so far
    required Duration totalDuration, // Total duration so far
    required bool isMetric, // Whether user prefers metric units
  }) async {
    try {
      AppLogger.info('[WATCH] Sending split notification: $splitDistance ${isMetric ? 'km' : 'mi'}, time: ${_formatDuration(splitDuration)}');
      
      // Format distances with appropriate units
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

  /// Update session metrics on the watch
  Future<bool> updateSessionOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
  }) async {
    AppLogger.debug('[WATCH] updateSessionOnWatch called with: distance: $distance, duration: ${duration.inSeconds}, pace: $pace, isPaused: $isPaused, heartRate: $_currentHeartRate');
    // Update local state
    _currentDistance = distance;
    _currentDuration = duration;
    _currentPace = pace;
    _isPaused = isPaused;
    
    try {
      // Send an explicit updateMetrics message via WatchConnectivity
      await _sendMessageToWatch({
        'command': 'updateMetrics',
        'metrics': {
          'distance': distance,
          'duration': duration.inSeconds,
          'pace': pace,
          'isPaused': isPaused,
          if (_currentHeartRate != null) 'heartRate': _currentHeartRate,
        },
      });
      return true;
    } catch (e) {
      AppLogger.error('[WATCH] Failed to update session on Watch: $e');
      return false;
    }
  }
  
  /// Helper method to format duration as MM:SS or HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
    } else {
      return '${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}';
    }
  }
  
  /// Pause the session on the watch
  Future<bool> pauseSessionOnWatch() async {
    _isPaused = true;
    
    try {
      final api = FlutterRuckingApi();
      await api.pauseSessionOnWatch();
      return true;
    } catch (e) {
      debugPrint('[ERROR] Failed to pause session on Watch: $e');
      return false;
    }
  }
  
  /// Resume the session on the watch
  Future<bool> resumeSessionOnWatch() async {
    _isPaused = false;
    
    try {
      final api = FlutterRuckingApi();
      await api.resumeSessionOnWatch();
      return true;
    } catch (e) {
      debugPrint('[ERROR] Failed to resume session on Watch: $e');
      return false;
    }
  }
  
  /// End the session on the watch
  Future<bool> endSessionOnWatch() async {
    _isSessionActive = false;
    
    try {
      // Save heart rate samples to storage
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
      
      final api = FlutterRuckingApi();
      await api.endSessionOnWatch();
      return true;
    } catch (e) {
      debugPrint('[ERROR] Failed to end session on Watch: $e');
      return false;
    }
  }
  
  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    _currentHeartRate = heartRate;
    // Notify health service if needed
    if (_isSessionActive) {
      _healthService.updateHeartRate(heartRate);
      // Store heart rate sample with timestamp
      final sample = HeartRateSample(
        timestamp: DateTime.now(),
        bpm: heartRate.toInt(),
      );
      _currentSessionHeartRateSamples.add(sample);
    }
    // Broadcast to listeners
    _heartRateController.add(heartRate);
  }
  
  /// Stream to listen for heart rate updates from the Watch
  Stream<double> get onHeartRateUpdate => _heartRateController.stream;
  
  /// Get current heart rate
  double? getCurrentHeartRate() => _currentHeartRate;
  
  /// Get current session heart rate samples
  List<HeartRateSample> getCurrentSessionHeartRateSamples() => _currentSessionHeartRateSamples;
  
  /// Helper to get user weight from preferences
  Future<double?> _getUserWeight() async {
    try {
      return await _userPrefsChannel.invokeMethod('getUserWeight');
    } catch (e) {
      debugPrint('Error getting user weight: $e');
      return null;
    }
  }
  
  void dispose() {
    _sessionEventController.close();
    _healthDataController.close();
    _heartRateController.close();
  }
}

/// Implementation of the RuckingApi for handling watch messages
class RuckingApiHandler extends RuckingApi {
  final WatchService _watchService;
  
  RuckingApiHandler(this._watchService);
  
  @override
  Future<bool> startSessionFromWatch(double ruckWeight) async {
    debugPrint('[INFO] Starting session from watch with weight: $ruckWeight');
    try {
      // Create new ruck session via backend API
      final apiClient = GetIt.instance<ApiClient>();
      final authService = GetIt.instance<AuthService>();
      final user = await authService.getCurrentUser();
      if (user == null) {
        debugPrint('[ERROR] No authenticated user found. Cannot create session.');
        return false;
      }

      // Use user's default body weight if available
      final double? userWeightKg = user.weightKg;

      // Minimal payload for session creation
      final payload = {
        'ruck_weight_kg': ruckWeight,
        'user_weight_kg': userWeightKg,
        'status': 'in_progress',
        'user_id': user.userId, // Ensure user ID is included
        'started_from': 'apple_watch',
        'start_time': DateTime.now().toUtc().toIso8601String(),
      };
      
      final response = await apiClient.post('/rucks', payload);
      debugPrint('[INFO] Session created from watch: $response');

      // Update app state
      _watchService._isSessionActive = true;
      _watchService._isPaused = false;
      _watchService._ruckWeight = ruckWeight;

      // Auto-navigate to active session screen if context is available
      // (Assume navigatorKey is set in your app for global navigation)
      final navigatorKey = GetIt.instance<GlobalKey<NavigatorState>>();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/activeSession',
        (route) => false,
        arguments: response, // Pass the session data if needed
      );

      return true;
    } catch (e) {
      debugPrint('[ERROR] Failed to create session from watch: $e');
      return false;
    }
  }
  
  @override
  Future<bool> pauseSessionFromWatch() async {
    // Implement pausing an active session
    debugPrint('[INFO] Pausing session from watch');
    
    // You'll need to implement this logic to interact with your existing app
    return true;
  }
  
  @override
  Future<bool> resumeSessionFromWatch() async {
    // Implement resuming a paused session
    debugPrint('[INFO] Resuming session from watch');
    
    // You'll need to implement this logic to interact with your existing app
    return true;
  }
  
  @override
  Future<bool> endSessionFromWatch(int duration, double distance, double calories) async {
    // Implement ending a session
    debugPrint('[INFO] Ending session from watch. Duration: $duration, Distance: $distance, Calories: $calories');
    
    // You'll need to implement this logic to interact with your existing app
    return true;
  }
  
  @override
  Future<bool> updateHeartRateFromWatch(double heartRate) async {
    // Handle heart rate updates from watch
    _watchService.handleWatchHeartRateUpdate(heartRate);
    return true;
  }

  @override
  Future<bool> startSessionOnWatch(double ruckWeight) async {
    // This method is for Flutter->Watch communication
    // It's implemented in RuckingApi but we don't need logic here
    // since our WatchService handles this using FlutterRuckingApi directly
    debugPrint('[INFO] startSessionOnWatch called on Flutter side, ignoring.');
    return true;
  }

  @override
  Future<bool> updateSessionOnWatch(double distance, double duration, double pace, bool isPaused) async {
    // This method is for Flutter->Watch communication
    // It's implemented in RuckingApi but we don't need logic here
    // since our WatchService handles this using FlutterRuckingApi directly
    debugPrint('[INFO] updateSessionOnWatch called on Flutter side, ignoring.');
    return true;
  }
}
