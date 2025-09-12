import 'package:equatable/equatable.dart';

class DuelStats extends Equatable {
  final String userId;
  final int duelsCreated;
  final int duelsJoined;
  final int duelsCompleted;
  final int duelsWon;
  final int duelsLost;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed stats from API
  final int? activeDuels;
  final int? pendingDuels;
  final double? avgWinningScore;
  final double? bestDistance;
  final double? bestTime;
  final double? bestElevation;
  final double? bestPowerPoints;

  // User info (if fetching other user's stats)
  final String? username;
  final String? email;
  final int? rank;

  const DuelStats({
    required this.userId,
    required this.duelsCreated,
    required this.duelsJoined,
    required this.duelsCompleted,
    required this.duelsWon,
    required this.duelsLost,
    required this.createdAt,
    required this.updatedAt,
    this.activeDuels,
    this.pendingDuels,
    this.avgWinningScore,
    this.bestDistance,
    this.bestTime,
    this.bestElevation,
    this.bestPowerPoints,
    this.username,
    this.email,
    this.rank,
  });

  // Utility getters
  int get totalDuels => duelsCreated + duelsJoined;

  double get winRate {
    if (duelsCompleted == 0) return 0.0;
    return duelsWon / duelsCompleted;
  }

  double get completionRate {
    if (totalDuels == 0) return 0.0;
    return duelsCompleted / totalDuels;
  }

  String get winRatePercentage => '${(winRate * 100).toStringAsFixed(1)}%';
  String get completionRatePercentage =>
      '${(completionRate * 100).toStringAsFixed(1)}%';

  bool get hasParticipatedInDuels => totalDuels > 0;
  bool get hasWonDuels => duelsWon > 0;
  bool get isActiveParticipant => (activeDuels ?? 0) > 0;

  DuelStats copyWith({
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
  }) {
    return DuelStats(
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
    );
  }

  @override
  List<Object?> get props => [
        userId,
        duelsCreated,
        duelsJoined,
        duelsCompleted,
        duelsWon,
        duelsLost,
        createdAt,
        updatedAt,
        activeDuels,
        pendingDuels,
        avgWinningScore,
        bestDistance,
        bestTime,
        bestElevation,
        bestPowerPoints,
        username,
        email,
        rank,
      ];
}
