import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/error_handler.dart';
import 'dart:async';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:get_it/get_it.dart';

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
  double? _latestHeartRate; // Cached latest HR for synchronous access

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
        // Cache latest heart rate for synchronous fallback consumers
        _latestHeartRate = hr.toDouble();
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

  /// Latest known heart rate value (BPM) from polling or watch updates
  double? get latestHeartRate => _latestHeartRate;

  // Set the current user ID to make settings user-specific
  void setUserId(String userId) {
    _userId = userId;
  }
  
  /// Request authorization to access and write health data
  Future<bool> requestAuthorization() async {
    try {
      AppLogger.info('Starting health authorization request...');
      
      // Check if HealthKit is available first
      if (Platform.isIOS) {
        try {
          final isAvailable = await Health().hasPermissions([HealthDataType.STEPS]);
          AppLogger.info('HealthKit availability check result: $isAvailable');
        } catch (e) {
          AppLogger.error('HealthKit availability check failed: $e');
          return false;
        }
      }
      
      // Use Health package types (cross‑platform). WORKOUT is iOS‑only.
      final types = <HealthDataType>[
        HealthDataType.STEPS,
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
        if (Platform.isIOS) HealthDataType.WORKOUT,
      ];
      
      // READ for steps and HR (HR read-only), READ_WRITE for distance/energy (iOS write; Android may ignore writes)
      final permissions = <HealthDataAccess>[
        HealthDataAccess.READ,             // Steps
        HealthDataAccess.READ_WRITE,       // Distance
        HealthDataAccess.READ_WRITE,       // Active Energy Burned
        HealthDataAccess.READ,             // Heart Rate
        if (Platform.isIOS) HealthDataAccess.READ_WRITE, // Workout
      ];
      
      // Small delay to ensure any native UI is ready
      await Future.delayed(const Duration(milliseconds: 500));
      
      AppLogger.info('Calling health.requestAuthorization (types=${types.length})');
      final authorized = await _health.requestAuthorization(types, permissions: permissions);
      AppLogger.info('Health authorization result: $authorized');
      
      // Double-check permissions after authorization using the same types/permissions set
      if (authorized) {
        try {
          final permsOk = await _health.hasPermissions(types, permissions: permissions);
          AppLogger.info('Post-authorization hasPermissions(types=${types.length}) -> $permsOk');
          // Some platform versions may return null; treat null as true if the system reported authorized
          _isAuthorized = permsOk ?? true;
        } catch (e) {
          AppLogger.warning('Post-authorization permission verification threw: $e');
          // Assume authorized if the system call succeeded
          _isAuthorized = true;
        }
      } else {
        _isAuthorized = false;
      }
      
      if (_isAuthorized) {
        await setHealthIntegrationEnabled(true);
        AppLogger.info('Health integration enabled successfully');
      } else {
        AppLogger.warning('Health authorization failed or step permission denied');
      }
      
      return _isAuthorized;
    } catch (e) {
      AppLogger.error('Failed to request health authorization: $e');
      _isAuthorized = false;
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
    return prefs.getBool('live_step_tracking') ?? true; // Default to true - steps enabled by default
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

  /// Read current heart rate from health store (iOS: HealthKit, Android: Health Connect/Google Fit via health plugin)
  Future<double?> getHeartRate() async {
    try {
      // Ensure authorization
      if (!_isAuthorized) {
        final ok = await requestAuthorization();
        if (!ok) return null;
      }
      
      // Fetch heart rate from the last 30 minutes
      final now = DateTime.now();
      final window = const Duration(minutes: 30);
      final startTime = now.subtract(window);
      AppLogger.info('Fetching heart rate from $startTime to $now');
      
      final List<HealthDataPoint> heartRateData = await _health.getHealthDataFromTypes(
        startTime: startTime,
        endTime: now,
        types: const [HealthDataType.HEART_RATE],
      );
      
      AppLogger.info('Fetched heart rate data points: ${heartRateData.length}');
      if (heartRateData.isEmpty) {
        AppLogger.info('No heart rate data available in the last 30 minutes');
        return null;
      }
      
      heartRateData.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
      final mostRecent = heartRateData.first;
      AppLogger.info('Most recent heart rate raw value: ${mostRecent.value} at ${mostRecent.dateFrom}');
      
      final dynamic rawValue = mostRecent.value;
      double? heartRateValue;
      if (rawValue is NumericHealthValue) {
        heartRateValue = rawValue.numericValue?.toDouble();
      } else if (rawValue is num) {
        heartRateValue = rawValue.toDouble();
      } else {
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
    print('[STEPS DEBUG] ===== getStepsBetween CALLED =====');
    print('[STEPS DEBUG] Start: $start');
    print('[STEPS DEBUG] End: $end');
    print('[STEPS DEBUG] Duration: ${end.difference(start).inSeconds} seconds');
    
    if (!Platform.isIOS && !Platform.isAndroid) {
      print('[STEPS DEBUG] Not iOS/Android platform, returning 0');
      return 0;
    }
    
    try {
    print('[STEPS DEBUG] Current authorization status: $_isAuthorized');
    
    // If not authorized, try to get authorization first
    if (!_isAuthorized) {
      AppLogger.info('[STEPS DEBUG] Not authorized, requesting authorization...');
      final authorized = await requestAuthorization();
      AppLogger.info('[STEPS DEBUG] Authorization request result: $authorized');
      if (!authorized) {
        AppLogger.warning('[STEPS DEBUG] Authorization failed, returning 0 steps');
        return 0;
      }
    }
    
    // Always check authorization status fresh (don't rely on cached _isAuthorized)
    print('[STEPS DEBUG] Checking HealthKit permissions for STEPS...');
    final authStatuses = await _health.hasPermissions(
      [HealthDataType.STEPS],
      permissions: [HealthDataAccess.READ],
    );
    print('[STEPS DEBUG] Permission check result: $authStatuses');
    
    // On iOS, some plugin versions return null here even when authorized. Treat null as authorized if
    // we've already marked the session as authorized to avoid unnecessary re-prompts.
    bool hasStepPermission;
    if (authStatuses == null) {
      hasStepPermission = Platform.isIOS ? _isAuthorized : false;
      print('[STEPS DEBUG] hasPermissions returned null; using iOS authorized status: $hasStepPermission');
    } else {
      hasStepPermission = authStatuses;
      print('[STEPS DEBUG] Step permission granted: $hasStepPermission');
    }
    // Extra diagnostics: dump broader permission status snapshot on iOS
    if (Platform.isIOS) {
      try {
        final snapshot = await getPermissionStatus();
        AppLogger.info('[STEPS DEBUG] iOS permission snapshot: $snapshot');
      } catch (_) {}
    }
    
    if (hasStepPermission == false) {
      AppLogger.info('[STEPS DEBUG] No step permission, requesting authorization...');
      final ok = await requestAuthorization();
      AppLogger.info('[STEPS DEBUG] Authorization request result: $ok');
      if (!ok) {
        AppLogger.error('[STEPS DEBUG] Authorization failed, returning 0');
        return 0;
      }
    }
      
      
      // Use a more robust approach - try multiple methods
      if (Platform.isIOS) {
        // Method 1: Try getTotalStepsInInterval (iOS specific)
        try {
          AppLogger.info('[STEPS DEBUG] Method 1: Calling health.getTotalStepsInInterval...');
          AppLogger.info('[STEPS DEBUG] Time window: $start to $end (duration: ${end.difference(start).inMinutes} minutes)');
          final totalSteps = await _health.getTotalStepsInInterval(start, end);
          AppLogger.info('[STEPS DEBUG] getTotalStepsInInterval returned: $totalSteps (type: ${totalSteps.runtimeType})');
          if (totalSteps != null && totalSteps > 0) {
            AppLogger.info('[STEPS DEBUG] getTotalStepsInInterval success: $totalSteps');
            return totalSteps;
          } else {
            AppLogger.warning('[STEPS DEBUG] getTotalStepsInInterval returned null or 0: $totalSteps');
          }
        } catch (e) {
          AppLogger.error('[STEPS DEBUG] getTotalStepsInInterval failed: $e');
        }
        
        // Method 2: Try getHealthDataFromTypes with better error handling
        try {
          AppLogger.info('[STEPS DEBUG] Method 2: Calling health.getHealthDataFromTypes...');
          final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
            startTime: start,
            endTime: end,
            types: [HealthDataType.STEPS],
          );
          
          AppLogger.info('[STEPS DEBUG] Retrieved ${points.length} health data points');
          
          if (points.isEmpty) {
            AppLogger.warning('[STEPS DEBUG] No health data points returned for time window');
            AppLogger.info('[STEPS DEBUG] Checking broader time window to see if ANY step data exists...');
            
            // Check if there's ANY step data in the last 24 hours to diagnose the issue
            final yesterday = DateTime.now().subtract(const Duration(hours: 24));
            final now = DateTime.now();
            try {
              final testPoints = await _health.getHealthDataFromTypes(
                startTime: yesterday,
                endTime: now,
                types: [HealthDataType.STEPS],
              );
              AppLogger.info('[STEPS DEBUG] Last 24h test query returned ${testPoints.length} points');
              if (testPoints.isNotEmpty) {
                AppLogger.info('[STEPS DEBUG] Sample point: ${testPoints.first.dateFrom} to ${testPoints.first.dateTo}, value: ${testPoints.first.value}');
              }
            } catch (e) {
              AppLogger.error('[STEPS DEBUG] 24h test query failed: $e');
            }
            
            return 0;
          }
          
          int total = 0;
          for (int i = 0; i < points.length; i++) {
            final p = points[i];
            final dynamic raw = p.value;
            AppLogger.debug('[STEPS DEBUG] Point $i: ${p.dateFrom} to ${p.dateTo}, value: $raw (${raw.runtimeType})');
            
            if (raw is NumericHealthValue) {
              final value = (raw.numericValue ?? 0).toInt();
              total += value;
              AppLogger.debug('[STEPS DEBUG] NumericHealthValue: +$value, total: $total');
            } else if (raw is num) {
              final value = raw.toInt();
              total += value;
              AppLogger.debug('[STEPS DEBUG] num: +$value, total: $total');
            } else {
              final parsed = int.tryParse(raw.toString());
              if (parsed != null) {
                total += parsed;
                AppLogger.debug('[STEPS DEBUG] parsed: +$parsed, total: $total');
              } else {
                AppLogger.warning('[STEPS DEBUG] Could not parse: $raw');
              }
            }
          }
          
          AppLogger.info('[STEPS DEBUG] Final total from getHealthDataFromTypes: $total');
          return total;
          
        } catch (e) {
          AppLogger.error('[STEPS DEBUG] getHealthDataFromTypes failed: $e');
        }
      } else if (Platform.isAndroid) {
        // Android path: Use Health Connect via health plugin to sum steps
        try {
          AppLogger.info('[STEPS DEBUG][Android] Calling health.getHealthDataFromTypes for STEPS...');
          final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
            startTime: start,
            endTime: end,
            types: [HealthDataType.STEPS],
          );

          AppLogger.info('[STEPS DEBUG][Android] Retrieved ${points.length} points');
          if (points.isEmpty) {
            AppLogger.warning('[STEPS DEBUG][Android] No step data points in range');
            return 0;
          }

          int total = 0;
          for (int i = 0; i < points.length; i++) {
            final p = points[i];
            final dynamic raw = p.value;
            AppLogger.debug('[STEPS DEBUG][Android] Point $i: ${p.dateFrom}→${p.dateTo} value=$raw (${raw.runtimeType})');

            if (raw is NumericHealthValue) {
              final value = (raw.numericValue ?? 0).toInt();
              total += value;
            } else if (raw is num) {
              total += raw.toInt();
            } else {
              final parsed = int.tryParse(raw.toString());
              if (parsed != null) total += parsed;
            }
          }

          AppLogger.info('[STEPS DEBUG][Android] Total steps summed: $total');
          return total;
        } catch (e) {
          AppLogger.error('[STEPS DEBUG][Android] Error retrieving steps: $e');
        }
      }
      
      // If we get here, all methods failed
      AppLogger.warning('[STEPS DEBUG] All step retrieval methods failed, returning 0');
      return 0;
      
    } catch (e) {
      AppLogger.error('[STEPS DEBUG] Exception in getStepsBetween: $e');
      return 0;
    }
  }

  /// Estimate steps based on distance and user height when health data unavailable
  /// Formula: Step length ≈ Height × 0.415 (for walking/rucking)
  /// Steps = Distance ÷ Step length
  int estimateStepsFromDistance(double distanceKm, {double? userHeightCm}) {
    if (distanceKm <= 0) return 0;
    
    // Use provided height or fall back to average adult height (170cm)
    final heightCm = userHeightCm ?? 170.0;
    
    // Step length formula for walking/rucking (in meters)
    final stepLengthM = (heightCm / 100) * 0.415; // Convert cm to m, then apply factor
    
    // Convert distance to meters and calculate steps
    final distanceM = distanceKm * 1000;
    final estimatedSteps = (distanceM / stepLengthM).round();
    
    AppLogger.debug('[STEPS FALLBACK] Distance: ${distanceKm}km, height: ${heightCm}cm, stepLength: ${stepLengthM}m, estimatedSteps: $estimatedSteps');
    
    return estimatedSteps;
  }
  
  // Live steps polling
  StreamController<int>? _stepsController;
  Timer? _stepsTimer;
  StreamSubscription<int>? _pedometerSubscription;
  
  Stream<int> startLiveSteps(DateTime start) {
    print('[STEPS DEBUG] ========== STARTING LIVE STEP TRACKING ==========');
    print('[STEPS DEBUG] Start time: $start');
    print('[STEPS DEBUG] Current time: ${DateTime.now()}');
    
    // For iOS, use CMPedometer for real-time updates
    if (Platform.isIOS) {
      print('[STEPS DEBUG] iOS detected - using CMPedometer for real-time steps');
      return _startCMPedometerStream(start);
    }
    
    // For Android or if CMPedometer fails, check if we can get real-time steps from Apple Watch
    try {
      final watchService = GetIt.instance<WatchService>();
      print('[STEPS DEBUG] WatchService found - checking session status');
      print('[STEPS DEBUG] Watch session active: ${watchService.isSessionActive}');
      
      // Only use watch stream if session is actually active AND producing data
      if (watchService.isSessionActive) {
        final watchStream = watchService.stepsStream;
        print('[STEPS DEBUG] ✅ Setting up Apple Watch steps stream (session active)');
        
        // Create a stream controller to merge watch and HealthKit data
        final controller = StreamController<int>.broadcast();
        bool watchTimedOut = false;
        Timer? timeoutTimer;
        Timer? pollingTimer;
        
        // Set up timeout for watch data
        timeoutTimer = Timer(const Duration(seconds: 15), () {
          if (!watchTimedOut) {
            print('[STEPS DEBUG] ⚠️ TIMEOUT: No watch steps received in 15 seconds');
            print('[STEPS DEBUG] Starting HealthKit polling fallback');
            watchTimedOut = true;
            
            // Start polling HealthKit
            pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
              print('[STEPS DEBUG] ⏰ FALLBACK POLL TIMER FIRED');
              try {
                final now = DateTime.now();
                final sessionDuration = now.difference(start);
                
                if (sessionDuration.inSeconds < 5) {
                  print('[STEPS DEBUG] Session too new, skipping poll');
                  controller.add(0);
                  return;
                }
                
                print('[STEPS DEBUG] Polling HealthKit for steps...');
                final total = await getStepsBetween(start, now);
                print('[STEPS DEBUG] HealthKit returned: $total steps');
                
                if (!controller.isClosed) {
                  controller.add(total);
                }
              } catch (e) {
                print('[STEPS DEBUG] Error polling HealthKit: $e');
              }
            });
          }
        });
        
        // Listen to watch stream
        watchStream.listen((steps) {
          print('[STEPS DEBUG] 🎉 WATCH SENT STEPS: $steps');
          timeoutTimer?.cancel();
          pollingTimer?.cancel();
          watchTimedOut = false;
          if (!controller.isClosed) {
            controller.add(steps);
          }
        });
        
        // Clean up on cancel
        controller.onCancel = () {
          timeoutTimer?.cancel();
          pollingTimer?.cancel();
        };
        
        return controller.stream;
      } else {
        AppLogger.warning('[STEPS LIVE] ⚠️  Watch session not active, falling back to polling');
      }
    } catch (e) {
      AppLogger.warning('[STEPS LIVE] WatchService not available, falling back to HealthKit polling: $e');
    }
    
    // Fallback to HealthKit polling if watch service not available
    // Clean up existing resources properly
    stopLiveSteps();
    
    _stepsController = StreamController<int>.broadcast();
    
    // Add proper cleanup when stream is cancelled
    _stepsController!.onCancel = () {
      AppLogger.info('[STEPS LIVE] Stream cancelled, stopping timer');
      _stepsTimer?.cancel();
      _stepsTimer = null;
    };

    // Store session start time for calculating session-only steps
    final sessionStart = start;

    // Emit 0 immediately since HealthKit needs time to record step intervals
    (() async {
      final now = DateTime.now();
      final sessionDuration = now.difference(sessionStart);
      AppLogger.debug('[STEPS LIVE] Immediate poll - session duration: ${sessionDuration.inSeconds}s');
      
      if (sessionDuration.inSeconds < 10) {
        // Too early - HealthKit likely hasn't recorded any intervals yet
        AppLogger.info('[STEPS LIVE] Session too new (${sessionDuration.inSeconds}s), emitting 0 steps');
        if (_stepsController != null && !_stepsController!.isClosed) {
          _stepsController!.add(0);
        }
        return;
      }
      
      // Query for steps only during the session
      final total = await getStepsBetween(sessionStart, now);
      AppLogger.info('[STEPS LIVE] Immediate emit total steps: $total');
      if (_stepsController != null && !_stepsController!.isClosed) {
        _stepsController!.add(total);
      }
    })();

    _stepsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final now = DateTime.now();
      final sessionDuration = now.difference(sessionStart);
      print('[STEPS DEBUG] ⏰ POLLING TIMER FIRED - session duration: ${sessionDuration.inSeconds}s');
      
      // Reduce delay to 10 seconds for testing (was 1 minute)
      // HealthKit might not have data immediately but 10s should be enough for testing
      if (sessionDuration.inSeconds < 10) {
        print('[STEPS DEBUG] Session too new (${sessionDuration.inSeconds}s), waiting for HealthKit data...');
        if (_stepsController != null && !_stepsController!.isClosed) {
          _stepsController!.add(0);
        }
        return;
      }
      
      print('[STEPS DEBUG] Querying HealthKit for steps between $sessionStart and $now');
      final total = await getStepsBetween(sessionStart, now);
      print('[STEPS DEBUG] 📊 HEALTHKIT RETURNED: $total steps');
      if (_stepsController != null && !_stepsController!.isClosed) {
        print('[STEPS DEBUG] Emitting $total steps to stream');
        _stepsController!.add(total);
      } else {
        AppLogger.warning('[STEPS LIVE] Steps controller is null/closed; skipping emit');
      }
    });
    return _stepsController!.stream;
  }
  
  void stopLiveSteps() {
    AppLogger.info('[STEPS LIVE] stopLiveSteps invoked');
    _stepsTimer?.cancel();
    _stepsTimer = null;
    
    // Cancel pedometer subscription safely
    try {
      _pedometerSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('[STEPS LIVE] Pedometer subscription cancel (safe to ignore): $e');
    }
    _pedometerSubscription = null;
    
    try {
      _stepsController?.close();
    } catch (_) {}
    _stepsController = null;
  }
  
  /// Start CMPedometer stream for real-time iOS step counting
  Stream<int> _startCMPedometerStream(DateTime sessionStart) {
    print('[STEPS DEBUG] Setting up CMPedometer stream');
    
    // Clean up any existing resources
    stopLiveSteps();
    
    // Create new StreamController
    _stepsController = StreamController<int>.broadcast();
    
    // Tell iOS to start a new pedometer session
    const platform = MethodChannel('com.getrucky.gfy/watch_session');
    platform.invokeMethod('startPedometerSession').then((_) {
      print('[STEPS DEBUG] Pedometer session started on iOS');
    }).catchError((e) {
      print('[STEPS DEBUG] Error starting pedometer session: $e');
    });
    
    // Set up the event channel for receiving pedometer data
    const EventChannel pedometerChannel = EventChannel('com.getrucky.gfy/pedometerStream');
    
    // Store the subscription so we can cancel it properly
    _pedometerSubscription = pedometerChannel.receiveBroadcastStream().map<int>((dynamic event) {
      print('[STEPS DEBUG] 🎉 CMPedometer event received: $event');
      
      if (event is Map) {
        final steps = event['steps'] as int?;
        final distance = event['distance'] as double?;
        final timestamp = event['timestamp'] as double?;
        
        print('[STEPS DEBUG] 📊 CMPedometer - Steps: $steps, Distance: ${distance?.toStringAsFixed(1)}m');
        
        return steps ?? 0;
      }
      
      // Handle direct integer if iOS sends simplified format
      if (event is int) {
        print('[STEPS DEBUG] 📊 CMPedometer - Direct steps: $event');
        return event;
      }
      
      print('[STEPS DEBUG] Unexpected pedometer data format: ${event.runtimeType}');
      return 0;
    }).listen((int steps) {
      // Forward steps to our controller
      if (_stepsController != null && !_stepsController!.isClosed) {
        _stepsController!.add(steps);
      }
    }, onError: (error) {
      print('[STEPS DEBUG] ❌ CMPedometer stream error: $error');
      print('[STEPS DEBUG] Falling back to HealthKit polling');
      
      // Cancel the failed subscription
      try {
        _pedometerSubscription?.cancel();
      } catch (_) {}
      _pedometerSubscription = null;
      
      // Fall back to HealthKit polling
      _startHealthKitPollingFallbackInternal(sessionStart);
    });
    
    return _stepsController!.stream;
  }
  
  /// Internal method to start HealthKit polling when controller is already set up
  void _startHealthKitPollingFallbackInternal(DateTime sessionStart) {
    // Poll every 10 seconds
    _stepsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final now = DateTime.now();
      print('[STEPS DEBUG] ⏰ HealthKit fallback polling timer fired');
      
      final total = await getStepsBetween(sessionStart, now);
      print('[STEPS DEBUG] HealthKit returned: $total steps');
      
      if (_stepsController != null && !_stepsController!.isClosed) {
        _stepsController!.add(total);
      }
    });
  }
  
  /// Fallback HealthKit polling stream
  Stream<int> _startHealthKitPollingStream(DateTime sessionStart) {
    print('[STEPS DEBUG] Starting HealthKit polling fallback');
    
    // Clean up existing resources
    stopLiveSteps();
    
    _stepsController = StreamController<int>.broadcast();
    
    // Poll every 10 seconds
    _stepsTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final now = DateTime.now();
      print('[STEPS DEBUG] ⏰ HealthKit polling timer fired');
      
      final total = await getStepsBetween(sessionStart, now);
      print('[STEPS DEBUG] HealthKit returned: $total steps');
      
      if (_stepsController != null && !_stepsController!.isClosed) {
        _stepsController!.add(total);
      }
    });
    
    return _stepsController!.stream;
  }

  /// Helper method to start HealthKit polling with an existing sink
  void _startHealthKitPollingWithSink(DateTime sessionStart, EventSink<int> sink) {
    print('[STEPS DEBUG] 🔄 STARTING HEALTHKIT POLLING FALLBACK');
    print('[STEPS DEBUG] Will poll every 5 seconds for step updates');
    
    // Poll every 5 seconds for step updates
    _stepsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      print('[STEPS DEBUG] ⏰ HEALTHKIT POLL TIMER FIRED');
      try {
        final now = DateTime.now();
        final sessionDuration = now.difference(sessionStart);
        
        // Cancel early for very new sessions - reduced from 10 to 5 seconds
        if (sessionDuration.inSeconds < 5) {
          print('[STEPS DEBUG] [HEALTHKIT_FALLBACK] Session too new (${sessionDuration.inSeconds}s), waiting for HealthKit data...');
          sink.add(0);
          return;
        }
        
        // Try a narrower window first (last 10 minutes)
        final fallbackStart = now.subtract(const Duration(minutes: 10));
        final actualStart = sessionStart.isAfter(fallbackStart) ? sessionStart : fallbackStart;
        
        print('[STEPS DEBUG] Querying HealthKit from $actualStart to $now');
        final total = await getStepsBetween(actualStart, now);
        print('[STEPS DEBUG] [HEALTHKIT_FALLBACK] HealthKit returned: $total steps');
        
        // Try to add data - if sink is closed, this will throw
        try {
          sink.add(total);
          print('[STEPS DEBUG] [HEALTHKIT_FALLBACK] Successfully sent $total steps to stream');
        } catch (e) {
          print('[STEPS DEBUG] [HEALTHKIT_FALLBACK] Sink closed, stopping timer: $e');
          timer.cancel();
        }
      } catch (e) {
        print('[STEPS DEBUG] [HEALTHKIT_FALLBACK] Error during step polling: $e');
        // Stop timer if sink is closed or other critical error
        timer.cancel();
      }
    });
  }
  
  /// Update heart rate from Watch (called from native code)
  void updateHeartRate(double heartRate) {
    AppLogger.info('Received heart rate update from Watch: $heartRate BPM');
    // Cache as latest heart rate for synchronous access
    _latestHeartRate = heartRate;
    // Push to the heart rate stream so UI updates
    _heartRateController?.add(HeartRateSample(
      timestamp: DateTime.now(),
      bpm: heartRate.round(),
    ));
  }

  // Add public getter so callers can check auth status without breaking encapsulation
  bool get isAuthorized => _isAuthorized;
}

