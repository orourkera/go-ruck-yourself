import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';

/// Implementation of health service using the health package
class HealthService {
  final Health health = Health();
  bool _isAuthorized = false;
  String _userId = '';
  String _platform = '';
  
  // Base keys - will be prefixed with userId for user-specific settings
  static const String _hasSeenIntroKeyBase = 'health_has_seen_intro';
  static const String _isHealthIntegrationEnabledKeyBase = 'health_integration_enabled';
  static const String _hasAppleWatchKeyBase = 'has_apple_watch';
  
  // Set the current user ID to make settings user-specific
  void setUserId(String userId) {
    _userId = userId;
  }
  
  // Get user-specific keys
  String get _hasSeenIntroKey => '${_userId}_$_hasSeenIntroKeyBase';
  String get _isHealthIntegrationEnabledKey => '${_userId}_$_isHealthIntegrationEnabledKeyBase';
  String get _hasAppleWatchKey => '${_userId}_$_hasAppleWatchKeyBase';

  /// Request authorization for health data access
  Future<bool> requestAuthorization() async {
    try {
      // Request permissions for workouts and other types
      List<HealthDataType> types = [
        HealthDataType.WORKOUT,
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
      ];
      
      // Request WRITE access for all requested types
      final List<HealthDataAccess> permissions =
          List.filled(types.length, HealthDataAccess.WRITE);
      
      // Debug: log authorization request types
      AppLogger.info('[INFO] HealthService: Requesting HealthKit authorization for types: $types with permissions: $permissions');
      
      // This call will trigger the iOS permission dialog
      bool requested = await health.requestAuthorization(types, permissions: permissions);
      // Debug: log authorization result
      AppLogger.info('[INFO] HealthService: HealthKit authorization result: $requested');
      _isAuthorized = requested;
      
      if (requested) {
        // If permissions granted, mark integration as enabled
        await setHealthIntegrationEnabled(true);
      }
      
      return requested;
    } catch (e) {
      AppLogger.error('[ERROR] HealthService: Error requesting health authorization: $e');
      return false;
    }
  }

  /// Write workout data to health store
  Future<bool> writeHealthData(double distanceMeters, double caloriesBurned, DateTime startTime, DateTime endTime) async {
    if (!_isAuthorized) {
      bool authorized = await requestAuthorization();
      if (!authorized) return false;
    }

    bool success = true;

    try {
      // Write distance data
      success &= await health.writeHealthData(
        value: distanceMeters,
        type: HealthDataType.DISTANCE_WALKING_RUNNING,
        startTime: startTime,
        endTime: endTime,
        unit: HealthDataUnit.METER,
      );
      
      // Write calorie data
      success &= await health.writeHealthData(
        value: caloriesBurned,
        type: HealthDataType.ACTIVE_ENERGY_BURNED,
        startTime: startTime,
        endTime: endTime,
        unit: HealthDataUnit.KILOCALORIE,
      );
    } catch (e) {
      AppLogger.error('[ERROR] HealthService: Error writing health data: $e');
      return false;
    }

    return success;
  }

  /// Save a complete ruck session as a workout in HealthKit
  /// This creates a HKWorkout with the hiking activity type
  Future<bool> saveRuckWorkout({
    required double distanceMeters,
    required double caloriesBurned,
    required DateTime startTime,
    required DateTime endTime,
    double? ruckWeightKg,
    double? elevationGainMeters,
    double? elevationLossMeters,
    double? heartRate,
  }) async {
    AppLogger.info('[INFO] HealthService: Saving workout with distance=${distanceMeters}m, calories=$caloriesBurned');
    if (!_isAuthorized) {
      await _requestAuthorization();
      if (!_isAuthorized) {
        return false;
      }
    }
    
    try {
      // Convert to health plugin units
      final activityType = _platform == 'ios'
          ? HealthWorkoutActivityType.HIKING 
          : HealthWorkoutActivityType.WALKING;

      // Create workout metadata object for additional stats
      final metadata = <String, dynamic>{};
      
      // Include ruck weight if available (as kilograms)
      if (ruckWeightKg != null && ruckWeightKg > 0) {
        metadata['ruckWeightKg'] = ruckWeightKg;
      }
      
      // Include elevation data if available
      if (elevationGainMeters != null && elevationGainMeters > 0) {
        metadata['elevationGainMeters'] = elevationGainMeters;
      }
      
      if (elevationLossMeters != null && elevationLossMeters > 0) {
        metadata['elevationLossMeters'] = elevationLossMeters;
      }
      
      // Include heart rate data if available
      if (heartRate != null && heartRate > 0) {
        metadata['averageHeartRateBpm'] = heartRate;
      }
      
      // Save the workout to HealthKit/Google Fit
      final success = await _health.writeWorkoutData(
        activityType: activityType,
        start: startTime,
        end: endTime,
        totalDistance: distanceMeters,
        totalDistanceUnit: HealthDataUnit.METER,
        totalEnergyBurned: caloriesBurned.toInt(),
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );

      AppLogger.info('[INFO] HealthService: Workout saved successfully: $success');
      return success;
    } catch (e) {
      AppLogger.error('[ERROR] HealthService: Failed to save workout: $e');
      return false;
    }
  }

