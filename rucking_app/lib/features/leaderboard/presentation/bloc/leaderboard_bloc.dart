import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/models/leaderboard_user_model.dart';
import 'leaderboard_event.dart';
import 'leaderboard_state.dart';

/// Well butter my grits! This here Bloc manages our leaderboard like a champion bull rider
/// Handles loading, sorting, searching, and real-time updates
/// 
/// 🔒 PRIVACY: Only shows users with Allow_Ruck_Sharing = true (backend filtered)
class LeaderboardBloc extends Bloc<LeaderboardEvent, LeaderboardState> {
  final LeaderboardRepository repository;
  
  // Keep track of current data for real-time updates
  List<LeaderboardUserModel> _currentUsers = [];
  String _currentSortBy = 'powerPoints';
  bool _currentAscending = false;
  String? _currentSearchQuery;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 20;

  LeaderboardBloc({
    required this.repository,
  }) : super(const LeaderboardInitial()) {
    // Register them event handlers like signing up for a barn dance
    on<LoadLeaderboard>(_onLoadLeaderboard);
    on<RefreshLeaderboard>(_onRefreshLeaderboard);
    on<SortLeaderboard>(_onSortLeaderboard);
    on<SearchLeaderboard>(_onSearchLeaderboard);
    on<LoadMoreUsers>(_onLoadMoreUsers);
    on<UserRuckStarted>(_onUserRuckStarted);
    on<UserRuckCompleted>(_onUserRuckCompleted);
    on<UserRankChanged>(_onUserRankChanged);
  }

  /// Load that leaderboard like loading hay into a barn
  Future<void> _onLoadLeaderboard(
    LoadLeaderboard event,
    Emitter<LeaderboardState> emit,
  ) async {
    emit(const LeaderboardLoading());

    try {
      final response = await repository.getLeaderboard(
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        limit: _pageSize,
        offset: 0,
      );

      // Get current user rank
      final currentUserRank = await _getCurrentUserRank();

      _currentUsers = response.users;
      _hasMore = response.hasMore;
      _currentOffset = response.users.length;

      emit(LeaderboardLoaded(
        users: response.users,
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        hasMore: response.hasMore,
        lastUpdated: DateTime.now(),
        currentUserRank: currentUserRank,
        activeRuckersCount: response.activeRuckersCount,
      ));
    } catch (e) {
      emit(LeaderboardError(message: 'Well I\'ll be! Failed to load leaderboard: $e'));
    }
  }

  /// Refresh that data like getting fresh water from the well
  Future<void> _onRefreshLeaderboard(
    RefreshLeaderboard event,
    Emitter<LeaderboardState> emit,
  ) async {
    if (state is! LeaderboardLoaded) return;

    final currentState = state as LeaderboardLoaded;
    emit(LeaderboardRefreshing(
      currentUsers: currentState.users,
      sortBy: currentState.sortBy,
      ascending: currentState.ascending,
      searchQuery: currentState.searchQuery,
    ));

    try {
      _currentOffset = 0;
      _hasMore = true;

      final users = await repository.getLeaderboard(
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        limit: _pageSize,
        offset: 0,
        searchQuery: _currentSearchQuery,
      );

      final currentUserRank = await _getCurrentUserRank();

      _currentUsers = users;
      _hasMore = users.length >= _pageSize;
      _currentOffset = users.length;

      emit(LeaderboardLoaded(
        users: users,
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        hasMore: _hasMore,
        searchQuery: _currentSearchQuery,
        lastUpdated: DateTime.now(),
        currentUserRank: currentUserRank,
      ));
    } catch (e) {
      emit(LeaderboardError(
        message: 'Shucks! Failed to refresh leaderboard: $e',
        previousUsers: currentState.users,
      ));
    }
  }

  /// Sort them rankings like organizing a tool shed
  Future<void> _onSortLeaderboard(
    SortLeaderboard event,
    Emitter<LeaderboardState> emit,
  ) async {
    if (state is! LeaderboardLoaded) return;

    final currentState = state as LeaderboardLoaded;
    emit(const LeaderboardLoading());

    try {
      _currentSortBy = event.sortBy;
      _currentAscending = event.ascending;
      _currentOffset = 0;
      _hasMore = true;

      final users = await repository.getLeaderboard(
        sortBy: event.sortBy,
        ascending: event.ascending,
        limit: _pageSize,
        offset: 0,
        searchQuery: _currentSearchQuery,
      );

      final currentUserRank = await _getCurrentUserRank();

      _currentUsers = users;
      _hasMore = users.length >= _pageSize;
      _currentOffset = users.length;

      emit(LeaderboardLoaded(
        users: users,
        sortBy: event.sortBy,
        ascending: event.ascending,
        hasMore: _hasMore,
        searchQuery: _currentSearchQuery,
        lastUpdated: DateTime.now(),
        currentUserRank: currentUserRank,
      ));
    } catch (e) {
      emit(LeaderboardError(
        message: 'Darn tootin\'! Failed to sort leaderboard: $e',
        previousUsers: currentState.users,
      ));
    }
  }

