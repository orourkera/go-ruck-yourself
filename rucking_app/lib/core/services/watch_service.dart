import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'dart:convert';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:uuid/uuid.dart';

/// Service for managing communication with Apple Watch companion app
class WatchService {
  final LocationService _locationService = GetIt.instance<LocationService>();
  final HealthService _healthService = GetIt.instance<HealthService>();
  final AuthService _authService = GetIt.instance<AuthService>();
  final ActiveSessionBloc _activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
  
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
  Stream<Map<String, dynamic>> get onHeartRateUpdate => _healthDataController.stream;
  
  // Add navigatorKey for navigation purposes
  final GlobalKey<NavigatorState> navigatorKey = GetIt.instance<GlobalKey<NavigatorState>>();
  
  WatchService() {
    print("[WatchService] Initializing WatchService");
    _initPlatformChannels();
    print("[WatchService] WatchService initialization complete");
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
    print("[WatchService] Handling watch session method: ${call.method}, arguments: ${call.arguments}");
    Map<String, dynamic> data;
    if (call.arguments is String) {
      final jsonString = call.arguments as String;
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      data = jsonData;
      print("[WatchService] Parsed JSON string into data: $data");
    } else if (call.arguments is Map<String, dynamic>) {
      data = call.arguments as Map<String, dynamic>;
      print("[WatchService] Received data as Map: $data");
    } else {
      print("[WatchService] Error: Unexpected argument type for session method: ${call.arguments.runtimeType}");
      return;
    }
    
    switch (call.method) {
      case 'onWatchSessionUpdated':
        print("[WatchService] Processing onWatchSessionUpdated with action: ${data['action']}");
        if (data['action'] == 'startSession') {
          print("[WatchService] Processing startSession from watch with data: $data");
          await _handleSessionStartedFromWatch(data);
        } else if (data['action'] == 'endSession') {
          print("[WatchSession] Watch requested to end session");
          await _handleSessionEndedFromWatch();
        } else if (data['action'] == 'pauseSession') {
          print("[WatchSession] Watch requested to pause session");
          await _handlePauseSessionFromWatch();
        } else if (data['action'] == 'resumeSession') {
          print("[WatchSession] Watch requested to resume session");
          await _handleResumeSessionFromWatch();
        } else {
          print("[WatchService] Unknown session action received: ${data['action']}");
        }
        break;
      default:
        print("[WatchService] Unknown method call from watch: ${call.method}");
    }
  }
  
  /// Handle method calls from the watch health channel
  Future<dynamic> _handleWatchHealthMethod(MethodCall call) async {
    print("[WatchService] Handling watch health method: ${call.method}, arguments: ${call.arguments}");
    Map<String, dynamic> data;
    if (call.arguments is String) {
      final jsonString = call.arguments as String;
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      data = jsonData;
      print("[WatchService] Parsed JSON string into health data: $data");
    } else if (call.arguments is Map<String, dynamic>) {
      data = call.arguments as Map<String, dynamic>;
      print("[WatchService] Received health data as Map: $data");
    } else {
      print("[WatchService] Error: Unexpected argument type for health method: ${call.arguments.runtimeType}");
      return;
    }

    switch (call.method) {
      case 'onHealthDataUpdated':
        print("[WatchService] Processing onHealthDataUpdated with type: ${data['type']}");
        if (data['type'] == 'heartRate') {
          _currentHeartRate = (data['value'] as num?)?.toDouble();
          print("[WatchService] Received heart rate update from watch: $_currentHeartRate");
          if (_isSessionActive) {
            _healthService.updateHeartRate(_currentHeartRate!);
          }
        } else {
          print("[WatchService] Unknown health data type received: ${data['type']}");
        }
        break;
      case 'onHeartRateUpdate':
        await _handleHeartRateUpdate(data);
        break;
      default:
        print("[WatchService] Unknown health method call from watch: ${call.method}");
    }
  }
  
