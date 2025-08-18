import 'package:equatable/equatable.dart';

/// Well I'll be jiggered! These here events'll make our leaderboard dance
abstract class LeaderboardEvent extends Equatable {
  const LeaderboardEvent();

  @override
  List<Object?> get props => [];
}

/// Load up that leaderboard like loading hay bales
class LoadLeaderboard extends LeaderboardEvent {
  final String sortBy;
  final bool ascending;
  final int limit;
  final int offset;
  final String timePeriod;

  const LoadLeaderboard({
    this.sortBy = 'powerPoints',
    this.ascending = false, // Descending by default (highest first)
    this.limit = 100,
    this.offset = 0,
    this.timePeriod = 'all_time',
  });

  @override
  List<Object?> get props => [sortBy, ascending, limit, offset, timePeriod];
}

/// Refresh that data faster than a hound dog chasing a rabbit
class RefreshLeaderboard extends LeaderboardEvent {
  const RefreshLeaderboard();
}

/// Sort them rankings like sorting corn from chaff
class SortLeaderboard extends LeaderboardEvent {
  final String sortBy;
  final bool ascending;

  const SortLeaderboard({
    required this.sortBy,
    required this.ascending,
  });

  @override
  List<Object?> get props => [sortBy, ascending];
}

/// Search for users like hunting for a needle in a haystack
class SearchLeaderboard extends LeaderboardEvent {
  final String query;

  const SearchLeaderboard({required this.query});

  @override
  List<Object?> get props => [query];
}

/// Filter leaderboard by time period
class FilterLeaderboardByTimePeriod extends LeaderboardEvent {
  final String timePeriod;

  const FilterLeaderboardByTimePeriod({required this.timePeriod});

  @override
  List<Object?> get props => [timePeriod];
}

/// Load more users than you can shake a stick at
class LoadMoreUsers extends LeaderboardEvent {
  const LoadMoreUsers();
}

/// Real-time update when someone finishes their ruck
class UserRuckCompleted extends LeaderboardEvent {
  final String userId;
  final Map<String, dynamic> newStats;
  final int? newRank;

  const UserRuckCompleted({
    required this.userId,
    required this.newStats,
    this.newRank,
  });

  @override
  List<Object?> get props => [userId, newStats, newRank];
}

/// Update when someone starts rucking
class UserRuckStarted extends LeaderboardEvent {
  final String userId;

  const UserRuckStarted({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// Update user's rank position
class UserRankChanged extends LeaderboardEvent {
  final String userId;
  final int oldRank;
  final int newRank;

  const UserRankChanged({
    required this.userId,
    required this.oldRank,
    required this.newRank,
  });

  @override
  List<Object?> get props => [userId, oldRank, newRank];
}
