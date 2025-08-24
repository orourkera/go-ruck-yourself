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
      AppLogger.info('[HealthService] polled HR → ${hr?.toString() ?? 'null'}');
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
    if (!Platform.isIOS) {
      AppLogger.warning('Health integration only available on iOS');
      return false;
    }
    
    try {
      AppLogger.info('Starting health authorization request...');
      
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
      
      // Ensure we're showing the system dialog by forcing a clean request
      // This is important for iOS where sometimes the dialog doesn't appear
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay to ensure UI is ready
      
      AppLogger.info('Calling health package requestAuthorization with ${types.length} types');
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
    // Only available on iOS for Apple Health integration
    if (!Platform.isIOS) return false;
    
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

      // --- Write full Workout sample (iOS only) ---
      if (Platform.isIOS) {
        try {
          // If the health package provides writeWorkoutData (>=5.0.0)
          workoutSuccess = await _health.writeWorkoutData(
            activityType: HealthWorkoutActivityType.HIKING,
            start: startDate,
            end: endDate,
            totalEnergyBurned: caloriesBurned,
            totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
            totalDistance: distanceMeters,
            totalDistanceUnit: HealthDataUnit.METER,
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

  /// Local preference for enabling live step tracking in-app (independent of watch)
  Future<void> setLiveStepTrackingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('live_step_tracking', enabled);
  }

  Future<bool> isLiveStepTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('live_step_tracking') ?? false;
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
      // Get heart rate data from the last 30 minutes (some watches batch-sync)
      final now = DateTime.now();
      final window = const Duration(minutes: 30);
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
        AppLogger.info('No heart rate data available in the last 30 minutes');
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

  /// Read total walking/running distance (meters) between start and end
  Future<double> getDistanceMetersBetween(DateTime start, DateTime end) async {
    if (!Platform.isIOS) {
      return 0.0;
    }
    try {
      // Ensure authorization
      if (!_isAuthorized) {
        final ok = await requestAuthorization();
        if (!ok) return 0.0;
      }
      final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [HealthDataType.DISTANCE_WALKING_RUNNING],
      );
      double totalMeters = 0.0;
      for (final p in points) {
        final dynamic raw = p.value;
        if (raw is NumericHealthValue) {
          final v = raw.numericValue?.toDouble() ?? 0.0;
          totalMeters += v;
        } else if (raw is num) {
          totalMeters += raw.toDouble();
        } else {
          final parsed = double.tryParse(raw.toString());
          if (parsed != null) totalMeters += parsed;
        }
      }
      return totalMeters;
    } catch (e) {
      AppLogger.error('Error reading distance between $start and $end: $e');
      return 0.0;
    }
  }
  
  /// Read total steps between start and end
  Future<int> getStepsBetween(DateTime start, DateTime end) async {
    AppLogger.info('[STEPS DEBUG] getStepsBetween called: $start to $end');
    
    if (!Platform.isIOS && !Platform.isAndroid) {
      AppLogger.warning('[STEPS DEBUG] Not iOS/Android platform, returning 0');
      return 0;
    }
    
    try {
      AppLogger.info('[STEPS DEBUG] Authorization status: $_isAuthorized');
      
      if (!_isAuthorized) {
        AppLogger.info('[STEPS DEBUG] Not authorized, requesting authorization...');
        final ok = await requestAuthorization();
        AppLogger.info('[STEPS DEBUG] Authorization request result: $ok');
        if (!ok) {
          AppLogger.error('[STEPS DEBUG] Authorization failed, returning 0');
          return 0;
        }
      }
      
      AppLogger.info('[STEPS DEBUG] Calling health.getHealthDataFromTypes...');
      final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [HealthDataType.STEPS],
      );
      
      AppLogger.info('[STEPS DEBUG] Retrieved ${points.length} health data points');
      
      int total = 0;
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final dynamic raw = p.value;
        AppLogger.debug('[STEPS DEBUG] Point $i: ${p.dateFrom} to ${p.dateTo}, value type: ${raw.runtimeType}, raw: $raw');
        
        if (raw is NumericHealthValue) {
          final value = (raw.numericValue ?? 0).toInt();
          total += value;
          AppLogger.debug('[STEPS DEBUG] NumericHealthValue: $value, total now: $total');
        } else if (raw is num) {
          final value = raw.toInt();
          total += value;
          AppLogger.debug('[STEPS DEBUG] num value: $value, total now: $total');
        } else {
          final parsed = int.tryParse(raw.toString());
          if (parsed != null) {
            total += parsed;
            AppLogger.debug('[STEPS DEBUG] Parsed value: $parsed, total now: $total');
          } else {
            AppLogger.warning('[STEPS DEBUG] Could not parse value: $raw');
          }
        }
      }
      
      AppLogger.info('[STEPS DEBUG] Final total steps: $total');
      return total;
    } catch (e) {
      AppLogger.error('[STEPS DEBUG] Exception in getStepsBetween: $e');
      AppLogger.error('Error reading steps between $start and $end: $e');
      return 0;
    }
  }
  
  // Live steps polling
  StreamController<int>? _stepsController;
  Timer? _stepsTimer;
  
  Stream<int> startLiveSteps(DateTime start) {
    _stepsController?.close();
    _stepsController = StreamController<int>.broadcast();
    _stepsTimer?.cancel();
    _stepsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final total = await getStepsBetween(start, DateTime.now());
      _stepsController?.add(total);
    });
    return _stepsController!.stream;
  }
  
  void stopLiveSteps() {
    _stepsTimer?.cancel();
    _stepsTimer = null;
    _stepsController?.close();
    _stepsController = null;
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

  // Add public getter so callers can check auth status without breaking encapsulation
  bool get isAuthorized => _isAuthorized;
}
