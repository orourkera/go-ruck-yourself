import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'dart:async';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Implementation of health service using the health package
class HealthService {
  final Health _health = Health();
  bool _isAuthorized = false;
  String _userId = '';
  String _platform = '';
  
  // Base keys - will be prefixed with userId for user-specific settings
  static const String _hasSeenIntroKeyBase = 'health_has_seen_intro';
  static const String _isHealthIntegrationEnabledKeyBase = 'health_integration_enabled';
  static const String _hasAppleWatchKeyBase = 'has_apple_watch';
  
  // --- Heart Rate Streaming ---
  StreamController<HeartRateSample>? _heartRateController;
  Timer? _heartRateTimer;

  /// Expose a stream of live heart rate samples (every 5 seconds)
  Stream<HeartRateSample> get heartRateStream {
    // Always create a new controller if it doesn't exist or is closed
    if (_heartRateController == null || _heartRateController!.isClosed) {
      _heartRateController = StreamController<HeartRateSample>.broadcast();
      _startHeartRatePolling();
      // No default/dummy value - only send actual heart rate readings
    }
    return _heartRateController!.stream;
  }

  void _startHeartRatePolling() {
    _heartRateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final hr = await getHeartRate();
      if (hr != null) {
        _heartRateController?.add(HeartRateSample(
          timestamp: DateTime.now(),
          bpm: hr.round(),
        ));
      }
    });
  }

  void _stopHeartRatePolling() {
    _heartRateTimer?.cancel();
    _heartRateTimer = null;
  }

  // Set the current user ID to make settings user-specific
  void setUserId(String userId) {
    _userId = userId;
  }
  
  /// Request authorization to access and write health data
  Future<bool> requestAuthorization() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      AppLogger.warning('Health integration only available on iOS and Android');
      return false;
    }
    
    try {
      // Updated to use proper health data types from the health package v12.1.0
      final types = [
        HealthDataType.STEPS,
        HealthDataType.DISTANCE_WALKING_RUNNING, 
        HealthDataType.ACTIVE_ENERGY_BURNED,   
        HealthDataType.HEART_RATE, // Added permission to read Heart Rate samples
        if (Platform.isIOS) HealthDataType.WORKOUT,
      ];
      
      // Define permissions for each type: READ for steps, READ_WRITE for others
      final permissions = [
        HealthDataAccess.READ,             // Steps
        HealthDataAccess.READ_WRITE,       // Distance
        HealthDataAccess.READ_WRITE,       // Active Energy Burned
        HealthDataAccess.READ,             // Heart Rate (read only)
        if (Platform.isIOS) HealthDataAccess.READ_WRITE, // Workout (includes writing)
      ];

      // Request authorization with specific permissions
      final authorized = await _health.requestAuthorization(types, permissions: permissions);
      AppLogger.info('Health authorization request result: $authorized');
      _isAuthorized = authorized;
      
      if (authorized) {
        // If permissions granted, mark integration as enabled
        await setHealthIntegrationEnabled(true);
      }
      
      return authorized;
    } catch (e) {
      AppLogger.error('Failed to request health authorization: $e');
      return false;
    }
  }
  
  /// Check if health data access is available
  Future<bool> isHealthDataAvailable() async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    
    try {
      // Simply check if authorization can be requested
      // Since Health doesn't have an isAvailable method in v12.1.0
      return true;
    } catch (e) {
      AppLogger.error('Error checking health data availability: $e');
      return false;
    }
  }
  
  /// Write workout data to health store
  Future<bool> writeHealthData(double distanceMeters, double caloriesBurned, DateTime startTime, DateTime endTime) async {
    if (!_isAuthorized) {
      await requestAuthorization();
      if (!_isAuthorized) {
        return false;
      }
    }

    bool success = true;
    try {
      // Write distance data
      success &= await _health.writeHealthData(
        value: distanceMeters,
        type: HealthDataType.DISTANCE_WALKING_RUNNING,
        startTime: startTime,
        endTime: endTime,
      );
      
      // Write calorie data
      success &= await _health.writeHealthData(
        value: caloriesBurned,
        type: HealthDataType.ACTIVE_ENERGY_BURNED,
        startTime: startTime,
        endTime: endTime,
        unit: HealthDataUnit.KILOCALORIE,
      );
    } catch (e) {
      AppLogger.error('Error writing health data: $e');
      return false;
    }

    return success;
  }
  
  /// Save a workout to the health store
  Future<bool> saveWorkout({
    required DateTime startDate,
    required DateTime endDate,
    required double distanceKm,
    required int caloriesBurned,
    double? ruckWeightKg,
    double? elevationGainMeters,
    double? elevationLossMeters,
    double? heartRate,
  }) async {
    AppLogger.info('Saving workout with distance=${distanceKm * 1000}m, calories=$caloriesBurned');
    if (!_isAuthorized) {
      await requestAuthorization();
      if (!_isAuthorized) {
        return false;
      }
    }

    try {
      // Convert km to m for health data
      final distanceMeters = (distanceKm * 1000).toInt();
      
      bool distanceSuccess = false;
      bool caloriesSuccess = false;
      bool workoutSuccess = false;

      // Write distance and calories data points as before
      distanceSuccess = await _health.writeHealthData(
        value: distanceMeters.toDouble(),
        type: HealthDataType.DISTANCE_WALKING_RUNNING,
        startTime: startDate,
        endTime: endDate,
        unit: HealthDataUnit.METER,
      );

      caloriesSuccess = await _health.writeHealthData(
        value: caloriesBurned.toDouble(),
        type: HealthDataType.ACTIVE_ENERGY_BURNED,
        startTime: startDate,
        endTime: endDate,
        unit: HealthDataUnit.KILOCALORIE,
      );

      // --- NEW: Write WORKOUT sample ---
      if (Platform.isIOS) {
        try {
          workoutSuccess = await _health.writeHealthData(
            value: distanceMeters.toDouble(), // Some plugins require a value (distance or duration)
            type: HealthDataType.WORKOUT,
            startTime: startDate,
            endTime: endDate,
            unit: HealthDataUnit.METER, // Or HealthDataUnit.MINUTE if you prefer
          );
        } catch (e) {
          AppLogger.error('Failed to write HealthKit WORKOUT sample: $e');
          workoutSuccess = false;
        }
      }

      AppLogger.info('Health data write results - Distance: $distanceSuccess, Calories: $caloriesSuccess, Workout: $workoutSuccess');

      // Consider success if at least one data point was written
      final success = distanceSuccess || caloriesSuccess || workoutSuccess;
      AppLogger.info('Workout data saved successfully: $success');
      return success;
    } catch (e) {
      AppLogger.error('Failed to save workout: $e');
      return false;
    }
  }
  
  /// Checks if the user has seen the health integration intro screen
  Future<bool> hasSeenIntro() async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when checking health intro status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_userId}_$_hasSeenIntroKeyBase') ?? false;
  }

  /// Marks the health integration intro screen as seen
  Future<void> setHasSeenIntro() async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when setting health intro status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_userId}_$_hasSeenIntroKeyBase', true);
  }

  /// Check if health integration is available on this device
  Future<bool> isHealthIntegrationAvailable() async {
    try {
      // iOS always has HealthKit
      if (Platform.isIOS) {
        return true;
      }
      
      // On Android, we'll just check the platform version
      // Since isHealthConnectAvailable doesn't exist in v12.1.0
      if (Platform.isAndroid) {
        return true; // Assume it's available on modern Android
      }
      
      // Not available on other platforms
      return false;
    } catch (e) {
      AppLogger.error('Error checking health integration: $e');
      return false;
    }
  }

  /// Checks if the user has enabled health integration
  Future<bool> isHealthIntegrationEnabled() async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when checking health integration status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_userId}_$_isHealthIntegrationEnabledKeyBase') ?? false;
  }

  /// Sets health integration status
  Future<void> setHealthIntegrationEnabled(bool enabled) async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when setting health integration status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_userId}_$_isHealthIntegrationEnabledKeyBase', enabled);
  }

  /// Sets whether the user has an Apple Watch
  Future<void> setHasAppleWatch(bool hasWatch) async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when setting Apple Watch status');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_userId}_$_hasAppleWatchKeyBase', hasWatch);
  }
  
  /// Checks if the user has indicated they have an Apple Watch
  Future<bool> hasAppleWatch() async {
    if (_userId.isEmpty) {
      AppLogger.warning('User ID not set when checking Apple Watch status');
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_userId}_$_hasAppleWatchKeyBase') ?? true; // Default to true if not set
  }

  /// Read current heart rate from health store
  Future<double?> getHeartRate() async {
    if (!Platform.isIOS) {
      return null; // Heart rate reading currently only supported on iOS
    }
    
    try {
      // Get heart rate data from the last 5 minutes
      final now = DateTime.now();
      final window = const Duration(minutes: 5);
      final startTime = now.subtract(window);
      AppLogger.info('Fetching heart rate from $startTime to $now');
      
      // Use HealthDataType.HEART_RATE
      List<HealthDataPoint> heartRateData = await _health.getHealthDataFromTypes(
        startTime: startTime,
        endTime: now, 
        types: [HealthDataType.HEART_RATE],
      );
      
      AppLogger.info('Fetched heart rate data points: ${heartRateData.length}');
      if (heartRateData.isEmpty) {
        AppLogger.info('No heart rate data available in the last 5 minutes');
        return null;
      }
      
      // Use the most recent heart rate
      heartRateData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
      final mostRecent = heartRateData.first;
      AppLogger.info('Most recent heart rate raw value: ${mostRecent.value} at ${mostRecent.dateFrom}');
      
      // Extract heart rate value dynamically, handling NumericHealthValue
      final dynamic rawValue = mostRecent.value;
      double? heartRateValue;
      
      if (rawValue is NumericHealthValue) {
        // Convert num to double safely
        heartRateValue = rawValue.numericValue?.toDouble();
      } else if (rawValue is num) {
        // Direct num type
        heartRateValue = rawValue.toDouble();
      } else {
        // Try parsing as string
        heartRateValue = double.tryParse(rawValue.toString());
      }
      
      AppLogger.info('Parsed heart rate: $heartRateValue');
      return heartRateValue;
    } catch (e) {
      AppLogger.error('Error reading heart rate: $e');
      return null;
    }
  }
  
  /// Update heart rate from Watch (called from native code)
  void updateHeartRate(double heartRate) {
    AppLogger.info('Received heart rate update from Watch: $heartRate BPM');
    // Push to the heart rate stream so UI updates
    _heartRateController?.add(HeartRateSample(
      timestamp: DateTime.now(),
      bpm: heartRate.round(),
    ));
  }
}
