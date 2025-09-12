import 'dart:async';
import 'dart:io';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/services/image_cache_manager.dart';

/// Service to monitor app memory usage and prevent crashes
class MemoryMonitorService {
  static Timer? _monitoringTimer;
  static const Duration _monitoringInterval = Duration(minutes: 2);
  static const double _warningThresholdMb =
      700.0; // Appropriate for GPS tracking apps
  static const double _criticalThresholdMb =
      1000.0; // Realistic for modern devices with Flutter + GPS

  /// Start memory monitoring
  static void startMonitoring() {
    if (_monitoringTimer != null) return;

    AppLogger.info('🧠 Starting memory monitoring');

    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _checkMemoryUsage();
    });
  }

  /// Stop memory monitoring
  static void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    AppLogger.info('🧠 Stopped memory monitoring');
  }

  /// Check current memory usage and alert if high
  static void _checkMemoryUsage() {
    try {
      final memoryInfo = getCurrentMemoryInfo();
      final memoryUsageMb = memoryInfo['memory_usage_mb'] as double;

      if (memoryUsageMb > _criticalThresholdMb) {
        AppLogger.critical('CRITICAL MEMORY USAGE DETECTED',
            exception: {
              'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
              'threshold_mb': _criticalThresholdMb.toStringAsFixed(1),
              'platform': Platform.isIOS ? 'iOS' : 'Android',
            }.toString());

        // Trigger emergency memory cleanup
        unawaited(forceMemoryCleanup());

        // Send to error handler for tracking - wrapped to prevent secondary errors
        try {
          AppErrorHandler.handleCriticalError(
            'critical_memory_usage',
            Exception('Memory usage at ${memoryUsageMb.toStringAsFixed(1)}MB'),
            context: {
              'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
              'platform': Platform.isIOS ? 'iOS' : 'Android',
            },
          );
        } catch (errorHandlerException) {
          // If error reporting fails, log it but don't crash monitoring
          AppLogger.error(
              'Error reporting failed during memory monitoring: $errorHandlerException');
        }
      } else if (memoryUsageMb > _warningThresholdMb) {
        AppLogger.warning(
            'High memory usage detected: ${memoryUsageMb.toStringAsFixed(1)}MB');

        // Clear only photo cache at warning level (less aggressive)
        unawaited(ImageCacheManager.clearPhotoCache());
        AppLogger.info('🧹 Cleared photo cache due to high memory usage');
      }
    } catch (e) {
      AppLogger.error('Failed to check memory usage: $e');
    }
  }

  /// Get current memory usage information
  static Map<String, dynamic> getCurrentMemoryInfo() {
    try {
      final processInfo = ProcessInfo.currentRss;
      final memoryUsageMb = processInfo / (1024 * 1024); // Convert bytes to MB

      return {
        'memory_usage_mb': memoryUsageMb,
        'process_rss_bytes': processInfo,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      AppLogger.warning('Failed to get memory info: $e');
      return {
        'memory_usage_mb': 0.0,
        'process_rss_bytes': 0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Force memory cleanup
  static Future<void> forceMemoryCleanup() async {
    try {
      AppLogger.info('🧹 Forcing memory cleanup');

      // Clear image caches to free up memory
      await ImageCacheManager.clearAllCaches();
      AppLogger.info('🧹 Cleared all image caches');

      // Note: Dart doesn't provide direct garbage collection control
      // The cache clearing should be sufficient to reduce memory pressure
      AppLogger.info('🧹 Memory cleanup completed');
    } catch (e) {
      AppLogger.error('Failed to force memory cleanup: $e');
    }
  }

  /// Report potential memory-related crash precursor
  static void reportMemoryPressure({
    required String sessionId,
    required double memoryUsageMb,
    required int pendingLocationPoints,
    required int pendingHeartRateSamples,
    required Duration sessionDuration,
  }) {
    try {
      AppLogger.critical(
          'MEMORY PRESSURE DETECTED - DATA PRESERVATION ACTIVATED',
          exception: {
            'session_id': sessionId,
            'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
            'pending_location_points': pendingLocationPoints,
            'pending_heart_rate_samples': pendingHeartRateSamples,
            'session_duration_minutes': sessionDuration.inMinutes,
            'platform': Platform.isIOS ? 'iOS' : 'Android',
            'timestamp': DateTime.now().toIso8601String(),
            'data_preservation_status': 'ACTIVE - NO DATA LOSS',
          }.toString());

      // Send to error handler for crash correlation
      AppErrorHandler.handleCriticalError(
        'memory_pressure_data_preservation',
        Exception(
            'Memory pressure at ${memoryUsageMb.toStringAsFixed(1)}MB - data preservation active'),
        context: {
          'session_id': sessionId,
          'memory_usage_mb': memoryUsageMb.toStringAsFixed(1),
          'pending_location_points': pendingLocationPoints.toString(),
          'pending_heart_rate_samples': pendingHeartRateSamples.toString(),
          'session_duration_minutes': sessionDuration.inMinutes.toString(),
          'platform': Platform.isIOS ? 'iOS' : 'Android',
          'data_preservation_status': 'ACTIVE',
        },
      );
    } catch (e) {
      AppLogger.error('Failed to report memory pressure: $e');
    }
  }
}
