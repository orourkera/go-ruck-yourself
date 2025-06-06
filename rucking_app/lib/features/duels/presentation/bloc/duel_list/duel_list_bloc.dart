import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/duel.dart';
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
    on<LoadMyDuels>(_onLoadMyDuels);
    on<LoadDiscoverDuels>(_onLoadDiscoverDuels);
    on<RefreshDuels>(_onRefreshDuels);
    on<FilterDuels>(_onFilterDuels);
    on<JoinDuel>(_onJoinDuel);
    on<ClearFilters>(_onClearFilters);
  }

  void _onLoadDuels(LoadDuels event, Emitter<DuelListState> emit) async {
    print('[DEBUG] DuelListBloc._onLoadDuels() - Starting with status=${event.status}, challengeType=${event.challengeType}, location=${event.location}, limit=${event.limit}');
    
    emit(DuelListLoading());

    print('[DEBUG] DuelListBloc._onLoadDuels() - Calling getDuels usecase');
    
    final result = await getDuels(GetDuelsParams(
      status: event.status,
      challengeType: event.challengeType,
      location: event.location,
      limit: event.limit,
    ));

    print('[DEBUG] DuelListBloc._onLoadDuels() - Got result from usecase');

    result.fold(
      (failure) {
        print('[ERROR] DuelListBloc._onLoadDuels() - Failure: ${failure.message}');
        emit(DuelListError(message: failure.message));
      },
      (duels) {
        print('[DEBUG] DuelListBloc._onLoadDuels() - Success: got ${duels.length} duels');
        emit(DuelListLoaded(
          duels: duels,
          activeStatus: event.status,
          activeChallengeType: event.challengeType,
          activeLocation: event.location,
          hasFilters: _hasActiveFilters(
            event.status,
            event.challengeType,
            event.location,
          ),
        ));
      },
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

  void _onLoadMyDuels(LoadMyDuels event, Emitter<DuelListState> emit) async {
    print('[DEBUG] DuelListBloc._onLoadMyDuels() - Loading duels user is participating in');
    emit(DuelListLoading());

    final result = await getDuels(const GetDuelsParams(
      userParticipating: true,
    ));

    result.fold(
      (failure) {
        print('[ERROR] DuelListBloc._onLoadMyDuels() - Failure: ${failure.message}');
        emit(DuelListError(message: failure.message));
      },
      (duels) {
        print('[DEBUG] DuelListBloc._onLoadMyDuels() - Success: got ${duels.length} my duels');
        // Sort duels: active first, then pending, then completed
        final sortedDuels = List<Duel>.from(duels);
        sortedDuels.sort((a, b) {
          const statusOrder = {'active': 0, 'pending': 1, 'completed': 2};
          final aOrder = statusOrder[a.status] ?? 3;
          final bOrder = statusOrder[b.status] ?? 3;
          return aOrder.compareTo(bOrder);
        });

        emit(DuelListLoaded(
          duels: sortedDuels,
          activeStatus: null,
          activeChallengeType: null,
          activeLocation: null,
          hasFilters: false,
        ));
      },
    );
  }

  void _onLoadDiscoverDuels(LoadDiscoverDuels event, Emitter<DuelListState> emit) async {
    print('[DEBUG] DuelListBloc._onLoadDiscoverDuels() - Loading duels available to join');
    emit(DuelListLoading());

    final result = await getDuels(const GetDuelsParams(
      userParticipating: false,
    ));

    result.fold(
      (failure) {
        print('[ERROR] DuelListBloc._onLoadDiscoverDuels() - Failure: ${failure.message}');
        emit(DuelListError(message: failure.message));
      },
      (duels) {
        print('[DEBUG] DuelListBloc._onLoadDiscoverDuels() - Success: got ${duels.length} discover duels');
        emit(DuelListLoaded(
          duels: duels,
          activeStatus: null,
          activeChallengeType: null,
          activeLocation: null,
          hasFilters: false,
        ));
      },
    );
  }

  bool _hasActiveFilters(String? status, String? challengeType, String? location) {
    return status != null || challengeType != null || location != null;
  }
}
