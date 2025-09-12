import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:flutter/material.dart'; // For GlobalKey, NavigatorState
import 'package:get_it/get_it.dart'; // For GetIt
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Implementation of the RuckingApi for handling watch messages
class RuckingApiHandler extends RuckingApi {
  final WatchService _watchService;
  final GetIt _getIt = GetIt.instance;

  RuckingApiHandler(this._watchService);

  @override
  Future<bool> startSessionFromWatch(double ruckWeight) async {
    AppLogger.info(
        '[API_HANDLER] Watch session creation disabled - sessions must be started from phone');
    return false;
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
  Future<bool> endSessionFromWatch(
      int duration, double distance, double calories) async {
    AppLogger.debug(
        '[API_HANDLER] Ending session from watch. Duration: $duration, Distance: $distance, Calories: $calories');
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
    AppLogger.debug(
        '[API_HANDLER] startSessionOnWatch called, forwarding to WatchService.');

    bool success = false;
    try {
      // Call the WatchService method which returns void
      await _watchService.startSessionOnWatch(ruckWeight);

      // If no exception occurred, consider it successful
      success = true;
      AppLogger.debug(
          '[API_HANDLER] Successfully started session on watch with weight: $ruckWeight');
    } catch (e) {
      // Log the error
      AppLogger.error('[API_HANDLER] Failed to start session on watch: $e');
      success = false;
    }

    // Return the success flag explicitly
    return success;
  }

  @override
  Future<bool> updateSessionOnWatch(
      double distance,
      double duration,
      double pace,
      bool isPaused,
      double calories,
      double elevationGain,
      double elevationLoss) async {
    // Get user's metric preference from the auth service
    // Default to metric (true) if not available
    bool isMetric = true; // Default to metric

    try {
      // Try to get AuthBloc from GetIt if available
      if (_getIt.isRegistered<AuthBloc>()) {
        final authBloc = _getIt<AuthBloc>();
        final authState = authBloc.state;
        if (authState is Authenticated) {
          isMetric = authState.user.preferMetric;
          AppLogger.info(
              '[API_HANDLER] User preferMetric from AuthBloc: ${authState.user.preferMetric}');
        }
      } else {
        // If AuthBloc isn't registered yet, try to get metric preference directly from AuthService
        final authService = _getIt<AuthService>();
        final user = await authService.getCurrentUser();
        if (user != null) {
          isMetric = user.preferMetric;
          AppLogger.info(
              '[API_HANDLER] User preferMetric from AuthService: ${user.preferMetric}');
        }
      }
    } catch (e) {
      AppLogger.warning(
          '[API_HANDLER] Could not access user preferences, defaulting to metric: $e');
    }

    // DEBUG: Log what we're sending to the watch
    AppLogger.info(
        '[API_HANDLER] Sending to watch: distance=$distance, isMetric=$isMetric');

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
