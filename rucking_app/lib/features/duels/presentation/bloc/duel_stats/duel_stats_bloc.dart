import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_user_duel_stats.dart';
import '../../../domain/usecases/get_duel_stats_leaderboard.dart';
import 'duel_stats_event.dart';
import 'duel_stats_state.dart';
import '../../../../../core/utils/app_logger.dart';

class DuelStatsBloc extends Bloc<DuelStatsEvent, DuelStatsState> {
  final GetUserDuelStats getUserDuelStats;
  final GetDuelStatsLeaderboard getDuelStatsLeaderboard;

  DuelStatsBloc({
    required this.getUserDuelStats,
    required this.getDuelStatsLeaderboard,
  }) : super(DuelStatsInitial()) {
    on<LoadUserDuelStats>(_onLoadUserDuelStats);
    on<RefreshUserDuelStats>(_onRefreshUserDuelStats);
    on<LoadDuelStatsLeaderboard>(_onLoadDuelStatsLeaderboard);
    on<RefreshDuelStatsLeaderboard>(_onRefreshDuelStatsLeaderboard);
  }

  void _onLoadUserDuelStats(
      LoadUserDuelStats event, Emitter<DuelStatsState> emit) async {
    AppLogger.info(
        '[DUEL_STATS] Loading user duel stats - userId: ${event.userId}');
    emit(DuelStatsLoading());

    try {
      final result =
          await getUserDuelStats(GetUserDuelStatsParams(userId: event.userId));
      AppLogger.info('[DUEL_STATS] User duel stats API call completed');

      result.fold(
        (failure) {
          AppLogger.error(
              '[DUEL_STATS] Failed to load user duel stats: ${failure.message}');
          emit(DuelStatsError(message: failure.message));
        },
        (userStats) {
          AppLogger.info(
              '[DUEL_STATS] User duel stats loaded successfully: ${userStats.toString()}');
          emit(UserDuelStatsLoaded(userStats: userStats));
          // Auto-load default leaderboard
          AppLogger.info('[DUEL_STATS] Auto-loading default leaderboard');
          add(const LoadDuelStatsLeaderboard());
        },
      );
    } catch (e) {
      AppLogger.error(
          '[DUEL_STATS] Unexpected error loading user duel stats: $e');
      emit(DuelStatsError(message: 'Unexpected error: $e'));
    }
  }

  void _onRefreshUserDuelStats(
      RefreshUserDuelStats event, Emitter<DuelStatsState> emit) async {
    AppLogger.info(
        '[DUEL_STATS] Refreshing user duel stats - userId: ${event.userId}');

    // If we're already loaded, just refresh the data without showing loading
    if (state is UserDuelStatsLoaded) {
      AppLogger.info('[DUEL_STATS] State is already loaded, refreshing data');
      final currentState = state as UserDuelStatsLoaded;

      try {
        final result = await getUserDuelStats(
            GetUserDuelStatsParams(userId: event.userId));
        AppLogger.info('[DUEL_STATS] Refresh API call completed');

        result.fold(
          (failure) {
            AppLogger.error(
                '[DUEL_STATS] Failed to refresh user duel stats: ${failure.message}');
            emit(DuelStatsError(message: failure.message));
          },
          (userStats) {
            AppLogger.info(
                '[DUEL_STATS] User duel stats refreshed successfully');
            emit(currentState.copyWith(userStats: userStats));
            // Refresh current leaderboard too
            add(RefreshDuelStatsLeaderboard(
              statType: currentState.currentLeaderboardType,
            ));
          },
        );
      } catch (e) {
        AppLogger.error(
            '[DUEL_STATS] Unexpected error refreshing user duel stats: $e');
        emit(DuelStatsError(message: 'Refresh failed: $e'));
      }
    } else {
      AppLogger.info('[DUEL_STATS] State not loaded yet, loading initial data');
      add(LoadUserDuelStats(userId: event.userId));
    }
  }

  void _onLoadDuelStatsLeaderboard(
      LoadDuelStatsLeaderboard event, Emitter<DuelStatsState> emit) async {
    AppLogger.info(
        '[DUEL_STATS] Loading leaderboard - statType: ${event.statType}, limit: ${event.limit}');

    if (state is UserDuelStatsLoaded) {
      AppLogger.info(
          '[DUEL_STATS] User stats loaded, loading leaderboard with context');
      final currentState = state as UserDuelStatsLoaded;
      emit(currentState.copyWith(
        isLeaderboardLoading: true,
        currentLeaderboardType: event.statType,
      ));

      try {
        final result =
            await getDuelStatsLeaderboard(GetDuelStatsLeaderboardParams(
          statType: event.statType,
          limit: event.limit,
        ));
        AppLogger.info('[DUEL_STATS] Leaderboard API call completed');

        result.fold(
          (failure) {
            AppLogger.error(
                '[DUEL_STATS] Failed to load leaderboard: ${failure.message}');
            emit(currentState.copyWith(
              isLeaderboardLoading: false,
              leaderboard: [],
            ));
          },
          (leaderboard) {
            AppLogger.info(
                '[DUEL_STATS] Leaderboard loaded successfully - ${leaderboard.length} entries');
            emit(currentState.copyWith(
              isLeaderboardLoading: false,
              leaderboard: leaderboard,
              currentLeaderboardType: event.statType,
            ));
          },
        );
      } catch (e) {
        AppLogger.error(
            '[DUEL_STATS] Unexpected error loading leaderboard: $e');
        emit(currentState.copyWith(
          isLeaderboardLoading: false,
          leaderboard: [],
        ));
      }
    } else {
      AppLogger.info(
          '[DUEL_STATS] No user stats context, loading leaderboard independently');
      // Load leaderboard independently
      emit(DuelStatsLoading());

      try {
        final result =
            await getDuelStatsLeaderboard(GetDuelStatsLeaderboardParams(
          statType: event.statType,
          limit: event.limit,
        ));
        AppLogger.info(
            '[DUEL_STATS] Independent leaderboard API call completed');

        result.fold(
          (failure) {
            AppLogger.error(
                '[DUEL_STATS] Failed to load independent leaderboard: ${failure.message}');
            emit(DuelStatsLeaderboardError(
              message: failure.message,
              statType: event.statType,
            ));
          },
          (leaderboard) {
            AppLogger.info(
                '[DUEL_STATS] Independent leaderboard loaded successfully - ${leaderboard.length} entries');
            emit(DuelStatsLeaderboardLoaded(
              leaderboard: leaderboard,
              statType: event.statType,
            ));
          },
        );
      } catch (e) {
        AppLogger.error(
            '[DUEL_STATS] Unexpected error loading independent leaderboard: $e');
        emit(DuelStatsLeaderboardError(
          message: 'Unexpected error: $e',
          statType: event.statType,
        ));
      }
    }
  }

  void _onRefreshDuelStatsLeaderboard(
      RefreshDuelStatsLeaderboard event, Emitter<DuelStatsState> emit) async {
    add(LoadDuelStatsLeaderboard(
      statType: event.statType,
      limit: event.limit,
    ));
  }
}
