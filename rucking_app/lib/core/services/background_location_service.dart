import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:rucking_app/core/services/app_error_handler.dart';

/// Platform channel for native background location service integration
/// Provides manual WakeLock control and session resurrection features like FitoTrack
class BackgroundLocationService {
  // Use different channel names for Android vs iOS
  static MethodChannel? get _channel {
    if (Platform.isAndroid) {
      return const MethodChannel('com.ruck.app/background_location');
    } else {
      // On iOS, return null to prevent any channel usage
      debugPrint('iOS: No background location channel needed');
      return null;
    }
  }

  /// Start native background location service with manual WakeLock
  static Future<void> startBackgroundTracking() async {
    // On iOS, background location is handled by the system with proper Info.plist configuration
    // Only Android needs the custom background service for aggressive battery optimization
    if (Platform.isAndroid) {
      final channel = _channel;
      if (channel == null) {
        debugPrint('Android: No background location channel available');
        return;
      }
      try {
        await channel.invokeMethod('startTracking');
        debugPrint('Background location tracking started');
      } on PlatformException catch (e) {
        // Monitor platform-specific background location failures
        await AppErrorHandler.handleCriticalError(
          'background_location_platform',
          e,
          context: {
            'platform': 'android',
            'error_code': e.code,
            'error_message': e.message,
          },
        );
        debugPrint('Failed to start background tracking: ${e.message}');
        rethrow;
      } catch (e) {
        // Monitor general background location failures
        await AppErrorHandler.handleError(
          'background_location_general',
          e,
          context: {
            'platform': 'android',
            'operation': 'start_tracking',
          },
        );
        debugPrint('Unexpected error starting background tracking: $e');
        // Don't rethrow - this prevents app crashes from background service issues
      }
    } else {
      debugPrint('iOS: Background location handled by system - no custom service needed');
      // On iOS, explicitly return without any native calls
      return;
    }
  }

  /// Stop native background location service and release WakeLock
  static Future<void> stopBackgroundTracking() async {
    // On iOS, background location is handled by the system with proper Info.plist configuration
    // Only Android needs the custom background service for aggressive battery optimization
    if (Platform.isAndroid) {
      final channel = _channel;
      if (channel == null) {
        debugPrint('Android: No background location channel available');
        return;
      }
      try {
        await channel.invokeMethod('stopTracking');
        debugPrint('Background location tracking stopped');
      } on PlatformException catch (e) {
        debugPrint('Failed to stop background tracking: ${e.message}');
        rethrow;
      } catch (e) {
        debugPrint('Unexpected error stopping background tracking: $e');
        // Don't rethrow - this prevents app crashes from background service issues
      }
    } else {
      debugPrint('iOS: Background location handled by system - no custom service needed');
      // On iOS, explicitly return without any native calls
      return;
    }
  }

  /// Check if background tracking is currently active
  static Future<bool> isTrackingActive() async {
    // On iOS, background location is handled by the system
    // Only Android needs the custom background service tracking status
    if (Platform.isAndroid) {
      final channel = _channel;
      if (channel == null) {
        debugPrint('Android: No background location channel available');
        return false;
      }
      try {
        final result = await channel.invokeMethod('isTracking');
        return result as bool;
      } on PlatformException catch (e) {
        debugPrint('Failed to check tracking status: ${e.message}');
        return false;
      } catch (e) {
        debugPrint('Unexpected error checking tracking status: $e');
        return false;
      }
    } else {
      // On iOS, assume tracking is active if location permission is granted
      debugPrint('iOS: Background location handled by system - returning true');
      return true;
    }
  }

  /// Manually acquire WakeLock (fallback if Geolocator's enableWakeLock fails)
  static Future<void> acquireWakeLock() async {
    // On iOS, wake locks are handled automatically by the system during background location
    // Only Android needs manual wake lock management for aggressive battery optimization
    if (Platform.isAndroid) {
      final channel = _channel;
      if (channel == null) {
        debugPrint('Android: No background location channel available');
        return;
      }
      try {
        await channel.invokeMethod('acquireWakeLock');
        debugPrint('Manual WakeLock acquired');
      } on PlatformException catch (e) {
        debugPrint('Failed to acquire WakeLock: ${e.message}');
      } catch (e) {
        debugPrint('Unexpected error acquiring WakeLock: $e');
      }
    } else {
      debugPrint('iOS: WakeLock handled automatically by system');
    }
  }

  /// Manually release WakeLock
  static Future<void> releaseWakeLock() async {
    // On iOS, wake locks are handled automatically by the system during background location
    // Only Android needs manual wake lock management for aggressive battery optimization
    if (Platform.isAndroid) {
      final channel = _channel;
      if (channel == null) {
        debugPrint('Android: No background location channel available');
        return;
      }
      try {
        await channel.invokeMethod('releaseWakeLock');
        debugPrint('Manual WakeLock released');
      } on PlatformException catch (e) {
        debugPrint('Failed to release WakeLock: ${e.message}');
      } catch (e) {
        debugPrint('Unexpected error releasing WakeLock: $e');
      }
    } else {
      debugPrint('iOS: WakeLock handled automatically by system');
    }
  }
}