  Future<void> _handleHeartRateUpdate(Map<String, dynamic> data) async {
    final heartRate = (data['heartRate'] as num?)?.toDouble() ?? 0.0;
    print("[WatchService] Received heart rate update from Watch: $heartRate BPM");
    print("[WatchService Debug] Adding heart rate data to stream: $heartRate BPM");
    _healthDataController.add({'heartRate': heartRate});
  }
  
  /// Handle a session started from the watch
  Future<void> _handleSessionStartedFromWatch(Map<String, dynamic> data) async {
    // Update local state
    _isSessionActive = true;
    _ruckWeight = (data['ruckWeight'] as num?)?.toDouble() ?? 0.0;
    print("[WatchService] Session started from watch with ruck weight: $_ruckWeight");
    
    try {
      // Navigate to active session screen if not already there
      if (navigatorKey.currentState != null) {
        final currentRoute = ModalRoute.of(navigatorKey.currentContext!)?.settings.name;
        print("[WatchService] Current route: $currentRoute");
        if (currentRoute != '/activeSession') {
          print("[WatchService] Navigating to active session screen from watch start");
          await navigatorKey.currentState?.pushNamed(
            '/activeSession',
            arguments: {
              'ruckWeight': _ruckWeight,
              'fromWatch': true,
            },
          );
          print("[WatchService] Navigation to active session attempted");
        } else {
          print("[WatchService] Already on active session screen");
        }
      } else {
        print("[WatchService] Navigator state not available, skipping navigation");
      }
    } catch (e) {
      print("[WatchService] Error navigating to active session screen: $e");
    }
  }

  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch() async {
    print('[WatchService] Session end requested from watch.');
    
    // Dispatch SessionCompleted event to ActiveSessionBloc
    _activeSessionBloc.add(const SessionCompleted()); 
    print('[WatchService] Dispatched SessionCompleted event to ActiveSessionBloc.');
  }

  /// Handle a session pause from the watch
  Future<void> _handlePauseSessionFromWatch() async {
    print('[WatchService] Session pause requested from watch.');
    _activeSessionBloc.add(const SessionPaused()); // Dispatch SessionPaused event
    print('[WatchService] Dispatched SessionPaused event to ActiveSessionBloc.');
    // No need to manually update _isPaused here, Bloc state should handle it
  }

  /// Handle a session resume from the watch
  Future<void> _handleResumeSessionFromWatch() async {
    print('[WatchService] Session resume requested from watch.');
    _activeSessionBloc.add(const SessionResumed()); // Dispatch SessionResumed event
    print('[WatchService] Dispatched SessionResumed event to ActiveSessionBloc.');
    // No need to manually update _isPaused here, Bloc state should handle it
  }
  
  /// Start a new rucking session on the watch
  Future<bool> startSessionOnWatch(double ruckWeight) async {
    _ruckWeight = ruckWeight;
    _isSessionActive = true;
    _isPaused = false;

    try {
      final api = FlutterRuckingApi();
      await api.startSessionOnWatch(ruckWeight);
      return true;
    } catch (e) {
      debugPrint('Error starting session on watch: $e');
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
      debugPrint('Error updating session on watch: $e');
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
      debugPrint('Error pausing session on watch: $e');
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
      debugPrint('Error resuming session on watch: $e');
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
      debugPrint('Error ending session on watch: $e');
      return false;
    }
  }
  
  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    _currentHeartRate = heartRate;
    // Notify health service if needed
    if (_isSessionActive) {
      _healthService.updateHeartRate(heartRate);
      print("[WatchService Debug] Updated heart rate to HealthService: $heartRate BPM");
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
      
      debugPrint('Sync user preferences to watch result: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('Error syncing user preferences to watch: $e');
      return false;
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
  
  /// Start a rucking session from the watch app
  Future<void> startRuckSession(double ruckWeight) async {
    debugPrint('Starting session from watch with weight: $ruckWeight');
    try {
      // Create new ruck session via backend API
      final apiClient = GetIt.instance<ApiClient>();
      final authService = GetIt.instance<AuthService>();
      final user = await authService.getCurrentUser();
      if (user == null) {
        debugPrint('No authenticated user found. Cannot create session.');
        return;
      }

      final payload = {
        'ruck_weight_kg': ruckWeight,
        'user_weight_kg': user.weightKg,
        'status': 'in_progress',
        'user_id': user.userId,
        'started_from': 'apple_watch',
        'start_time': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await apiClient.post('/rucks', payload);
      debugPrint('Session created from watch: $response');

      // Update local state
      _ruckWeight = ruckWeight;
      _isSessionActive = true;
      _isPaused = false;

      // Auto-navigate to active session screen if context is available
      // (Assume navigatorKey is set in your app for global navigation)
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/activeSession',
          (route) => false,
          arguments: response,
        );
      } else {
        print("[WatchService] Navigator state not available in startRuckSession");
      }
    } catch (e) {
      debugPrint('Error starting session from watch: $e');
    }
  }
}

/// Implementation of the RuckingApi for handling watch messages
class RuckingApiHandler extends RuckingApi {
  final WatchService _watchService;
  
