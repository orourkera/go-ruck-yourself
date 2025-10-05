import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

/// Demo data for browse mode users
class DemoData {
  /// Generate realistic demo ruck sessions for browse mode preview
  static List<RuckSession> getDemoSessions() {
    final now = DateTime.now();

    final demoStart1 = now.subtract(const Duration(days: 1, hours: 8));
    final demoStart2 = now.subtract(const Duration(days: 3, hours: 12));
    final demoStart3 = now.subtract(const Duration(days: 5, hours: 9));
    final demoStart4 = now.subtract(const Duration(days: 7, hours: 18));
    final demoStart5 = now.subtract(const Duration(days: 10, hours: 10));

    return [
      RuckSession(
        id: 'demo-1',
        startTime: demoStart1,
        endTime: demoStart1.add(const Duration(hours: 2, minutes: 15)),
        distance: 8.5,
        duration: const Duration(hours: 2, minutes: 15),
        caloriesBurned: 650,
        elevationGain: 120,
        elevationLoss: 115,
        ruckWeightKg: 15.0,
        averagePace: 952, // seconds per km
        status: RuckStatus.completed,
        notes: 'Morning ruck through the park',
        rating: 5,
      ),
      RuckSession(
        id: 'demo-2',
        startTime: demoStart2,
        endTime: demoStart2.add(const Duration(hours: 1, minutes: 20)),
        distance: 5.2,
        duration: const Duration(hours: 1, minutes: 20),
        caloriesBurned: 420,
        elevationGain: 45,
        elevationLoss: 42,
        ruckWeightKg: 15.0,
        averagePace: 923,
        status: RuckStatus.completed,
        notes: 'Quick lunch break ruck',
        rating: 4,
      ),
      RuckSession(
        id: 'demo-3',
        startTime: demoStart3,
        endTime: demoStart3.add(const Duration(hours: 3, minutes: 5)),
        distance: 12.0,
        duration: const Duration(hours: 3, minutes: 5),
        caloriesBurned: 890,
        elevationGain: 200,
        elevationLoss: 195,
        ruckWeightKg: 20.0,
        averagePace: 929,
        status: RuckStatus.completed,
        notes: 'Epic weekend ruck!',
        rating: 5,
      ),
      RuckSession(
        id: 'demo-4',
        startTime: demoStart4,
        endTime: demoStart4.add(const Duration(hours: 1, minutes: 45)),
        distance: 6.8,
        duration: const Duration(hours: 1, minutes: 45),
        caloriesBurned: 510,
        elevationGain: 85,
        elevationLoss: 80,
        ruckWeightKg: 15.0,
        averagePace: 926,
        status: RuckStatus.completed,
        notes: 'Evening neighborhood loop',
        rating: 4,
      ),
      RuckSession(
        id: 'demo-5',
        startTime: demoStart5,
        endTime: demoStart5.add(const Duration(hours: 2, minutes: 30)),
        distance: 10.0,
        duration: const Duration(hours: 2, minutes: 30),
        caloriesBurned: 750,
        elevationGain: 150,
        elevationLoss: 145,
        ruckWeightKg: 18.0,
        averagePace: 900,
        status: RuckStatus.completed,
        notes: 'Training for upcoming event',
        rating: 5,
      ),
    ];
  }

  /// Get demo monthly stats
  static Map<String, dynamic> getDemoMonthlyStats() {
    return {
      'total_distance_km': 42.5,
      'total_rucks': 5,
      'total_calories': 3220,
      'total_elevation_gain_m': 600,
      'avg_pace_s_per_km': 900, // 15 min/km
      'total_duration_seconds': 38100, // ~10.5 hours
    };
  }

  /// Get demo weekly stats
  static Map<String, dynamic> getDemoWeeklyStats() {
    return {
      'total_distance_km': 15.2,
      'total_rucks': 2,
      'total_calories': 1160,
      'total_elevation_gain_m': 165,
      'avg_pace_s_per_km': 885,
      'total_duration_seconds': 13500, // ~3.75 hours
    };
  }
}
