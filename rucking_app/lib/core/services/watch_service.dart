import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/data/models/ruck_session.dart';

/// Service for managing communication with Apple Watch companion app
class WatchService {
  final LocationService _locationService = GetIt.instance<LocationService>();
  final HealthService _healthService = GetIt.instance<HealthService>();
  
  // Session state
  bool _isSessionActive = false;
  bool _isPaused = false;
  double _currentDistance = 0.0;
  Duration _currentDuration = Duration.zero;
  double _currentPace = 0.0;
  double? _currentHeartRate;
  double _ruckWeight = 0.0;
  
  // Watch communication
  late FlutterRuckingApi _flutterRuckingApi;
  
  WatchService() {
    _initPlatformChannels();
  }
  
  void _initPlatformChannels() {
    // Set up Pigeon API handler (remove old setup call, use instance if needed)
    // RuckingApi.setup(RuckingApiHandler(this)); // REMOVE THIS LINE
    // FlutterRuckingApi is abstract and cannot be instantiated directly.
    // If you need to receive messages from native-to-Dart, implement FlutterRuckingApi and register with setUp().
    // Example:
    // FlutterRuckingApi.setUp(YourFlutterRuckingApiHandler());
    // For sending messages to native, use RuckingApi:
    // final ruckingApi = RuckingApi();
  }
  
  /// Start a new rucking session on the watch
  Future<bool> startSessionOnWatch(double ruckWeight) async {
    _ruckWeight = ruckWeight;
    _isSessionActive = true;
    _isPaused = false;
    
    try {
      RuckingApi().startSessionOnWatch(ruckWeight);
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
      RuckingApi().updateSessionOnWatch(
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
      RuckingApi().pauseSessionOnWatch();
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
      RuckingApi().resumeSessionOnWatch();
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
      RuckingApi().endSessionOnWatch();
      return true;
    } catch (e) {
      debugPrint('Error ending session on watch: $e');
      return false;
    }
  }
  
  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    _currentHeartRate = heartRate;
    // You can notify listeners or update UI as needed
  }
  
  /// Get current state values
  bool get isSessionActive => _isSessionActive;
  bool get isPaused => _isPaused;
  double get currentDistance => _currentDistance;
  Duration get currentDuration => _currentDuration;
  double get currentPace => _currentPace;
  double? get currentHeartRate => _currentHeartRate;
  double get ruckWeight => _ruckWeight;
}

/// Implementation of the RuckingApi for handling watch messages
class RuckingApiHandler extends RuckingApi {
  final WatchService _watchService;
  
  RuckingApiHandler(this._watchService);
  
  @override
  Future<bool> startSessionFromWatch(double ruckWeight) async {
    // Implement starting a session from the watch
    // This would typically create a session in your app's state management
    // and navigate to the active session screen
    debugPrint('Starting session from watch with weight: $ruckWeight');
    
    // You'll need to implement this logic to interact with your existing app
    // For example, creating a session and starting tracking
    return true;
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
}