  RuckingApiHandler(this._watchService);
  
  @override
  Future<bool> startSessionFromWatch(double ruckWeight) async {
    debugPrint('Starting session from watch with weight: $ruckWeight');
    try {
      final apiClient = GetIt.instance<ApiClient>();
      final authService = GetIt.instance<AuthService>();
      final user = await authService.getCurrentUser();
      if (user == null) {
        debugPrint('No authenticated user found. Cannot create session.');
        return false;
      }
      final double? userWeightKg = user.weightKg;
      final payload = {
        'ruck_weight_kg': ruckWeight,
        'user_weight_kg': userWeightKg,
        'status': 'in_progress',
        'user_id': user.userId,
        'started_from': 'apple_watch',
        'start_time': DateTime.now().toUtc().toIso8601String(),
      };
      final response = await apiClient.post('/rucks', payload);
      debugPrint('Session created from watch: $response');
      final String ruckId = (response['id'] == null || response['id'].toString().trim().isEmpty)
        ? Uuid().v4()
        : response['id'].toString();
      debugPrint('Extracted ruckId: $ruckId');
      // Dispatch SessionStarted event to ActiveSessionBloc
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      activeSessionBloc.add(SessionStarted(
        ruckId: ruckId,
        userWeightKg: userWeightKg,
        ruckWeightKg: ruckWeight,
      ));
      // Navigate to active session screen
      final navigatorKey = GetIt.instance<GlobalKey<NavigatorState>>();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/activeSession',
        (route) => false,
        arguments: {'ruckId': ruckId}
      );
      return true;
    } catch (e) {
      debugPrint('Error creating session from watch: $e');
      return false;
    }
  }
  
  @override
  Future<bool> pauseSessionFromWatch() async {
    // Implement pausing an active session
    debugPrint('Pausing session from watch');
    
    // You'll need to implement this logic to interact with your existing app
    return true;
  }
  
  @override
  Future<bool> resumeSessionFromWatch() async {
    // Implement resuming a paused session
    debugPrint('Resuming session from watch');
    
    // You'll need to implement this logic to interact with your existing app
    return true;
  }
  
  @override
  Future<bool> endSessionFromWatch(int duration, double distance, double calories) async {
    // Implement ending a session
    debugPrint('Ending session from watch. Duration: $duration, Distance: $distance, Calories: $calories');
    
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
    debugPrint('startSessionOnWatch called on Flutter side, ignoring.');
    return true;
  }

  @override
  Future<bool> updateSessionOnWatch(double distance, double duration, double pace, bool isPaused) async {
    // This method is for Flutter->Watch communication
    // It's implemented in RuckingApi but we don't need logic here
    // since our WatchService handles this using FlutterRuckingApi directly
    debugPrint('updateSessionOnWatch called on Flutter side, ignoring.');
    return true;
  }
}
