import 'package:rucking_app/core/models/ruck_session.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';

/// Encapsulates all calculations for a single session as well as
/// aggregations over a list of sessions. All numeric inputs are in SI
/// units (km, kg, metres, seconds) as stored in the backend.
class SessionMetricsService {
  // ----------------- per-session helpers ------------------------------
  static String distanceDisplay(RuckSession s, bool metric) =>
      MeasurementUtils.formatDistance(s.totalDistanceKm ?? 0.0, metric: metric);

  static String paceDisplay(RuckSession s, bool metric) {
    final secPerKm = s.avgPaceSecPerKm ?? 0.0;
    return MeasurementUtils.formatPace(secPerKm, metric: metric);
  }

  static String elevationDisplay(RuckSession s, bool metric) =>
      MeasurementUtils.formatElevation(
        s.elevationGain ?? 0.0,
        s.elevationLoss ?? 0.0,
        metric: metric,
      );

  static String weightDisplay(RuckSession s, bool metric) =>
      MeasurementUtils.formatWeight(s.ruckWeightKg, metric: metric);

  static String caloriesDisplay(RuckSession s) =>
      MeasurementUtils.formatCalories(s.caloriesBurned ?? 0);

  // ----------------- aggregation helpers ------------------------------
  static Map<String, dynamic> aggregate(List<RuckSession> list) {
    double totalDistanceKm = 0;
    int totalDurationSec = 0;
    int totalCalories = 0;
    double totalElevationGain = 0;
    double totalElevationLoss = 0;

    for (final s in list) {
      totalDistanceKm += s.totalDistanceKm ?? 0;
      totalDurationSec += s.totalDurationSec ?? 0;
      totalCalories += s.caloriesBurned ?? 0;
      totalElevationGain += s.elevationGain ?? 0;
      totalElevationLoss += s.elevationLoss ?? 0;
    }

    final avgPaceSecPerKm =
        totalDistanceKm > 0 ? totalDurationSec / totalDistanceKm : 0.0;

    return {
      'total_distance_km': totalDistanceKm,
      'total_duration_sec': totalDurationSec,
      'total_calories': totalCalories,
      'total_elevation_gain_m': totalElevationGain,
      'total_elevation_loss_m': totalElevationLoss,
      'avg_pace_sec_per_km': avgPaceSecPerKm,
    };
  }
}
