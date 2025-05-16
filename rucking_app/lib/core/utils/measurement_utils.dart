import 'package:rucking_app/core/config/app_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

/// MeasurementUtils centralizes all unit conversions and number
/// formatting rules so that every widget in the app shows data with
/// identical precision and wording.
class MeasurementUtils {
  /// Format a single elevation value (gain or loss) to 0 decimals with correct sign and unit.
  static String formatSingleElevation(double meters, {required bool metric}) {
    if (metric) {
      final prefix = meters >= 0 ? '+' : '-';
      return '$prefix${meters.abs().round()}m';
    } else {
      final feet = meters * _mToFt;
      final prefix = feet >= 0 ? '+' : '-';
      return '$prefix${feet.abs().round()}ft';
    }
  }

  // ===== Conversion factors =====
  static const double _kmToMi = 0.621371; // 1 km in miles
  static const double _mToFt = 3.28084;   // 1 metre in feet

  // Public helpers ---------------------------------------------------------

  /// Converts km → mi (returns same value if [metric] is true).
  static double distance(double km, {required bool metric}) =>
      metric ? km : km * _kmToMi;

  /// Converts seconds-per-km to seconds-per-unit depending on preference.
  static double paceSeconds(double secPerKm, {required bool metric}) =>
      metric ? secPerKm : secPerKm * 1 / _kmToMi;

  // ===== Formatting helpers (strings for UI) =============================

  /// Distance formatted to 2 decimal places + unit label (km/mi).
  static String formatDistance(double km, {required bool metric}) {
    final value = distance(km, metric: metric);
    return '${value.toStringAsFixed(2)} ${metric ? 'km' : 'mi'}';
  }

