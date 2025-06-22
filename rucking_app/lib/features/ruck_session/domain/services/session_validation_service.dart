import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/error_messages.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Provides validation logic for ruck sessions
class SessionValidationService {
  // Thresholds
  static const double minSessionDistanceMeters = 100.0; // 100 meters
  static const Duration minSessionDuration = Duration(minutes: 2);
  static const double minInitialDistanceMeters = 50.0; // 50 meters for faster stats display
  static const double maxSpeedKmh = 10.0; // 10 km/h max speed (walking/light jogging)
  static const Duration maxSpeedDuration = Duration(minutes: 1); // 1 minute max over speed
  static const double minMovingSpeedKmh = 0.5; // 0.5 km/h min speed to be considered moving
  static const Duration idleDuration = Duration(minutes: 1); // 1 minute without movement to auto-pause
  static const Duration longIdleDuration = Duration(minutes: 2); // 2 minutes idle to suggest ending session
  static const double maxPositionJumpMeters = 20.0; // 20 meters max jump in position
  static const Duration maxPositionJumpDuration = Duration(seconds: 5); // 5 seconds between location points
  static const double minGpsAccuracyMeters = 20.0; // 20 meters minimum GPS accuracy (was 50.0)
  static const double minCaloriesPerHour = 300.0; // 300 calories minimum per hour
  static const double maxCaloriesPerHour = 800.0; // 800 calories maximum per hour
  static const Duration lowGpsWarningDelay = Duration(seconds: 30); // 30 seconds delay before showing GPS warning

  // State tracking
  double _cumulativeDistanceMeters = 0.0;
  bool _isInitialDistanceReached = false;
  DateTime? _overSpeedStartTime;
  DateTime? _idleStartTime;
  DateTime? _lowGpsStartTime; // Track when low GPS accuracy started
  int _validationErrorCount = 0;
  LocationPoint? _lastValidPoint;

  // Public state access
  bool get isInitialDistanceReached => _isInitialDistanceReached;
  int get validationErrorCount => _validationErrorCount;

  /// Reset all validation state
  void reset() {
    _cumulativeDistanceMeters = 0.0;
    _isInitialDistanceReached = false;
    _overSpeedStartTime = null;
    _idleStartTime = null;
    _lowGpsStartTime = null;
    _validationErrorCount = 0;
    _lastValidPoint = null;
  }