  /// Search for users like hunting for a lost calf
  Future<void> _onSearchLeaderboard(
    SearchLeaderboard event,
    Emitter<LeaderboardState> emit,
  ) async {
    if (state is! LeaderboardLoaded) return;

    emit(const LeaderboardLoading());

    try {
      _currentSearchQuery = event.query.trim().isEmpty ? null : event.query.trim();
      _currentOffset = 0;
      _hasMore = true;

      final users = await repository.getLeaderboard(
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        limit: _pageSize,
        offset: 0,
        searchQuery: _currentSearchQuery,
      );

      final currentUserRank = await _getCurrentUserRank();

      _currentUsers = users;
      _hasMore = users.length >= _pageSize;
      _currentOffset = users.length;

      emit(LeaderboardLoaded(
        users: users,
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        hasMore: _hasMore,
        searchQuery: _currentSearchQuery,
        lastUpdated: DateTime.now(),
        currentUserRank: currentUserRank,
      ));
    } catch (e) {
      emit(LeaderboardError(message: 'Well I\'ll be! Failed to search leaderboard: $e'));
    }
  }

  /// Load more users like adding more logs to the fire
  Future<void> _onLoadMoreUsers(
    LoadMoreUsers event,
    Emitter<LeaderboardState> emit,
  ) async {
    if (state is! LeaderboardLoaded) return;
    
    final currentState = state as LeaderboardLoaded;
    if (!currentState.hasMore) return;

    emit(LeaderboardLoadingMore(
      currentUsers: currentState.users,
      sortBy: currentState.sortBy,
      ascending: currentState.ascending,
      searchQuery: currentState.searchQuery,
    ));

    try {
      final newUsers = await repository.getLeaderboard(
        sortBy: _currentSortBy,
        ascending: _currentAscending,
        limit: _pageSize,
        offset: _currentOffset,
        searchQuery: _currentSearchQuery,
      );

      _currentUsers.addAll(newUsers);
      _hasMore = newUsers.length >= _pageSize;
      _currentOffset += newUsers.length;

      emit(LeaderboardLoaded(
        users: List.from(_currentUsers),
        sortBy: currentState.sortBy,
        ascending: currentState.ascending,
        hasMore: _hasMore,
        searchQuery: currentState.searchQuery,
        lastUpdated: DateTime.now(),
        currentUserRank: currentState.currentUserRank,
      ));
    } catch (e) {
      emit(LeaderboardError(
        message: 'Dag nabbit! Failed to load more users: $e',
        previousUsers: currentState.users,
      ));
    }
  }

  /// Handle user starting a ruck
  void _onUserRuckStarted(
    UserRuckStarted event,
    Emitter<LeaderboardState> emit,
  ) {
    if (state is! LeaderboardLoaded) return;

    final currentState = state as LeaderboardLoaded;
    final updatedUsers = _updateUserStatus(currentState.users, event.userId, isRucking: true);

    emit(LeaderboardUpdating(
      users: updatedUsers,
      sortBy: currentState.sortBy,
      ascending: currentState.ascending,
      hasMore: currentState.hasMore,
      searchQuery: currentState.searchQuery,
      lastUpdated: DateTime.now(),
      currentUserRank: currentState.currentUserRank,
      updateType: 'user_started',
      affectedUserId: event.userId,
    ));
  }

  /// Handle user completing a ruck
  void _onUserRuckCompleted(
    UserRuckCompleted event,
    Emitter<LeaderboardState> emit,
  ) {
    if (state is! LeaderboardLoaded) return;

    final currentState = state as LeaderboardLoaded;
    final updatedUsers = _updateUserStats(currentState.users, event.userId, event.newStats);

    emit(LeaderboardUpdating(
      users: updatedUsers,
      sortBy: currentState.sortBy,
      ascending: currentState.ascending,
      hasMore: currentState.hasMore,
      searchQuery: currentState.searchQuery,
      lastUpdated: DateTime.now(),
      currentUserRank: currentState.currentUserRank,
      updateType: 'new_ruck',
      affectedUserId: event.userId,
    ));
  }

  /// Handle user rank change
  void _onUserRankChanged(
    UserRankChanged event,
    Emitter<LeaderboardState> emit,
  ) {
    // For now, just refresh the leaderboard
    add(const RefreshLeaderboard());
  }

  /// Get current user's rank
  Future<int?> _getCurrentUserRank() async {
    try {
      return await repository.getCurrentUserRank(sortBy: _currentSortBy);
    } catch (e) {
      return null;
    }
  }

  /// Update user status (currently rucking)
  List<LeaderboardUserModel> _updateUserStatus(
    List<LeaderboardUserModel> users,
    String userId,
    {required bool isRucking}
  ) {
    return users.map((user) {
      if (user.userId == userId) {
        return user.copyWith(isCurrentlyRucking: isRucking);
      }
      return user;
    }).toList();
  }

  /// Update user stats after ruck completion
  List<LeaderboardUserModel> _updateUserStats(
    List<LeaderboardUserModel> users,
    String userId,
    Map<String, dynamic> newStats,
  ) {
    return users.map((user) {
      if (user.userId == userId) {
        // Create updated stats
        final updatedStats = LeaderboardStatsModel(
          totalRucks: newStats['totalRucks'] ?? user.stats.totalRucks,
          distanceKm: newStats['distanceKm'] ?? user.stats.distanceKm,
          elevationGainMeters: newStats['elevationGainMeters'] ?? user.stats.elevationGainMeters,
          caloriesBurned: newStats['caloriesBurned'] ?? user.stats.caloriesBurned,
          powerPoints: newStats['powerPoints'] ?? user.stats.powerPoints,
          averageDistanceKm: newStats['averageDistanceKm'] ?? user.stats.averageDistanceKm,
          averagePaceMinKm: newStats['averagePaceMinKm'] ?? user.stats.averagePaceMinKm,
        );
        
        return user.copyWith(
          stats: updatedStats,
          isCurrentlyRucking: false,
          lastRuckDate: DateTime.now(),
        );
      }
      return user;
    }).toList();
  }
}
