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
    DateTime? startedAtDate;
    if (json['started_at'] != null) {
      startedAtDate = DateTime.parse(json['started_at']);
    }
    DateTime? completedAtDate;
    if (json['completed_at'] != null) {
      completedAtDate = DateTime.parse(json['completed_at']);
    }
    DateTime createdAtDate;
    if (json['created_at'] != null) {
      createdAtDate = DateTime.parse(json['created_at']);
    } else if (json['started_at'] != null) {
      createdAtDate = DateTime.parse(json['started_at']);
    } else {
      createdAtDate = DateTime.now();
    }
    Map<String, dynamic> userData = json['users'] ?? {};
import 'package:equatable/equatable.dart';

class RuckBuddyModel extends Equatable {
  final String id;
  final String userId;
  final double ruckWeightKg;
  final int durationSeconds;
  final double distanceKm;
  final int caloriesBurned;
  final double elevationGainM;
  final double elevationLossM;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final int? avgHeartRate;
  final UserInfo user;

  const RuckBuddyModel({
    required this.id,
    required this.userId,
    required this.ruckWeightKg,
    required this.durationSeconds,
    required this.distanceKm,
    required this.caloriesBurned,
    required this.elevationGainM,
    required this.elevationLossM,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    this.avgHeartRate,
    required this.user,
  });

  factory RuckBuddyModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? userJson = json['users'];
>>>>>>> 0789ed16 (feat: Implement Ruck Buddies feature)
    
    return RuckBuddyModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
<<<<<<< HEAD
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

  // No toJson needed for this model (fetch-only)
}
<<<<<<< HEAD
=======

class UserInfo extends Equatable {
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const UserInfo({
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      username: json['username'],
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
  };
  
  String get displayNameOrUsername => displayName ?? username ?? 'Anonymous Rucker';

  @override
  List<Object?> get props => [username, displayName, avatarUrl];
}
>>>>>>> 0789ed16 (feat: Implement Ruck Buddies feature)
