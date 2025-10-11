import 'package:equatable/equatable.dart';
import '../../data/models/leaderboard_user_model.dart';

/// Well ain't that something! These states'll track our leaderboard like a bloodhound
abstract class LeaderboardState extends Equatable {
  const LeaderboardState();

  @override
  List<Object?> get props => [];
}

/// Starting state, fresh as morning dew
class LeaderboardInitial extends LeaderboardState {
  const LeaderboardInitial();
}

/// Loading state - hold your horses!
class LeaderboardLoading extends LeaderboardState {
  const LeaderboardLoading();
}

/// Loading more users at the bottom
class LeaderboardLoadingMore extends LeaderboardState {
  final List<LeaderboardUserModel> currentUsers;
  final String sortBy;
  final bool ascending;
  final String? searchQuery;
  final int activeRuckersCount;

  const LeaderboardLoadingMore({
    required this.currentUsers,
    required this.sortBy,
    required this.ascending,
    this.searchQuery,
    this.activeRuckersCount = 0,
  });

  @override
  List<Object?> get props => [currentUsers, sortBy, ascending, searchQuery, activeRuckersCount];
}

/// Loaded and ready to rock like a front porch swing
class LeaderboardLoaded extends LeaderboardState {
  final List<LeaderboardUserModel> users;
  final String sortBy;
  final bool ascending;
  final bool hasMore;
  final String? searchQuery;
  final DateTime lastUpdated;
  final int? currentUserRank;
  final int activeRuckersCount;
  final String timePeriod;

  const LeaderboardLoaded({
    required this.users,
    required this.sortBy,
    required this.ascending,
    required this.hasMore,
    this.searchQuery,
    required this.lastUpdated,
    this.currentUserRank,
    this.activeRuckersCount = 0,
    this.timePeriod = 'all_time',
  });

  /// Copy this state slicker than a whistle
  LeaderboardLoaded copyWith({
    List<LeaderboardUserModel>? users,
    String? sortBy,
    bool? ascending,
    bool? hasMore,
    String? searchQuery,
    DateTime? lastUpdated,
    int? currentUserRank,
    int? activeRuckersCount,
    String? timePeriod,
  }) {
    return LeaderboardLoaded(
      users: users ?? this.users,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      hasMore: hasMore ?? this.hasMore,
      searchQuery: searchQuery ?? this.searchQuery,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      currentUserRank: currentUserRank ?? this.currentUserRank,
      activeRuckersCount: activeRuckersCount ?? this.activeRuckersCount,
      timePeriod: timePeriod ?? this.timePeriod,
    );
  }

  @override
  List<Object?> get props => [
        users,
        sortBy,
        ascending,
        hasMore,
        searchQuery,
        lastUpdated,
        currentUserRank,
        activeRuckersCount,
        timePeriod,
      ];
}

/// Real-time update happening - exciting as a barn raising!
class LeaderboardUpdating extends LeaderboardState {
  final List<LeaderboardUserModel> users;
  final String sortBy;
  final bool ascending;
  final bool hasMore;
  final String? searchQuery;
  final DateTime lastUpdated;
  final int? currentUserRank;
  final int activeRuckersCount;
  final String updateType; // 'rank_change', 'new_ruck', 'user_started'
  final String? affectedUserId;

  const LeaderboardUpdating({
    required this.users,
    required this.sortBy,
    required this.ascending,
    required this.hasMore,
    this.searchQuery,
    required this.lastUpdated,
    this.currentUserRank,
    this.activeRuckersCount = 0,
    required this.updateType,
    this.affectedUserId,
  });

  @override
  List<Object?> get props => [
        users,
        sortBy,
        ascending,
        hasMore,
        searchQuery,
        lastUpdated,
        currentUserRank,
        activeRuckersCount,
        updateType,
        affectedUserId,
      ];
}

/// Error state - something went cattywampus
class LeaderboardError extends LeaderboardState {
  final String message;
  final List<LeaderboardUserModel>?
      previousUsers; // Keep previous data if available

  const LeaderboardError({
    required this.message,
    this.previousUsers,
  });

  @override
  List<Object?> get props => [message, previousUsers];
}

/// Refreshing the data like a cool breeze on a hot day
class LeaderboardRefreshing extends LeaderboardState {
  final List<LeaderboardUserModel> currentUsers;
  final String sortBy;
  final bool ascending;
  final String? searchQuery;

  const LeaderboardRefreshing({
    required this.currentUsers,
    required this.sortBy,
    required this.ascending,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [currentUsers, sortBy, ascending, searchQuery];
}
