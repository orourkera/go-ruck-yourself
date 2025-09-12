import '../../domain/entities/duel_stats.dart';

class UserDuelStatsModel extends DuelStats {
  // Additional properties specific to the model
  final String id;
  final int duelsAbandoned;
  final double totalDistanceChallenged;
  final int totalTimeChallenged;
  final double totalElevationChallenged;
  final int totalPowerPointsChallenged;

  const UserDuelStatsModel({
    required this.id,
    required super.userId,
    required super.duelsCreated,
    required super.duelsJoined,
    required super.duelsCompleted,
    required super.duelsWon,
    required super.duelsLost,
    required super.createdAt,
    required super.updatedAt,
    required this.duelsAbandoned,
    required this.totalDistanceChallenged,
    required this.totalTimeChallenged,
    required this.totalElevationChallenged,
    required this.totalPowerPointsChallenged,
    super.activeDuels,
    super.pendingDuels,
    super.avgWinningScore,
    super.bestDistance,
    super.bestTime,
    super.bestElevation,
    super.bestPowerPoints,
    super.username,
    super.email,
    super.rank,
  });

  factory UserDuelStatsModel.fromJson(Map<String, dynamic> json) {
    return UserDuelStatsModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      duelsCreated: json['duels_created'] as int,
      duelsJoined: json['duels_joined'] as int,
      duelsCompleted: json['duels_completed'] as int,
      duelsWon: json['duels_won'] as int,
      duelsLost: json['duels_lost'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      duelsAbandoned: json['duels_abandoned'] as int,
      totalDistanceChallenged:
          (json['total_distance_challenged'] as num).toDouble(),
      totalTimeChallenged: json['total_time_challenged'] as int,
      totalElevationChallenged:
          (json['total_elevation_challenged'] as num).toDouble(),
      totalPowerPointsChallenged: json['total_power_points_challenged'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'duels_created': duelsCreated,
      'duels_joined': duelsJoined,
      'duels_completed': duelsCompleted,
      'duels_won': duelsWon,
      'duels_lost': duelsLost,
      'duels_abandoned': duelsAbandoned,
      'total_distance_challenged': totalDistanceChallenged,
      'total_time_challenged': totalTimeChallenged,
      'total_elevation_challenged': totalElevationChallenged,
      'total_power_points_challenged': totalPowerPointsChallenged,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  UserDuelStatsModel copyWith({
    String? id,
    String? userId,
    int? duelsCreated,
    int? duelsJoined,
    int? duelsCompleted,
    int? duelsWon,
    int? duelsLost,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? activeDuels,
    int? pendingDuels,
    double? avgWinningScore,
    double? bestDistance,
    double? bestTime,
    double? bestElevation,
    double? bestPowerPoints,
    String? username,
    String? email,
    int? rank,
    int? duelsAbandoned,
    double? totalDistanceChallenged,
    int? totalTimeChallenged,
    double? totalElevationChallenged,
    int? totalPowerPointsChallenged,
  }) {
    return UserDuelStatsModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      duelsCreated: duelsCreated ?? this.duelsCreated,
      duelsJoined: duelsJoined ?? this.duelsJoined,
      duelsCompleted: duelsCompleted ?? this.duelsCompleted,
      duelsWon: duelsWon ?? this.duelsWon,
      duelsLost: duelsLost ?? this.duelsLost,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activeDuels: activeDuels ?? this.activeDuels,
      pendingDuels: pendingDuels ?? this.pendingDuels,
      avgWinningScore: avgWinningScore ?? this.avgWinningScore,
      bestDistance: bestDistance ?? this.bestDistance,
      bestTime: bestTime ?? this.bestTime,
      bestElevation: bestElevation ?? this.bestElevation,
      bestPowerPoints: bestPowerPoints ?? this.bestPowerPoints,
      username: username ?? this.username,
      email: email ?? this.email,
      rank: rank ?? this.rank,
      duelsAbandoned: duelsAbandoned ?? this.duelsAbandoned,
      totalDistanceChallenged:
          totalDistanceChallenged ?? this.totalDistanceChallenged,
      totalTimeChallenged: totalTimeChallenged ?? this.totalTimeChallenged,
      totalElevationChallenged:
          totalElevationChallenged ?? this.totalElevationChallenged,
      totalPowerPointsChallenged:
          totalPowerPointsChallenged ?? this.totalPowerPointsChallenged,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        duelsCreated,
        duelsJoined,
        duelsCompleted,
        duelsWon,
        duelsLost,
        duelsAbandoned,
        totalDistanceChallenged,
        totalTimeChallenged,
        totalElevationChallenged,
        totalPowerPointsChallenged,
        createdAt,
        updatedAt,
      ];
}
