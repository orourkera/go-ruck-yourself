import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel_stats.dart';

abstract class DuelStatsState extends Equatable {
  const DuelStatsState();

  @override
  List<Object?> get props => [];
}

class DuelStatsInitial extends DuelStatsState {}

class DuelStatsLoading extends DuelStatsState {}

class UserDuelStatsLoaded extends DuelStatsState {
  final DuelStats userStats;
  final bool isLeaderboardLoading;
  final List<DuelStats> leaderboard;
  final String currentLeaderboardType;

  const UserDuelStatsLoaded({
    required this.userStats,
    this.isLeaderboardLoading = false,
    this.leaderboard = const [],
    this.currentLeaderboardType = 'wins',
  });

  UserDuelStatsLoaded copyWith({
    DuelStats? userStats,
    bool? isLeaderboardLoading,
    List<DuelStats>? leaderboard,
    String? currentLeaderboardType,
  }) {
    return UserDuelStatsLoaded(
      userStats: userStats ?? this.userStats,
      isLeaderboardLoading: isLeaderboardLoading ?? this.isLeaderboardLoading,
      leaderboard: leaderboard ?? this.leaderboard,
      currentLeaderboardType:
          currentLeaderboardType ?? this.currentLeaderboardType,
    );
  }

  @override
  List<Object?> get props => [
        userStats,
        isLeaderboardLoading,
        leaderboard,
        currentLeaderboardType,
      ];
}

class DuelStatsError extends DuelStatsState {
  final String message;

  const DuelStatsError({required this.message});

  @override
  List<Object> get props => [message];
}

class DuelStatsLeaderboardLoaded extends DuelStatsState {
  final List<DuelStats> leaderboard;
  final String statType;

  const DuelStatsLeaderboardLoaded({
    required this.leaderboard,
    required this.statType,
  });

  @override
  List<Object> get props => [leaderboard, statType];
}

class DuelStatsLeaderboardError extends DuelStatsState {
  final String message;
  final String statType;

  const DuelStatsLeaderboardError({
    required this.message,
    required this.statType,
  });

  @override
  List<Object> get props => [message, statType];
}
