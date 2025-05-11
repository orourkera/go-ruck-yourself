import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';

class RuckBuddyModel extends RuckBuddy {

  const RuckBuddyModel({
    required String id,
    required String userId,
    required double ruckWeightKg,
    required int durationSeconds,
    required double distanceKm,
    required int caloriesBurned,
    required double elevationGainM,
    required double elevationLossM,
    DateTime? startedAt,
    DateTime? completedAt,
    required DateTime createdAt,
    int? avgHeartRate,
    required UserInfo user,
  }) : super(
    id: id,
    userId: userId,
    ruckWeightKg: ruckWeightKg,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    caloriesBurned: caloriesBurned,
    elevationGainM: elevationGainM,
    elevationLossM: elevationLossM,
    startedAt: startedAt,
    completedAt: completedAt,
    createdAt: createdAt,
    avgHeartRate: avgHeartRate,
    user: user,
  );

  factory RuckBuddyModel.fromJson(Map<String, dynamic> json) {
    // Handle conversion of dates from strings to DateTime objects
    DateTime? startedAtDate;
    if (json['started_at'] != null) {
      startedAtDate = DateTime.parse(json['started_at']);
    }
    
    DateTime? completedAtDate;
    if (json['completed_at'] != null) {
      completedAtDate = DateTime.parse(json['completed_at']);
    }
    
    DateTime createdAtDate = DateTime.parse(json['created_at']);

    // Extract user data
    Map<String, dynamic> userData = json['user'] ?? {};
    
    return RuckBuddyModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      ruckWeightKg: (json['ruck_weight_kg'] ?? 0).toDouble(),
      durationSeconds: json['duration_seconds'] ?? 0,
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      caloriesBurned: json['calories_burned'] ?? 0,
      elevationGainM: (json['elevation_gain_m'] ?? 0).toDouble(),
      elevationLossM: (json['elevation_loss_m'] ?? 0).toDouble(),
      startedAt: startedAtDate,
      completedAt: completedAtDate,
      createdAt: createdAtDate,
      avgHeartRate: json['avg_heart_rate'],
      user: UserInfo.fromJson(userData),
    );
  }

  // We don't need toJson for this model since it's only used for data fetching
  // If needed later, we would implement it with proper handling of the user object

  @override
  List<Object?> get props => [
    id, userId, ruckWeightKg, durationSeconds, 
    distanceKm, caloriesBurned, elevationGainM, 
    elevationLossM, startedAt, completedAt, createdAt, 
    avgHeartRate, user
  ];
}
