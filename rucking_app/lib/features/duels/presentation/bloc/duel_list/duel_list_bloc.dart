import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_duels.dart';
import '../../../domain/usecases/join_duel.dart' as join_duel_usecase;
import 'duel_list_event.dart';
import 'duel_list_state.dart';

class DuelListBloc extends Bloc<DuelListEvent, DuelListState> {
  final GetDuels getDuels;
  final join_duel_usecase.JoinDuel joinDuel;

  DuelListBloc({
    required this.getDuels,
    required this.joinDuel,
  }) : super(DuelListInitial()) {
    on<LoadDuels>(_onLoadDuels);
    on<RefreshDuels>(_onRefreshDuels);
    on<FilterDuels>(_onFilterDuels);
    on<JoinDuel>(_onJoinDuel);
    on<ClearFilters>(_onClearFilters);
  }

  void _onLoadDuels(LoadDuels event, Emitter<DuelListState> emit) async {
    emit(DuelListLoading());

    final result = await getDuels(GetDuelsParams(
      status: event.status,
      challengeType: event.challengeType,
      location: event.location,
      limit: event.limit,
    ));

    result.fold(
      (failure) => emit(DuelListError(message: failure.message)),
      (duels) => emit(DuelListLoaded(
        duels: duels,
        activeStatus: event.status,
        activeChallengeType: event.challengeType,
        activeLocation: event.location,
        hasFilters: _hasActiveFilters(
          event.status,
          event.challengeType,
          event.location,
        ),
      )),
    );
  }

  void _onRefreshDuels(RefreshDuels event, Emitter<DuelListState> emit) async {
    // Keep current filters if duels are loaded
    if (state is DuelListLoaded) {
      final currentState = state as DuelListLoaded;
      add(LoadDuels(
        status: currentState.activeStatus,
        challengeType: currentState.activeChallengeType,
        location: currentState.activeLocation,
      ));
    } else {
      add(const LoadDuels());
    }
  }

  void _onFilterDuels(FilterDuels event, Emitter<DuelListState> emit) async {
    emit(DuelListLoading());

    final result = await getDuels(GetDuelsParams(
      status: event.status,
      challengeType: event.challengeType,
      location: event.location,
    ));

    result.fold(
      (failure) => emit(DuelListError(message: failure.message)),
      (duels) => emit(DuelListLoaded(
        duels: duels,
        activeStatus: event.status,
        activeChallengeType: event.challengeType,
        activeLocation: event.location,
        hasFilters: _hasActiveFilters(
          event.status,
          event.challengeType,
          event.location,
        ),
      )),
    );
  }

  void _onJoinDuel(JoinDuel event, Emitter<DuelListState> emit) async {
    emit(DuelJoining(duelId: event.duelId));

    final result = await joinDuel(join_duel_usecase.JoinDuelParams(duelId: event.duelId));

    result.fold(
      (failure) => emit(DuelJoinError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelJoined(duelId: event.duelId));
        // Refresh the list to show updated state
        add(RefreshDuels());
      },
    );
  }

  void _onClearFilters(ClearFilters event, Emitter<DuelListState> emit) async {
    add(const LoadDuels());
  }

  bool _hasActiveFilters(String? status, String? challengeType, String? location) {
    return status != null || challengeType != null || location != null;
  }
}
