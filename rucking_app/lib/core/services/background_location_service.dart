import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

/// Platform channel for native background location service integration
/// Provides manual WakeLock control and session resurrection features like FitoTrack
class BackgroundLocationService {
  // Use different channel names for Android vs iOS
  static MethodChannel get _channel {
    if (Platform.isAndroid) {
      return const MethodChannel('com.ruck.app/background_location');
    } else {
      return const MethodChannel('com.goruckyourself.app/background_location');
    }
  }

  /// Start native background location service with manual WakeLock
  static Future<void> startBackgroundTracking() async {
    // On iOS, background location is handled by the system with proper Info.plist configuration
    // Only Android needs the custom background service for aggressive battery optimization
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startTracking');
        debugPrint('Background location tracking started');
      } on PlatformException catch (e) {
        debugPrint('Failed to start background tracking: ${e.message}');
        rethrow;
      }
    } else {
      debugPrint('iOS: Background location handled by system - no custom service needed');
    }
  }

  /// Stop native background location service and release WakeLock
  static Future<void> stopBackgroundTracking() async {
    // On iOS, background location is handled by the system with proper Info.plist configuration
    // Only Android needs the custom background service for aggressive battery optimization
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopTracking');
        debugPrint('Background location tracking stopped');
      } on PlatformException catch (e) {
        debugPrint('Failed to stop background tracking: ${e.message}');
        rethrow;
      }
    } else {
      debugPrint('iOS: Background location handled by system - no custom service needed');
    }
  }

  /// Check if background tracking is currently active
  static Future<bool> isTrackingActive() async {
    // On iOS, background location is handled by the system
    // Only Android needs the custom background service tracking status
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod('isTracking');
        return result as bool;
      } on PlatformException catch (e) {
        debugPrint('Failed to check tracking status: ${e.message}');
        return false;
      }
    } else {
      // On iOS, assume tracking is active if location permission is granted
      return true;
    }
  }

  /// Manually acquire WakeLock (fallback if Geolocator's enableWakeLock fails)
  static Future<void> acquireWakeLock() async {
    // On iOS, wake locks are handled automatically by the system during background location
    // Only Android needs manual wake lock management for aggressive battery optimization
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('acquireWakeLock');
        debugPrint('Manual WakeLock acquired');
      } on PlatformException catch (e) {
        debugPrint('Failed to acquire WakeLock: ${e.message}');
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
      try {
        await _channel.invokeMethod('releaseWakeLock');
        debugPrint('Manual WakeLock released');
      } on PlatformException catch (e) {
        debugPrint('Failed to release WakeLock: ${e.message}');
      }
    } else {
      debugPrint('iOS: WakeLock handled automatically by system');
    }
  }
}
