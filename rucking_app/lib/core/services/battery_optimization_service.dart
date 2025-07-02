import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/shared/widgets/battery_optimization_dialog.dart';

/// Service to handle Android battery optimization and background app restrictions
/// Critical for ensuring location tracking continues when app is backgrounded
class BatteryOptimizationService {
  static const String _ignoreBatteryOptimizationChecked = 'ignore_battery_optimization_checked';
  
  /// Show custom dialog explaining battery optimization before requesting system permission
  static Future<bool> showBatteryOptimizationExplanation(BuildContext context) async {
    if (!Platform.isAndroid) return true;
    
    bool userAccepted = false;
    
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return BatteryOptimizationDialog(
          onAllow: () {
            userAccepted = true;
            Navigator.of(context).pop(true);
          },
          onDeny: () {
            userAccepted = false;
            Navigator.of(context).pop(false);
          },
        );
      },
    );
    
    return userAccepted;
  }
  
  /// Check if battery optimization permissions are needed and configured
  static Future<bool> ensureBackgroundExecutionPermissions({BuildContext? context}) async {
    if (!Platform.isAndroid) {
      AppLogger.info('[BATTERY] Not Android - skipping battery optimization check');
      return true;
    }
    
    try {
      AppLogger.info('[BATTERY] Checking battery optimization permissions...');
      
      // Check if we can ignore battery optimizations
      final batteryOptimizationStatus = await Permission.ignoreBatteryOptimizations.status;
      AppLogger.info('[BATTERY] Battery optimization status: $batteryOptimizationStatus');
      AppLogger.info('[BATTERY] Status details - isDenied: ${batteryOptimizationStatus.isDenied}, isGranted: ${batteryOptimizationStatus.isGranted}, isPermanentlyDenied: ${batteryOptimizationStatus.isPermanentlyDenied}');
      
      if (!batteryOptimizationStatus.isGranted) {
        AppLogger.info('[BATTERY] Permission not granted (status: $batteryOptimizationStatus) - showing explanation dialog');
        // Show custom explanation dialog first if context is provided
        if (context != null) {
          final userAccepted = await showBatteryOptimizationExplanation(context);
          AppLogger.info('[BATTERY] User response to dialog: $userAccepted');
          if (!userAccepted) {
            AppLogger.info('[BATTERY] User declined battery optimization exemption');
            return false;
          }
        } else {
          AppLogger.warning('[BATTERY] No context provided - cannot show dialog');
        }
        
        AppLogger.info('[BATTERY] Requesting battery optimization exemption...');
        final result = await Permission.ignoreBatteryOptimizations.request();
        AppLogger.info('[BATTERY] Battery optimization request result: $result');
        return result.isGranted;
      } else {
        AppLogger.info('[BATTERY] Permission already granted (status: $batteryOptimizationStatus) - no dialog needed');
      }
      
      final isGranted = batteryOptimizationStatus.isGranted;
      AppLogger.info('[BATTERY] Final permission status - isGranted: $isGranted');
      return isGranted;
    } catch (e) {
      AppLogger.error('[BATTERY] Error checking battery optimization permissions: $e');
      return false;
    }
  }
  
  /// Check all critical permissions needed for background location tracking
  static Future<Map<String, bool>> checkBackgroundLocationPermissions() async {
    final results = <String, bool>{};
    
    if (!Platform.isAndroid) {
      results['all_granted'] = true;
      return results;
    }
    
    try {
      // Location permissions
      final locationWhenInUse = await Permission.locationWhenInUse.status;
      final locationAlways = await Permission.location.status;
      
      results['location_when_in_use'] = locationWhenInUse.isGranted;
      results['location_always'] = locationAlways.isGranted;
      
      // Battery optimization
      final batteryOptimization = await Permission.ignoreBatteryOptimizations.status;
      results['battery_optimization'] = batteryOptimization.isGranted;
      
      // Overall result
      results['all_granted'] = results.values.every((granted) => granted == true);
      
      AppLogger.info('[BATTERY] Permission status: $results');
      return results;
    } catch (e) {
      AppLogger.error('[BATTERY] Error checking permissions: $e');
      results['all_granted'] = false;
      return results;
    }
  }
  
  /// Request all necessary permissions for background tracking
  static Future<bool> requestAllBackgroundPermissions({BuildContext? context}) async {
    if (!Platform.isAndroid) return true;
    
    try {
      AppLogger.info('[BATTERY] Requesting all background permissions...');
      
      // First request location permissions
      final locationWhenInUse = await Permission.locationWhenInUse.request();
      AppLogger.info('[BATTERY] Location when in use: $locationWhenInUse');
      
      if (!locationWhenInUse.isGranted) {
        AppLogger.warning('[BATTERY] Location when in use permission denied');
        return false;
      }
      
      // Request always location (background)
      final locationAlways = await Permission.location.request();
      AppLogger.info('[BATTERY] Location always: $locationAlways');
      
      // Request battery optimization exemption with custom explanation
      PermissionStatus batteryOptimization = await Permission.ignoreBatteryOptimizations.status;
      
      if (!batteryOptimization.isGranted && context != null) {
        // Show custom explanation dialog first
        final userAccepted = await showBatteryOptimizationExplanation(context);
        if (!userAccepted) {
          AppLogger.info('[BATTERY] User declined battery optimization exemption');
          batteryOptimization = PermissionStatus.denied;
        } else {
          batteryOptimization = await Permission.ignoreBatteryOptimizations.request();
        }
      } else if (!batteryOptimization.isGranted) {
        // Fallback to direct request if no context
        batteryOptimization = await Permission.ignoreBatteryOptimizations.request();
      }
      
      AppLogger.info('[BATTERY] Battery optimization: $batteryOptimization');
      
      final allGranted = locationWhenInUse.isGranted && 
                        (locationAlways.isGranted || locationAlways.isPermanentlyDenied) &&
                        batteryOptimization.isGranted;
      
      AppLogger.info('[BATTERY] All permissions granted: $allGranted');
      return allGranted;
    } catch (e) {
      AppLogger.error('[BATTERY] Error requesting permissions: $e');
      return false;
    }
  }
  
  /// Log current power management state for debugging
  static Future<void> logPowerManagementState() async {
    if (!Platform.isAndroid) return;
    
    try {
      final permissions = await checkBackgroundLocationPermissions();
      AppLogger.info('[BATTERY] Current power management state:');
      permissions.forEach((key, value) {
        AppLogger.info('[BATTERY]   $key: $value');
      });
    } catch (e) {
      AppLogger.error('[BATTERY] Error logging power management state: $e');
    }
  }
}