  /// Check if a new location point is valid and should be added to route
  /// Returns a map with validation results
  Map<String, dynamic> validateLocationPoint(
    LocationPoint point, 
    LocationPoint? previousPoint,
    {double? distanceMeters}
  ) {
    final results = <String, dynamic>{
      'isValid': true,
      'shouldPause': false,
      'message': null,
    };

    // Skip validation for the first point (no previous point)
    if (previousPoint == null) {
      _lastValidPoint = point;
      return results;
    }

    // Calculate distance if not provided
    final distance = distanceMeters ?? _calculateDistanceBetweenPoints(point, previousPoint);
    final duration = point.timestamp.difference(previousPoint.timestamp);

    // 1. GPS accuracy check
    if (point.accuracy > minGpsAccuracyMeters) {
      if (_lowGpsStartTime == null) {
        _lowGpsStartTime = point.timestamp;
      } else if (point.timestamp.difference(_lowGpsStartTime!) > lowGpsWarningDelay) {
        _validationErrorCount++;
        results['isValid'] = false;
        results['message'] = 'Low GPS accuracy (${point.accuracy.toStringAsFixed(1)}m). Try moving to open space.';
        return results;
      }
      // Don't return yet if we're still in the buffer period - continue processing the point
    } else {
      _lowGpsStartTime = null;
    }

    // 2. Position jump check
    if (distance > maxPositionJumpMeters && duration < maxPositionJumpDuration) {
      _validationErrorCount++;
      results['isValid'] = false;
      results['message'] = 'Unrealistic movement detected. Position jumped too far.';
      return results;
    }

    // 3. Speed/idle check (robust)
    double? speedKmh;
    if (point.speed != null) {
      speedKmh = point.speed! * 3.6; // Convert m/s to km/h
    } else if (duration.inSeconds > 0) {
      // Fallback: calculate speed from distance/time
      speedKmh = (distance / duration.inSeconds) * 3.6;
    }

    if (speedKmh != null) {
      // Check for too-fast movement - DISABLED FOR NOW
      /*
      if (speedKmh > maxSpeedKmh) {
        if (_overSpeedStartTime == null) {
          _overSpeedStartTime = point.timestamp;
        } else if (point.timestamp.difference(_overSpeedStartTime!) > maxSpeedDuration) {
          _validationErrorCount++;
          results['shouldPause'] = true; // Auto-pause on unrealistic speed
          results['message'] = 'Moving too fast (${speedKmh.toStringAsFixed(1)} km/h). Rucking is walking speed.';
        }
      } else {
        _overSpeedStartTime = null;
      }
      */

      // Check for not moving (auto-pause) - DISABLED
      /*
      if (speedKmh < minMovingSpeedKmh) {
        if (_idleStartTime == null) {
          _idleStartTime = point.timestamp;
        } else {
          final idleTime = point.timestamp.difference(_idleStartTime!);
          if (idleTime > idleDuration) {
            results['shouldPause'] = true;
            results['message'] = 'Auto-paused: No movement detected for 1+ minute';
          }
        }
      } else {
        _idleStartTime = null;
      }
      */

      // Check for not moving (suggest end session)
      if (speedKmh < minMovingSpeedKmh) {
        if (_idleStartTime == null) {
          _idleStartTime = point.timestamp;
        } else {
          final idleTime = point.timestamp.difference(_idleStartTime!);
          if (idleTime > longIdleDuration) {
            results['shouldEnd'] = true;
            results['message'] = 'Idle for 2+ minutes. Consider ending session?';
          }
        }
      } else {
        _idleStartTime = null;
      }
    }

    // Update initial distance tracking
    if (!_isInitialDistanceReached) {
      _cumulativeDistanceMeters += distance;
      if (_cumulativeDistanceMeters >= minInitialDistanceMeters) {
        _isInitialDistanceReached = true;
        results['initialDistanceReached'] = true;
      }
    }

    // If all validations passed, update last valid point
    if (results['isValid']) {
      _lastValidPoint = point;
    }

    return results;
  }

  /// Validates and returns elevation gain/loss for a segment
  /// Returns a map: { 'gain': double, 'loss': double }
  Map<String, double> validateElevationChange(
    LocationPoint previousPoint,
    LocationPoint newPoint,
    {double? minChangeMeters}
  ) {
    // Platform-specific elevation thresholds
    final double threshold = minChangeMeters ?? _getPlatformElevationThreshold();
    
    final elevationDifference = newPoint.elevation - previousPoint.elevation;
    double gain = 0.0;
    double loss = 0.0;
    
    // Apply platform-specific elevation processing
    final processedElevationDiff = _processElevationDifference(
      elevationDifference, 
      previousPoint, 
      newPoint
    );
    
    AppLogger.debug('Elevation validation - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, RawDiff: ${elevationDifference}m, ProcessedDiff: ${processedElevationDiff}m, Threshold: ${threshold}m, PrevElev: ${previousPoint.elevation}m, NewElev: ${newPoint.elevation}m, Accuracy: ${newPoint.accuracy}m');
    
    if (processedElevationDiff > threshold) {
      gain = processedElevationDiff;
    } else if (processedElevationDiff < -threshold) {
      loss = processedElevationDiff.abs();
    }
    
    return {'gain': gain, 'loss': loss};
  }
  
  /// Get platform-specific elevation change threshold
  double _getPlatformElevationThreshold() {
    if (Platform.isIOS) {
      // iOS uses barometric + GPS - more conservative but accurate
      // Lower threshold to catch smaller but legitimate changes
      return 0.5; // 0.5 meters = ~1.6 feet
    } else {
      // Android GPS elevation can be noisier
      // Slightly higher threshold to filter noise
      return 1.0; // 1 meter = ~3.3 feet  
    }
  }
  
  /// Process elevation difference with platform-specific logic
  double _processElevationDifference(
    double rawDifference,
    LocationPoint previousPoint,
    LocationPoint currentPoint,
  ) {
    if (Platform.isIOS) {
      return _processIOSElevation(rawDifference, previousPoint, currentPoint);
    } else {
      return _processAndroidElevation(rawDifference, previousPoint, currentPoint);
    }
  }
  
