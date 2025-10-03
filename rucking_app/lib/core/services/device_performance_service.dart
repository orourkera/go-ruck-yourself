import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Provides coarse device capability heuristics so expensive features can scale down
/// gracefully on older or low-memory devices.
class DevicePerformanceService {
  DevicePerformanceService();

  bool _initialized = false;
  bool _isLowSpecDevice = false;
  int? _androidSdkInt;
  String? _iosSystemVersion;

  /// Evaluate device capabilities once per app launch.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _androidSdkInt = androidInfo.version.sdkInt;

        // Prefer the platform's low-RAM signal; modern devices running older
        // Android versions (e.g., Note20 on Android 10) should still be treated
        // as high spec when RAM is plentiful.
        final isLowRam = androidInfo.isLowRamDevice ?? false;
        _isLowSpecDevice = isLowRam;

        AppLogger.info(
          '[DEVICE_PERF] Android SDK ${androidInfo.version.sdkInt} '
          '(lowRam=$isLowRam) -> lowSpec=$_isLowSpecDevice',
        );
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _iosSystemVersion = iosInfo.systemVersion;

        // Only treat very old iOS builds as constrained. Modern devices running
        // iOS 14+ have ample performance for the cheerleader pipeline.
        final majorVersion = _parseMajorVersion(iosInfo.systemVersion);
        _isLowSpecDevice = majorVersion != null && majorVersion <= 13;

        AppLogger.info(
          '[DEVICE_PERF] iOS ${iosInfo.systemVersion} (major=$majorVersion) '
          '-> lowSpec=$_isLowSpecDevice',
        );
      } else {
        // Desktop/web builds are considered sufficiently capable by default.
        _isLowSpecDevice = false;
      }
    } catch (e) {
      AppLogger.warning('[DEVICE_PERF] Failed to inspect device profile: $e');
      _isLowSpecDevice = false;
    } finally {
      _initialized = true;
    }
  }

  bool get isInitialized => _initialized;

  bool get isLowSpecDevice => _isLowSpecDevice;

  /// Soft memory ceiling (MB) used to short-circuit AI work when close to OOM.
  double get aiCheerleaderMemorySoftLimitMb => _isLowSpecDevice ? 300.0 : 360.0;

  /// Minimum interval between cheerleader trigger evaluations.
  Duration get cheerleaderMinTriggerInterval => _isLowSpecDevice
      ? const Duration(seconds: 45)
      : const Duration(seconds: 30);

  /// How many historical cheer messages to request when building context.
  int get cheerHistoryLimit => _isLowSpecDevice ? 8 : 20;

  /// Skip location reverse-geocoding for constrained devices (expensive JSON).
  bool get shouldSkipLocationContext => _isLowSpecDevice;

  /// Skip ElevenLabs audio synthesis/playback on constrained devices.
  bool get shouldSkipAIAudio => _isLowSpecDevice;

  int? get androidSdkInt => _androidSdkInt;
  String? get iosSystemVersion => _iosSystemVersion;

  int? _parseMajorVersion(String version) {
    try {
      final parts = version.split('.');
      if (parts.isEmpty) return null;
      return int.tryParse(parts.first);
    } catch (_) {
      return null;
    }
  }
}
