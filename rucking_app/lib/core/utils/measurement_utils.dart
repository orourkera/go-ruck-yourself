import 'package:rucking_app/core/config/app_config.dart';

/// MeasurementUtils centralizes all unit conversions and number
/// formatting rules so that every widget in the app shows data with
/// identical precision and wording.
class MeasurementUtils {
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
    if (paceSeconds <= 0) return '--';
    final pace = metric ? paceSeconds : paceSeconds * 1.60934;
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
}
