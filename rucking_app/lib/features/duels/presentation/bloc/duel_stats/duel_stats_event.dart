import 'package:equatable/equatable.dart';

abstract class DuelStatsEvent extends Equatable {
  const DuelStatsEvent();

  @override
  List<Object?> get props => [];
}

class LoadUserDuelStats extends DuelStatsEvent {
  final String? userId; // null for current user

  const LoadUserDuelStats({this.userId});

  @override
  List<Object?> get props => [userId];
}

class RefreshUserDuelStats extends DuelStatsEvent {
  final String? userId;

  const RefreshUserDuelStats({this.userId});

  @override
  List<Object?> get props => [userId];
}

class LoadDuelStatsLeaderboard extends DuelStatsEvent {
  final String statType;
  final int limit;

  const LoadDuelStatsLeaderboard({
    this.statType = 'wins',
    this.limit = 50,
  });

  @override
  List<Object> get props => [statType, limit];
}

class RefreshDuelStatsLeaderboard extends DuelStatsEvent {
  final String statType;
  final int limit;

  const RefreshDuelStatsLeaderboard({
    this.statType = 'wins',
    this.limit = 50,
  });

  @override
  List<Object> get props => [statType, limit];
}
