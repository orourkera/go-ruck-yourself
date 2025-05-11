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
    
    return RuckBuddyModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      ruckWeightKg: json['ruck_weight_kg']?.toDouble() ?? 0.0,
      durationSeconds: json['duration_seconds'] ?? 0,
      distanceKm: json['distance_km']?.toDouble() ?? 0.0,
      caloriesBurned: json['calories_burned']?.toInt() ?? 0,
      elevationGainM: json['elevation_gain_m']?.toDouble() ?? 0.0,
      elevationLossM: json['elevation_loss_m']?.toDouble() ?? 0.0,
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      avgHeartRate: json['avg_heart_rate'],
      user: UserInfo.fromJson(userJson ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'ruck_weight_kg': ruckWeightKg,
    'duration_seconds': durationSeconds,
    'distance_km': distanceKm,
    'calories_burned': caloriesBurned,
    'elevation_gain_m': elevationGainM,
    'elevation_loss_m': elevationLossM,
    'started_at': startedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'avg_heart_rate': avgHeartRate,
    'users': user.toJson(),
  };

  @override
  List<Object?> get props => [
    id, userId, ruckWeightKg, durationSeconds, 
    distanceKm, caloriesBurned, elevationGainM, 
    elevationLossM, startedAt, completedAt, createdAt, 
    avgHeartRate, user
  ];
}

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
