import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';

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
  
  // Public streams
  Stream<Map<String, dynamic>> get sessionEvents => _sessionEventController.stream;
  Stream<Map<String, dynamic>> get healthData => _healthDataController.stream;
  
  WatchService(this._locationService, this._healthService, this._authService) {
    _initPlatformChannels();
  }
  
  void _initPlatformChannels() {
    // Set up method channels
    _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');
    _watchHealthChannel = const MethodChannel('com.getrucky.gfy/watch_health');
    _userPrefsChannel = const MethodChannel('com.getrucky.gfy/user_preferences');
    
    // Set up method call handlers
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);
    _watchHealthChannel.setMethodCallHandler(_handleWatchHealthMethod);
    
    // Register the RuckingApi handler
    RuckingApi.setUp(RuckingApiHandler(this));
  }
  
  /// Handle method calls from the watch session channel
  Future<dynamic> _handleWatchSessionMethod(MethodCall call) async {
    switch (call.method) {
      case 'onWatchSessionUpdated':
        final data = call.arguments as Map<String, dynamic>;
        _sessionEventController.add(data);
        
        // Check if a session was started from the watch
        if (data['action'] == 'startSession') {
          await _handleSessionStartedFromWatch(data);
        } else if (data['action'] == 'endSession') {
          await _handleSessionEndedFromWatch(data);
        } else if (data['action'] == 'pauseSession') {
          _isPaused = true;
        } else if (data['action'] == 'resumeSession') {
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
    switch (call.method) {
      case 'onHealthDataUpdated':
        final data = call.arguments as Map<String, dynamic>;
        _healthDataController.add(data);
        
        // Update heart rate if needed
        if (data['type'] == 'heartRate') {
          _currentHeartRate = data['value'];
          
          // If session is active, send to health service
          if (_isSessionActive) {
            _healthService.updateHeartRate(_currentHeartRate!);
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
    
    try {
      // Get current user
      final authState = await _authService.getCurrentUser();
      if (authState == null) {
        debugPrint('[ERROR] No authenticated user found - cannot create session from Watch');
        return;
      }
      
      // Create ruck session
      final response = await GetIt.instance<ApiClient>().post('/rucks', {
        'ruckWeight': ruckWeight,
      });
      
      if (response == null || !response.containsKey('id')) {
        return;
      }
      
      // Extract session ID and start the session
      final String sessionId = response['id'].toString();
      
      // Send session ID to watch so it can include it in API calls
      await sendSessionIdToWatch(sessionId);
      
      // Start session on backend
      await GetIt.instance<ApiClient>().post('/rucks/$sessionId/start', {});
      
      // Send event to BLoC to update UI
      /* // Temporarily commented out - removing watch functionality
      GetIt.instance<ActiveSessionBloc>().add(SessionStarted(
        ruckId: sessionId,
        ruckWeight: ruckWeight,
        userWeight: await _getUserWeight() ?? 70.0, // Get from service or use default
      ));
      */
      
    } catch (e) {
      debugPrint('[ERROR] Failed to process session start from Watch: $e');
    }
  }
  
  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch(Map<String, dynamic> data) async {
    try {
      final bloc = GetIt.instance<ActiveSessionBloc>();
      if (bloc.state is ActiveSessionRunning) {
        bloc.add(const SessionCompleted());
      }
    } catch (e) {
      debugPrint('[ERROR] Failed to handle session end from Watch: $e');
    }
  }
  
  /// Handle a session pause from the watch
  Future<void> _handlePauseSessionFromWatch(Map<String, dynamic> data) async {
    try {
      final bloc = GetIt.instance<ActiveSessionBloc>();
      if (bloc.state is ActiveSessionRunning && !(bloc.state as ActiveSessionRunning).isPaused) {
        bloc.add(const SessionPaused());
      }
    } catch (e) {
      debugPrint('[ERROR] Failed to pause session from Watch: $e');
    }
  }
  
  /// Handle a session resume from the watch
  Future<void> _handleResumeSessionFromWatch(Map<String, dynamic> data) async {
    try {
      final bloc = GetIt.instance<ActiveSessionBloc>();
      if (bloc.state is ActiveSessionRunning && (bloc.state as ActiveSessionRunning).isPaused) {
        bloc.add(const SessionResumed());
      }
    } catch (e) {
      debugPrint('[ERROR] Failed to resume session from Watch: $e');
    }
  }
  
  /// Start a new rucking session on the watch
  Future<void> startSessionOnWatch(double ruckWeight) async {
    try {
      await _sendMessageToWatch({
        'command': 'startSession',
        'ruckWeight': ruckWeight,
      });
    } catch (e) {
      debugPrint('[ERROR] Failed to start session on Watch: $e');
    }
  }
  
  /// Update session metrics on the watch
  Future<bool> updateSessionOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
  }) async {
    // Update local state
    _currentDistance = distance;
    _currentDuration = duration;
    _currentPace = pace;
    _isPaused = isPaused;
    
    try {
      final api = FlutterRuckingApi();
      await api.updateSessionOnWatch(
        distance,
        duration.inSeconds.toDouble(),
        pace,
        isPaused,
      );
      return true;
    } catch (e) {
      debugPrint('[ERROR] Failed to update session on Watch: $e');
      return false;
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
    }
  }
  
  /// Sync user preferences to the watch
  Future<bool> syncUserPreferencesToWatch({
    required String userId,
    required bool useMetricUnits,
  }) async {
    try {
      // Define the method channel for user preferences
      const methodChannel = MethodChannel('com.getrucky.gfy/user_preferences');
      
      // Call the native method to sync preferences
      final result = await methodChannel.invokeMethod<bool>(
        'syncUserPreferences',
        {
          'userId': userId,
          'useMetricUnits': useMetricUnits,
        },
      );
      
      debugPrint('[INFO] Sync user preferences to watch result: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ERROR] Failed to sync user preferences to watch: $e');
      return false;
    }
  }
  
  /// Send the backend session ID to the watch so that it can include it
  /// in subsequent API calls originating from the watch.
  Future<void> sendSessionIdToWatch(String sessionId) async {
    await _sendMessageToWatch({
      'command': 'setSessionId',
      'sessionId': sessionId,
    });
  }
  
  /// Low-level helper to deliver a JSON-like map to the watch via the
  /// session MethodChannel. All higher-level watch messages should flow
  /// through this utility so that we have a single point for error handling.
  Future<void> _sendMessageToWatch(Map<String, dynamic> message) async {
    try {
      await _watchSessionChannel.invokeMethod('message', message);
    } on PlatformException catch (e) {
      debugPrint('[ERROR] Failed to send message to Watch: $e – $message');
    }
  }
  
  /// Get current state values
  bool get isSessionActive => _isSessionActive;
  bool get isPaused => _isPaused;
  double get currentDistance => _currentDistance;
  Duration get currentDuration => _currentDuration;
  double get currentPace => _currentPace;
  double? get currentHeartRate => _currentHeartRate;
  double get ruckWeight => _ruckWeight;
  
  void dispose() {
    _sessionEventController.close();
    _healthDataController.close();
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