extension HealthServiceDebug on HealthService {
  /// Returns a map of key health permissions and whether they are granted.
  /// Values can be true, false, or null (unknown on some platforms/plugin versions).
  Future<Map<String, bool?>> getPermissionStatus() async {
    final types = <HealthDataType>[
      HealthDataType.HEART_RATE,
      HealthDataType.DISTANCE_WALKING_RUNNING,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.STEPS,
      if (Platform.isIOS) HealthDataType.WORKOUT,
    ];

    final permissions = <HealthDataAccess>[
      HealthDataAccess.READ,             // Heart rate read-only
      HealthDataAccess.READ_WRITE,       // Distance
      HealthDataAccess.READ_WRITE,       // Active energy
      HealthDataAccess.READ,             // Steps
      if (Platform.isIOS) HealthDataAccess.READ_WRITE, // Workout
    ];

    try {
      final dynamic raw = await _health.hasPermissions(types, permissions: permissions);
      final map = <String, bool?>{};

      // Normalize to a per-type list for easier handling
      List<bool?> perType;
      if (raw is List) {
        perType = raw.cast<bool?>();
      } else if (raw is bool?) {
        perType = List<bool?>.filled(types.length, raw);
      } else {
        perType = List<bool?>.filled(types.length, null);
      }

      for (int i = 0; i < types.length; i++) {
        final key = types[i].toString().split('.').last;
        map[key] = i < perType.length ? perType[i] : null;
      }

      AppLogger.info('[HEALTH PERMS] Status: $map');
      return map;
    } catch (e) {
      AppLogger.error('Failed to fetch health permission status: $e');
      return {
        'ERROR': false,
      };
    }
  }
}
