import 'dart:math';
import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/location_point.dart';

/// Provides validation logic for ruck sessions
class LocationValidationService {
  // Thresholds
  static const double minInitialDistanceMeters = 10.0; // 10 meters for faster stats display
  static const double maxSpeedKmh = 25.0; // 25 km/h max speed (walking/light jogging)
  static const Duration maxSpeedDuration = Duration(minutes: 1); // 1 minute max over speed
  static const double minMovingSpeedKmh = 0.5; // 0.5 km/h min speed to be considered moving
  static const Duration idleDuration = Duration(minutes: 1); // 1 minute without movement to auto-pause
  static const Duration longIdleDuration = Duration(minutes: 2); // 2 minutes idle to suggest ending session
  static const double maxPositionJumpMeters = 50.0; // 50 meters max jump in position
  static const Duration maxPositionJumpDuration = Duration(seconds: 5); // 5 seconds between location points
  static const double minGpsAccuracyMeters = 20.0; // 20 meters minimum GPS accuracy
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
      // Check for too-fast movement
      if (speedKmh > maxSpeedKmh) {
        if (_overSpeedStartTime == null) {
          _overSpeedStartTime = point.timestamp;
        } else if (point.timestamp.difference(_overSpeedStartTime!) > maxSpeedDuration) {
          _validationErrorCount++;
          results['isValid'] = false;
          results['message'] = 'Moving too fast (${speedKmh.toStringAsFixed(1)} km/h). Rucking is walking speed.';
          return results;
        }
      } else {
        _overSpeedStartTime = null;
      }

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
    {double minChangeMeters = 1.0}
  ) {
    final elevationDifference = newPoint.elevation - previousPoint.elevation;
    double gain = 0.0;
    double loss = 0.0;
    if (elevationDifference > minChangeMeters) {
      gain = elevationDifference;
    } else if (elevationDifference < -minChangeMeters) {
      loss = elevationDifference.abs();
    }
    return {'gain': gain, 'loss': loss};
  }

  /// Returns the currently accumulated distance that hasn't yet reached the threshold
  double getAccumulatedDistanceMeters() {
    return _cumulativeDistanceMeters;
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