  /// iOS-specific elevation processing
  double _processIOSElevation(
    double rawDifference,
    LocationPoint previousPoint,
    LocationPoint currentPoint,
  ) {
    // iOS barometric sensor is more accurate but conservative
    // Check for poor GPS accuracy that might affect elevation
    if (currentPoint.accuracy > 20) {
      // Poor horizontal accuracy usually means poor altitude accuracy too
      AppLogger.debug('iOS elevation: Poor GPS accuracy (${currentPoint.accuracy}m), applying 0.7x smoothing');
      // Apply more aggressive smoothing for poor accuracy readings
      return rawDifference * 0.7; // Reduce impact of potentially inaccurate reading
    }
    
    // For good accuracy, trust iOS altitude more
    // But enhance small changes that iOS might under-report
    if (rawDifference.abs() < 2.0 && rawDifference.abs() > 0.3) {
      // Enhance small but significant changes (iOS tends to under-report)
      AppLogger.debug('iOS elevation: Enhancing small change from ${rawDifference}m to ${rawDifference * 1.3}m');
      return rawDifference * 1.3;
    }
    
    return rawDifference;
  }
  
  /// Android-specific elevation processing  
  double _processAndroidElevation(
    double rawDifference,
    LocationPoint previousPoint,
    LocationPoint currentPoint,
  ) {
    // Android GPS elevation can be noisier but more responsive
    // Apply noise filtering for very poor accuracy
    if (currentPoint.accuracy > 30) {
      AppLogger.debug('Android elevation: Very poor GPS accuracy (${currentPoint.accuracy}m), applying 0.5x noise filtering');
      // Strong noise filtering for poor readings
      return rawDifference * 0.5;
    } else if (currentPoint.accuracy > 15) {
      // Moderate filtering for moderate accuracy
      return rawDifference * 0.8;
    }
    
    // For good accuracy, trust Android GPS elevation
    return rawDifference;
  }

  /// Check if the session is valid before saving it
  Map<String, dynamic> validateSessionForSave({
    required double distanceMeters,
    required Duration duration,
    required double caloriesBurned,
  }) {
    final results = <String, dynamic>{
      'isValid': true,
      'message': null,
    };

    // NOTE: Minimum session duration and minimum distance checks have been DISABLED.
    // Users can now save workouts with any duration or distance, including zero.

    // 3. Calories value can be zero; just warn if negative
    if (caloriesBurned < 0.0) {
      //debugPrint('WARNING: Negative calorie value: $caloriesBurned');
    }

    // 4. Calories sanity check (warn, but don't block)
    final durationHours = duration.inSeconds / 3600;
    if (durationHours > 0) {
      final caloriesPerHour = caloriesBurned / durationHours;
      if (caloriesPerHour < minCaloriesPerHour || caloriesPerHour > maxCaloriesPerHour) {
        //debugPrint('WARNING: Unusual calorie burn rate: $caloriesPerHour calories/hour');
        // We don't invalidate the session, just log a warning
      }
    }

    return results;
  }

  /// Returns the currently accumulated distance that hasn't yet reached the threshold
  double getAccumulatedDistanceMeters() {
    return _cumulativeDistanceMeters;
  }

  /// Get a suitable pace value (smoothed if needed)
  double getSmoothedPace(double currentPace, List<double> recentPaces) {
    // No smoothing needed if we don't have enough data
    if (recentPaces.length < 3) return currentPace;
    
    // Calculate rolling average of the last several pace values
    // excluding any outliers (very high or very low values)
    final validPaces = [...recentPaces]..sort();
    // Remove potential outliers (first and last value)
    if (validPaces.length > 4) {
      validPaces.removeAt(0);
      validPaces.removeLast();
    }
    
    // Calculate average
    double sum = validPaces.fold(0, (a, b) => a + b);
    return sum / validPaces.length;
  }

  /// Calculate distance between two points in meters
  double _calculateDistanceBetweenPoints(LocationPoint point1, LocationPoint point2) {
    // Use Haversine formula for accurate earth distances
    const double earthRadius = 6371000; // meters
    final double lat1 = point1.latitude * (pi / 180);
    final double lat2 = point2.latitude * (pi / 180);
    final double lon1 = point1.longitude * (pi / 180);
    final double lon2 = point2.longitude * (pi / 180);
    
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
}
