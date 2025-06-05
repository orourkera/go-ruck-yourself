import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_user_duel_stats.dart';
import '../../../domain/usecases/get_duel_stats_leaderboard.dart';
import 'duel_stats_event.dart';
import 'duel_stats_state.dart';

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

  void _onLoadUserDuelStats(LoadUserDuelStats event, Emitter<DuelStatsState> emit) async {
    emit(DuelStatsLoading());

    final result = await getUserDuelStats(GetUserDuelStatsParams(userId: event.userId));

    result.fold(
      (failure) => emit(DuelStatsError(message: failure.message)),
      (userStats) {
        emit(UserDuelStatsLoaded(userStats: userStats));
        // Auto-load default leaderboard
        add(const LoadDuelStatsLeaderboard());
      },
    );
  }

  void _onRefreshUserDuelStats(RefreshUserDuelStats event, Emitter<DuelStatsState> emit) async {
    // If we're already loaded, just refresh the data without showing loading
    if (state is UserDuelStatsLoaded) {
      final currentState = state as UserDuelStatsLoaded;
      
      final result = await getUserDuelStats(GetUserDuelStatsParams(userId: event.userId));

      result.fold(
        (failure) => emit(DuelStatsError(message: failure.message)),
        (userStats) {
          emit(currentState.copyWith(userStats: userStats));
          // Refresh current leaderboard too
          add(RefreshDuelStatsLeaderboard(
            statType: currentState.currentLeaderboardType,
          ));
        },
      );
    } else {
      add(LoadUserDuelStats(userId: event.userId));
    }
  }

  void _onLoadDuelStatsLeaderboard(LoadDuelStatsLeaderboard event, Emitter<DuelStatsState> emit) async {
    if (state is UserDuelStatsLoaded) {
      final currentState = state as UserDuelStatsLoaded;
      emit(currentState.copyWith(
        isLeaderboardLoading: true,
        currentLeaderboardType: event.statType,
      ));

      final result = await getDuelStatsLeaderboard(GetDuelStatsLeaderboardParams(
        statType: event.statType,
        limit: event.limit,
      ));

      result.fold(
        (failure) {
          emit(currentState.copyWith(
            isLeaderboardLoading: false,
            leaderboard: [],
          ));
        },
        (leaderboard) {
          emit(currentState.copyWith(
            isLeaderboardLoading: false,
            leaderboard: leaderboard,
            currentLeaderboardType: event.statType,
          ));
        },
      );
    } else {
      // Load leaderboard independently
      emit(DuelStatsLoading());

      final result = await getDuelStatsLeaderboard(GetDuelStatsLeaderboardParams(
        statType: event.statType,
        limit: event.limit,
      ));

      result.fold(
        (failure) => emit(DuelStatsLeaderboardError(
          message: failure.message,
          statType: event.statType,
        )),
        (leaderboard) => emit(DuelStatsLeaderboardLoaded(
          leaderboard: leaderboard,
          statType: event.statType,
        )),
      );
    }
  }

  void _onRefreshDuelStatsLeaderboard(RefreshDuelStatsLeaderboard event, Emitter<DuelStatsState> emit) async {
    add(LoadDuelStatsLeaderboard(
      statType: event.statType,
      limit: event.limit,
    ));
  }
}