  /// Checks if the user has seen the health integration intro screen
  Future<bool> hasSeenIntro() async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when checking health intro status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenIntroKey) ?? false;
  }

  /// Marks the health integration intro screen as seen
  Future<void> setHasSeenIntro() async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when setting health intro status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenIntroKey, true);
  }

  /// Check if health integration is available on this device
  Future<bool> isHealthIntegrationAvailable() async {
    try {
      // On iOS, Apple Health is built into the OS, so it's always available
      if (Platform.isIOS) {
        return true;
      }
      
      // On Android, we need to check if Health Connect is available
      if (Platform.isAndroid) {
        // Use the Health Connect API to check availability
        return await health.isHealthConnectAvailable();
      }
      
      // Not available on other platforms
      return false;
    } catch (e) {
      AppLogger.error('[ERROR] HealthService: Error checking health integration: $e');
      return false;
    }
  }

  /// Checks if the user has enabled health integration
  Future<bool> isHealthIntegrationEnabled() async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when checking health integration status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isHealthIntegrationEnabledKey) ?? false;
  }

  /// Sets health integration status
  Future<void> setHealthIntegrationEnabled(bool enabled) async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when setting health integration status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isHealthIntegrationEnabledKey, enabled);
  }

  /// Disables health integration
  Future<void> disableHealthIntegration() async {
    await setHealthIntegrationEnabled(false);
  }

  /// Sets whether the user has an Apple Watch
  Future<void> setHasAppleWatch(bool hasWatch) async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when setting Apple Watch status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasAppleWatchKey, hasWatch);
  }
  
  /// Checks if the user has indicated they have an Apple Watch
  Future<bool> hasAppleWatch() async {
    if (_userId.isEmpty) {
      AppLogger.warning('[WARNING] HealthService: User ID not set when checking Apple Watch status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasAppleWatchKey) ?? true; // Default to true if not set
  }

  /// Read current heart rate from health store
  Future<double?> getCurrentHeartRate() async {
    if (!_isAuthorized) {
      bool authorized = await requestAuthorization();
      if (!authorized) return null;
    }

    try {
      // Fetch heart rate from last 5 minutes
      final now = DateTime.now();
      final window = const Duration(minutes: 5);
      final startTime = now.subtract(window);
      AppLogger.info('[INFO] HealthService: Fetching heart rate from $startTime to $now');
      List<HealthDataPoint> heartRateData = await health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: startTime,
        endTime: now,
      );
      AppLogger.info('[INFO] HealthService: Fetched heart rate data points: ${heartRateData.length}');
      if (heartRateData.isEmpty) {
        AppLogger.info('[INFO] HealthService: No heart rate data available in the last 5 minutes');
        return null;
      }
      
      // Sort by timestamp to get most recent reading
      heartRateData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
      final mostRecent = heartRateData.first;
      AppLogger.info('[INFO] HealthService: Most recent heart rate raw value: ${mostRecent.value} at ${mostRecent.dateFrom}');
      // Extract heart rate value dynamically, handling NumericHealthValue
      final dynamic rawValue = mostRecent.value;
      dynamic extracted = rawValue is NumericHealthValue
        ? (rawValue as dynamic).numericValue
        : rawValue;
      double? heartRateValue;
      if (extracted is num) {
        heartRateValue = extracted.toDouble();
      } else {
        heartRateValue = double.tryParse(extracted.toString());
      }
      AppLogger.info('[INFO] HealthService: Parsed heart rate: $heartRateValue');
      return heartRateValue;
    } catch (e) {
      AppLogger.error('[ERROR] HealthService: Error reading heart rate: $e');
      return null;
    }
  }

  /// Update current heart rate value
  /// This method is used to receive real-time heart rate updates from the Watch
  void updateHeartRate(double heartRate) {
    // For now, we just log the heart rate
    // This could be expanded to store the value or send to a health bloc
    AppLogger.info('[INFO] HealthService: Received heart rate update from Watch: $heartRate BPM');
    
    // In a future version, this could write to Health/HealthKit
    // Or update a heart rate stream that UI components could listen to
  }
}
