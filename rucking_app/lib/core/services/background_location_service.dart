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
    try {
      await _channel.invokeMethod('startTracking');
      debugPrint('Background location tracking started');
    } on PlatformException catch (e) {
      debugPrint('Failed to start background tracking: ${e.message}');
      rethrow;
    }
  }

  /// Stop native background location service and release WakeLock
  static Future<void> stopBackgroundTracking() async {
    try {
      await _channel.invokeMethod('stopTracking');
      debugPrint('Background location tracking stopped');
    } on PlatformException catch (e) {
      debugPrint('Failed to stop background tracking: ${e.message}');
      rethrow;
    }
  }

  /// Check if background tracking is currently active
  static Future<bool> isTrackingActive() async {
    try {
      final result = await _channel.invokeMethod('isTracking');
      return result as bool;
    } on PlatformException catch (e) {
      debugPrint('Failed to check tracking status: ${e.message}');
      return false;
    }
  }

  /// Manually acquire WakeLock (fallback if Geolocator's enableWakeLock fails)
  static Future<void> acquireWakeLock() async {
    try {
      await _channel.invokeMethod('acquireWakeLock');
      debugPrint('Manual WakeLock acquired');
    } on PlatformException catch (e) {
      debugPrint('Failed to acquire WakeLock: ${e.message}');
    }
  }

  /// Manually release WakeLock
  static Future<void> releaseWakeLock() async {
    try {
      await _channel.invokeMethod('releaseWakeLock');
      debugPrint('Manual WakeLock released');
    } on PlatformException catch (e) {
      debugPrint('Failed to release WakeLock: ${e.message}');
    }
  }
}
