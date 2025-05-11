import 'package:rucking_app/core/config/app_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rucking_app/core/models/location_point.dart';

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

  /// Weight formatted to the nearest whole number + unit label.
  static String formatWeight(double kg, {required bool metric}) {
    if (metric) {
      return '${kg.toStringAsFixed(1)} kg'; // Show one decimal place for metric
    } else {
      final lbs = kg * AppConfig.kgToLbs;
      return '${lbs.round()} lbs'; // Round to whole number for standard
    }
  }

  /// Calories formatted as integer string.
  static String formatCalories(int calories) => calories.toString();

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
