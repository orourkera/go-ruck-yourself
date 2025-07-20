import 'package:equatable/equatable.dart';

/// Well butter my biscuit! This here's the data model for our leaderboard users
class LeaderboardUserModel extends Equatable {
  final String userId;
  final String username;
  final String? avatarUrl;
  final String? gender;
  final LeaderboardStatsModel stats;
  final DateTime? lastRuckDate;
  final String? lastRuckLocation;
  final bool isCurrentUser;
  final bool isCurrentlyRucking;

  const LeaderboardUserModel({
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.gender,
    required this.stats,
    this.lastRuckDate,
    this.lastRuckLocation,
    this.isCurrentUser = false,
    this.isCurrentlyRucking = false,
  });

  /// Hot diggity dog! Create from JSON like mama's apple pie
  factory LeaderboardUserModel.fromJson(Map<String, dynamic> json) {
    return LeaderboardUserModel(
      userId: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      gender: json['gender'] as String?,
      stats: LeaderboardStatsModel.fromJson(json['stats'] ?? {}),
      lastRuckDate: json['last_ruck_date'] != null 
          ? DateTime.parse(json['last_ruck_date'] as String)
          : null,
      lastRuckLocation: json['location'] as String?,
      isCurrentUser: json['is_current_user'] as bool? ?? false,
      isCurrentlyRucking: json['isCurrentlyRucking'] as bool? ?? false,
    );
  }

  /// Convert to JSON slicker than a whistle
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'avatar_url': avatarUrl,
      'gender': gender,
      'last_ruck_date': lastRuckDate?.toIso8601String(),
      'last_ruck_location': lastRuckLocation,
      'is_current_user': isCurrentUser,
      'is_currently_rucking': isCurrentlyRucking,
      ...stats.toJson(),
    };
  }

  /// Copy this critter with new values
  LeaderboardUserModel copyWith({
    String? userId,
    String? username,
    String? avatarUrl,
    String? gender,
    LeaderboardStatsModel? stats,
    DateTime? lastRuckDate,
    String? lastRuckLocation,
    bool? isCurrentUser,
    bool? isCurrentlyRucking,
  }) {
    return LeaderboardUserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      stats: stats ?? this.stats,
      lastRuckDate: lastRuckDate ?? this.lastRuckDate,
      lastRuckLocation: lastRuckLocation ?? this.lastRuckLocation,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      isCurrentlyRucking: isCurrentlyRucking ?? this.isCurrentlyRucking,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        username,
        avatarUrl,
        gender,
        stats,
        lastRuckDate,
        lastRuckLocation,
        isCurrentUser,
        isCurrentlyRucking,
      ];
}

/// Shucks! The stats model that'll make your mama proud
class LeaderboardStatsModel extends Equatable {
  final int totalRucks;
  final double distanceKm;
  final double elevationGainMeters;
  final double caloriesBurned;
  final double powerPoints;
  final double averageDistanceKm;
  final double averagePaceMinKm;

  const LeaderboardStatsModel({
    required this.totalRucks,
    required this.distanceKm,
    required this.elevationGainMeters,
    required this.caloriesBurned,
    required this.powerPoints,
    required this.averageDistanceKm,
    required this.averagePaceMinKm,
  });

  /// Parse from JSON like churning butter
  factory LeaderboardStatsModel.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse numbers (learned from ruck_session.dart)
    num? safeParseNum(dynamic value) {
      if (value == null) return null;
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    }

    return LeaderboardStatsModel(
      totalRucks: safeParseNum(json['rucks'])?.toInt() ?? 0,
      distanceKm: safeParseNum(json['distanceKm'])?.toDouble() ?? 0.0,
      elevationGainMeters: safeParseNum(json['elevationGainMeters'])?.toDouble() ?? 0.0,
      caloriesBurned: safeParseNum(json['caloriesBurned'])?.toDouble() ?? 0.0,
      powerPoints: safeParseNum(json['powerPoints'])?.toDouble() ?? 0.0,
      averageDistanceKm: safeParseNum(json['averageDistanceKm'])?.toDouble() ?? 0.0,
      averagePaceMinKm: safeParseNum(json['averagePaceMinKm'])?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON smooth as molasses
  Map<String, dynamic> toJson() {
    return {
      'total_rucks': totalRucks,
      'total_distance_km': distanceKm,
      'total_elevation_gain_meters': elevationGainMeters,
      'total_calories_burned': caloriesBurned,
      'total_power_points': powerPoints,
      'average_distance_km': averageDistanceKm,
      'average_pace_min_km': averagePaceMinKm,
    };
  }

  @override
  List<Object?> get props => [
        totalRucks,
        distanceKm,
        elevationGainMeters,
        caloriesBurned,
        powerPoints,
        averageDistanceKm,
        averagePaceMinKm,
      ];
}