  /// Pace formatted as mm:ss per km/mi.
  static String formatPaceSeconds(double secPerKm, {required bool metric}) {
    if (secPerKm <= 0) return '--';
    final seconds = paceSeconds(secPerKm, metric: metric);
    final mins = (seconds / 60).floor();
    final secs = (seconds.round()) % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}/${metric ? 'km' : 'mi'}';
  }

  /// Pace formatted as minutes:seconds per unit (km/mi).
  static String formatPace(double paceSeconds, {required bool metric}) {
    // Return dashes for invalid pace values
    if (paceSeconds <= 0) return '--';
    
    // Convert from seconds/km to seconds/mile if not metric
    // For conversion: seconds/mile = seconds/km * 0.621371 (km to mile factor)
    final pace = metric ? paceSeconds : paceSeconds * 0.621371;
    
    // Cap extremely slow paces (>60min/km or mile) to avoid UI glitches
    if (pace > 3600) return '--';
    
    // Format pace as minutes:seconds
    final minutes = (pace / 60).floor();
    final seconds = (pace % 60).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds/${metric ? 'km' : 'mi'}';
  }

  /// Elevation gain/loss formatted to 0 decimals (+X m/ft).
  static String formatElevation(
    double gainMeters,
    double lossMeters, {
    required bool metric,
  }) {
    if (metric) {
      return '+${gainMeters.round()}m/-${lossMeters.round()}m';
    } else {
      final gainFt = gainMeters * _mToFt;
      final lossFt = lossMeters * _mToFt;
      return '+${gainFt.round()}ft/-${lossFt.round()}ft';
    }
  }

  /// Elevation gain/loss formatted to 0 decimals (+X m/ft) with compact representation.
  static String formatElevationCompact(double gainMeters, double lossMeters, {required bool metric}) {
    final gain = metric ? gainMeters : gainMeters * _mToFt;
    final loss = metric ? lossMeters : lossMeters * _mToFt;
    return '+${gain.round()}${metric ? 'm' : 'ft'}/-${loss.round()}${metric ? 'm' : 'ft'}';
  }

  /// Weight formatted with one decimal place + unit label.
  static String formatWeight(double kg, {required bool metric}) {
    if (metric) {
      return '${kg.toStringAsFixed(1)} kg'; // Show one decimal place for metric
    } else {
      final lbs = kg * AppConfig.kgToLbs;
      return '${lbs.toStringAsFixed(1)} lbs'; // Show one decimal place for imperial too
    }
  }
  
  /// Special weight formatter for ruck buddies weight chips to preserve exact values
  /// This helps avoid rounding issues when displaying weights that were originally
  /// entered as whole numbers (like 10 lbs, 20 lbs, etc.)
  static String formatWeightForChip(double kg, {required bool metric}) {
    if (kDebugMode) {
      debugPrint('[formatWeightForChip] Received kg: $kg, metric: $metric');
    }
    if (metric) {
      // For metric, just display the kg value with one decimal
      return '${kg.toStringAsFixed(1)} kg';
    } else {
      final double calculatedLbs = kg * AppConfig.kgToLbs;
      if (kDebugMode) {
        debugPrint('[formatWeightForChip] Calculated lbs: $calculatedLbs (from kg: $kg)');
      }

      // Common standard ruck weights in pounds
      const List<int> standardPoundWeights = [
        5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100
      ];

      // Check if calculatedLbs is extremely close to a standard pound weight
      for (final int standardLb in standardPoundWeights) {
        // Use a slightly larger tolerance for floating point comparisons directly in pounds
        if ((calculatedLbs - standardLb).abs() < 0.02) { 
          return '$standardLb lbs';
        }
      }

      // If not a standard weight, check if calculatedLbs is extremely close to any whole number
      final int roundedLbs = calculatedLbs.round();
      if ((calculatedLbs - roundedLbs).abs() < 0.02) { 
        return '$roundedLbs lbs';
      }
      
      // Otherwise, format to one decimal place as a fallback
      return '${calculatedLbs.toStringAsFixed(1)} lbs';
    }
  }
  
  /// Format a duration into a readable string (e.g., "1h 23m" or "45m")
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Calories formatted as integer string.
  static String formatCalories(int calories) => calories.toString();
  
  /// Format a UTC date to the local timezone and locale with specified format.
  /// Default format is 'MMMM d, yyyy' (e.g. "May 14, 2025")
  static String formatDate(DateTime utcDateTime, {String format = 'MMMM d, yyyy'}) {
    // Convert UTC time to local timezone
    final localDateTime = utcDateTime.toLocal();
    final dateFormat = DateFormat(format);
    return dateFormat.format(localDateTime);
  }
  
  /// Format a UTC time to the local timezone and locale with specified format.
  /// Default format is 'h:mm a' (e.g. "3:30 PM")
  static String formatTime(DateTime utcDateTime, {String format = 'h:mm a'}) {
    // Convert UTC time to local timezone
    final localDateTime = utcDateTime.toLocal();
    final timeFormat = DateFormat(format);
    return timeFormat.format(localDateTime);
  }
  
  /// Format a UTC dateTime to a readable representation in local timezone.
  /// This returns both date and time, separated by a space.
  /// Useful for showing the full date and time of an event.
  static String formatDateTime(DateTime utcDateTime, {
    String dateFormat = 'MMMM d, yyyy',
    String timeFormat = 'h:mm a',
  }) {
    return '${formatDate(utcDateTime, format: dateFormat)} at ${formatTime(utcDateTime, format: timeFormat)}';
  }

  /// Calculates total distance in kilometers from a list of LocationPoints.
  static double totalDistance(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 1; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total / 1000; // meters to km
  }

  /// Calculates total elevation gain in meters from a list of LocationPoints.
  static double totalElevationGain(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    double gain = 0.0;
    for (int i = 1; i < points.length; i++) {
      final diff = points[i].elevation - points[i - 1].elevation;
      if (diff > 0) gain += diff;
    }
    return gain;
  }

  /// Calculates total elevation loss in meters from a list of LocationPoints.
  static double totalElevationLoss(List<LocationPoint> points) {
    if (points.length < 2) return 0.0;
    double loss = 0.0;
    for (int i = 1; i < points.length; i++) {
      final diff = points[i].elevation - points[i - 1].elevation;
      if (diff < 0) loss -= diff;
    }
    return loss;
  }
}
