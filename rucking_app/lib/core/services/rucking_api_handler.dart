import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:flutter/material.dart'; // For GlobalKey, NavigatorState
import 'package:get_it/get_it.dart'; // For GetIt
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_state.dart';

/// Implementation of the RuckingApi for handling watch messages
class RuckingApiHandler extends RuckingApi {
  final WatchService _watchService;
  final AuthBloc _authBloc;
  
  RuckingApiHandler(this._watchService) : _authBloc = GetIt.instance<AuthBloc>();
  
  @override
  Future<bool> startSessionFromWatch(double ruckWeight) async {
    AppLogger.debug('[API_HANDLER] Starting session from watch with weight: $ruckWeight');
    try {
      // Create new ruck session via backend API
      final apiClient = GetIt.instance<ApiClient>();
      final authService = GetIt.instance<AuthService>();
      final user = await authService.getCurrentUser();
      if (user == null) {
        AppLogger.error('[API_HANDLER] No authenticated user found. Cannot create session.');
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
      AppLogger.debug('[API_HANDLER] Session created from watch: $response');

      // Update app state in WatchService
      _watchService.sessionStartedFromWatchCallback(ruckWeight, response);

      // Auto-navigate to active session screen if context is available
      final navigatorKey = GetIt.instance<GlobalKey<NavigatorState>>();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/activeSession',
        (route) => false,
        arguments: response, // Pass the session data if needed
      );

      return true;
    } catch (e) {
      AppLogger.error('[API_HANDLER] Failed to create session from watch: $e');
      return false;
    }
  }
  
  @override
  Future<bool> pauseSessionFromWatch() async {
    AppLogger.debug('[API_HANDLER] Pausing session from watch');
    _watchService.pauseSessionFromWatchCallback();
    return true;
  }
  
  @override
  Future<bool> resumeSessionFromWatch() async {
    AppLogger.debug('[API_HANDLER] Resuming session from watch');
    _watchService.resumeSessionFromWatchCallback();
    return true;
  }
  
  @override
  Future<bool> endSessionFromWatch(int duration, double distance, double calories) async {
    AppLogger.debug('[API_HANDLER] Ending session from watch. Duration: $duration, Distance: $distance, Calories: $calories');
    _watchService.endSessionFromWatchCallback(duration, distance, calories);
    return true;
  }
  
  @override
  Future<bool> updateHeartRateFromWatch(double heartRate) async {
    _watchService.handleWatchHeartRateUpdate(heartRate);
    return true;
  }

  @override
  Future<bool> startSessionOnWatch(double ruckWeight) async {
    // This is Flutter -> Watch, handled by WatchService directly
    AppLogger.debug('[API_HANDLER] startSessionOnWatch called, forwarding to WatchService.');
    
    bool success = false;
    try {
      // Call the WatchService method which returns void
      await _watchService.startSessionOnWatch(ruckWeight);
      
      // If no exception occurred, consider it successful
      success = true;
      AppLogger.debug('[API_HANDLER] Successfully started session on watch with weight: $ruckWeight');
    } catch (e) {
      // Log the error
      AppLogger.error('[API_HANDLER] Failed to start session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  @override
  Future<bool> updateSessionOnWatch(double distance, double duration, double pace, bool isPaused, double calories, double elevationGain, double elevationLoss) async {
    // Get user's metric preference from the auth service
    // Default to metric (true) if not available
    final authState = _authBloc.state;
    final isMetric = authState is Authenticated ? authState.user.preferMetric : true;
    
    return _watchService.updateSessionOnWatch(
      distance: distance,
      duration: Duration(seconds: duration.toInt()),
      pace: pace,
      isPaused: isPaused,
      calories: calories, // Pass as double directly, no .toInt() conversion
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      isMetric: isMetric, // Pass the user's metric preference
    );
  }
}
