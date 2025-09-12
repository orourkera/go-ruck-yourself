import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service to handle Android-specific optimizations for background location tracking
class AndroidOptimizationService {
  static AndroidOptimizationService? _instance;
  static AndroidOptimizationService get instance =>
      _instance ??= AndroidOptimizationService._();
  AndroidOptimizationService._();

  /// Request all critical permissions for reliable background location tracking
  Future<bool> requestCriticalPermissions() async {
    if (!Platform.isAndroid) return true;

    AppLogger.info(
        'Requesting critical Android permissions for background location...');

    bool allGranted = true;

    try {
      // 1. Basic location permissions
      final locationStatus = await Permission.locationWhenInUse.request();
      AppLogger.info('Location when in use: $locationStatus');
      if (!locationStatus.isGranted) allGranted = false;

      // 2. Background location (Android 10+)
      final backgroundLocationStatus =
          await Permission.locationAlways.request();
      AppLogger.info('Background location: $backgroundLocationStatus');
      if (!backgroundLocationStatus.isGranted) allGranted = false;

      // 3. Battery optimization exemption (CRITICAL for GPS tracking)
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        AppLogger.info('Requesting battery optimization exemption...');
        final batteryStatus =
            await Permission.ignoreBatteryOptimizations.request();
        AppLogger.info('Battery optimization exemption: $batteryStatus');
        if (!batteryStatus.isGranted) {
          AppLogger.warning(
              'Battery optimization exemption denied - GPS may be throttled');
          allGranted = false;
        }
      }

      // 4. System alert window (helps prevent app killing)
      if (await Permission.systemAlertWindow.isDenied) {
        AppLogger.info('Requesting system alert window permission...');
        final alertStatus = await Permission.systemAlertWindow.request();
        AppLogger.info('System alert window: $alertStatus');
        // This permission is optional - don't fail if denied
      }

      return allGranted;
    } catch (e) {
      AppLogger.error('Error requesting critical permissions', exception: e);
      return false;
    }
  }

  /// Check if all critical permissions are granted
  Future<bool> hasAllCriticalPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      // Check location permissions
      final locationWhenInUse = await Permission.locationWhenInUse.isGranted;
      final backgroundLocation = await Permission.locationAlways.isGranted;
      final batteryOptimization =
          await Permission.ignoreBatteryOptimizations.isGranted;

      AppLogger.info('Permission status:');
      AppLogger.info('  Location when in use: $locationWhenInUse');
      AppLogger.info('  Background location: $backgroundLocation');
      AppLogger.info('  Battery optimization exemption: $batteryOptimization');

      return locationWhenInUse && backgroundLocation && batteryOptimization;
    } catch (e) {
      AppLogger.error('Error checking permissions', exception: e);
      return false;
    }
  }

  /// Get detailed permission status for debugging
  Future<Map<String, String>> getPermissionStatus() async {
    if (!Platform.isAndroid) {
      return {'platform': 'Not Android'};
    }

    final status = <String, String>{};

    try {
      status['locationWhenInUse'] =
          (await Permission.locationWhenInUse.status).toString();
      status['locationAlways'] =
          (await Permission.locationAlways.status).toString();
      status['batteryOptimization'] =
          (await Permission.ignoreBatteryOptimizations.status).toString();
      status['systemAlertWindow'] =
          (await Permission.systemAlertWindow.status).toString();
      status['notification'] =
          (await Permission.notification.status).toString();

      return status;
    } catch (e) {
      AppLogger.error('Error getting permission status', exception: e);
      return {'error': e.toString()};
    }
  }

  /// Log current Android optimization status for debugging
  Future<void> logOptimizationStatus() async {
    if (!Platform.isAndroid) return;

    AppLogger.info('=== Android Optimization Status ===');

    final permissions = await getPermissionStatus();
    permissions.forEach((key, value) {
      AppLogger.info('$key: $value');
    });

    // Check if battery optimization is actually working
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (batteryStatus.isGranted) {
      AppLogger.info(
          '✅ Battery optimization exemption granted - GPS should not be throttled');
    } else {
      AppLogger.warning(
          '⚠️ Battery optimization exemption denied - GPS may be throttled during background operation');
    }

    AppLogger.info('=== End Status ===');
  }

  /// Show user guidance for manually enabling permissions if automatic request fails
  String getManualPermissionInstructions() {
    return '''
To ensure reliable GPS tracking during your ruck sessions:

1. Open Android Settings
2. Go to Apps → Ruck → Permissions
3. Enable "Location" and set to "Allow all the time"
4. Go to Apps → Ruck → Battery
5. Enable "Unrestricted" or "Don't optimize"
6. Some devices (Samsung, Xiaomi, etc.) have additional settings:
   - Samsung: Settings → Apps → Ruck → Battery → Allow background activity
   - Xiaomi: Settings → Apps → Manage apps → Ruck → Battery saver → No restrictions

This prevents Android from throttling GPS during background operation.
''';
  }

  /// Check if this is a problematic OEM device
  bool isProblematiOEMDevice() {
    final manufacturer = Platform.operatingSystemVersion.toLowerCase();

    // Known problematic OEMs that aggressively kill background apps
    return manufacturer.contains('samsung') ||
        manufacturer.contains('xiaomi') ||
        manufacturer.contains('huawei') ||
        manufacturer.contains('oppo') ||
        manufacturer.contains('vivo') ||
        manufacturer.contains('oneplus');
  }

  /// Get OEM-specific optimization tips
  String getOEMSpecificTips() {
    final version = Platform.operatingSystemVersion.toLowerCase();

    if (version.contains('samsung')) {
      return 'Samsung devices: Go to Settings → Apps → Ruck → Battery → Allow background activity';
    } else if (version.contains('xiaomi')) {
      return 'Xiaomi devices: Settings → Apps → Manage apps → Ruck → Battery saver → No restrictions';
    } else if (version.contains('huawei')) {
      return 'Huawei devices: Settings → Apps → Ruck → Battery → App launch → Manage manually';
    } else {
      return 'Check your device\'s battery optimization settings and whitelist the Ruck app';
    }
  }
}
