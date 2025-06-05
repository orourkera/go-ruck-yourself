import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_duel_details.dart';
import '../../../domain/usecases/get_duel_leaderboard.dart';
import '../../../domain/usecases/join_duel.dart' as join_duel_usecase;
import '../../../domain/usecases/update_duel_progress.dart' as update_progress_usecase;
import 'duel_detail_event.dart';
import 'duel_detail_state.dart';

class DuelDetailBloc extends Bloc<DuelDetailEvent, DuelDetailState> {
  final GetDuelDetails getDuelDetails;
  final GetDuelLeaderboard getDuelLeaderboard;
  final join_duel_usecase.JoinDuel joinDuel;
  final update_progress_usecase.UpdateDuelProgress updateDuelProgress;

  DuelDetailBloc({
    required this.getDuelDetails,
    required this.getDuelLeaderboard,
    required this.joinDuel,
    required this.updateDuelProgress,
  }) : super(DuelDetailInitial()) {
    on<LoadDuelDetail>(_onLoadDuelDetail);
    on<RefreshDuelDetail>(_onRefreshDuelDetail);
    on<JoinDuelFromDetail>(_onJoinDuelFromDetail);
    on<LoadLeaderboard>(_onLoadLeaderboard);
    on<UpdateDuelProgress>(_onUpdateDuelProgress);
  }

  void _onLoadDuelDetail(LoadDuelDetail event, Emitter<DuelDetailState> emit) async {
    emit(DuelDetailLoading());

    final result = await getDuelDetails(GetDuelDetailsParams(duelId: event.duelId));

    result.fold(
      (failure) => emit(DuelDetailError(message: failure.message)),
      (duel) {
        emit(DuelDetailLoaded(duel: duel));
        // Auto-load leaderboard after loading duel
        add(LoadLeaderboard(duelId: event.duelId));
      },
    );
  }

  void _onRefreshDuelDetail(RefreshDuelDetail event, Emitter<DuelDetailState> emit) async {
    // If we're already loaded, just refresh the data without showing loading
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      
      final result = await getDuelDetails(GetDuelDetailsParams(duelId: event.duelId));

      result.fold(
        (failure) => emit(DuelDetailError(message: failure.message)),
        (duel) {
          emit(currentState.copyWith(duel: duel));
          // Refresh leaderboard too
          add(LoadLeaderboard(duelId: event.duelId));
        },
      );
    } else {
      add(LoadDuelDetail(duelId: event.duelId));
    }
  }

  void _onJoinDuelFromDetail(JoinDuelFromDetail event, Emitter<DuelDetailState> emit) async {
    emit(DuelJoiningFromDetail(duelId: event.duelId));

    final result = await joinDuel(join_duel_usecase.JoinDuelParams(duelId: event.duelId));

    result.fold(
      (failure) => emit(DuelJoinErrorFromDetail(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelJoinedFromDetail(duelId: event.duelId));
        // Refresh the duel details to show updated participant list
        add(RefreshDuelDetail(duelId: event.duelId));
      },
    );
  }

  void _onLoadLeaderboard(LoadLeaderboard event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      emit(currentState.copyWith(isLeaderboardLoading: true));

      final result = await getDuelLeaderboard(GetDuelLeaderboardParams(duelId: event.duelId));

      result.fold(
        (failure) {
          // Don't emit error for leaderboard failure, just stop loading
          emit(currentState.copyWith(isLeaderboardLoading: false));
        },
        (leaderboard) {
          emit(currentState.copyWith(
            leaderboard: leaderboard,
            isLeaderboardLoading: false,
          ));
        },
      );
    }
  }

  void _onUpdateDuelProgress(UpdateDuelProgress event, Emitter<DuelDetailState> emit) async {
    emit(DuelProgressUpdating(duelId: event.duelId));

    final result = await updateDuelProgress(update_progress_usecase.UpdateDuelProgressParams(
      duelId: event.duelId,
      participantId: event.participantId,
      sessionId: event.sessionId,
      contributionValue: event.contributionValue,
    ));

    result.fold(
      (failure) => emit(DuelProgressUpdateError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelProgressUpdated(duelId: event.duelId));
        // Refresh the duel details and leaderboard to show updated progress
        add(RefreshDuelDetail(duelId: event.duelId));
      },
    );
  }
}
