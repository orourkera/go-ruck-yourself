import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel.dart';

enum DuelListViewMode {
  all,
  myDuels,
  discover,
}

abstract class DuelListState extends Equatable {
  const DuelListState();

  @override
  List<Object?> get props => [];
}

class DuelListInitial extends DuelListState {}

class DuelListLoading extends DuelListState {}

class DuelListLoaded extends DuelListState {
  final List<Duel> duels;
  final String? activeStatus;
  final String? activeChallengeType;
  final String? activeLocation;
  final bool hasFilters;
  final DuelListViewMode viewMode;

  const DuelListLoaded({
    required this.duels,
    this.activeStatus,
    this.activeChallengeType,
    this.activeLocation,
    this.hasFilters = false,
    this.viewMode = DuelListViewMode.all,
  });

  DuelListLoaded copyWith({
    List<Duel>? duels,
    String? activeStatus,
    String? activeChallengeType,
    String? activeLocation,
    bool? hasFilters,
    DuelListViewMode? viewMode,
  }) {
    return DuelListLoaded(
      duels: duels ?? this.duels,
      activeStatus: activeStatus ?? this.activeStatus,
      activeChallengeType: activeChallengeType ?? this.activeChallengeType,
      activeLocation: activeLocation ?? this.activeLocation,
      hasFilters: hasFilters ?? this.hasFilters,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  @override
  List<Object?> get props => [
        duels,
        activeStatus,
        activeChallengeType,
        activeLocation,
        hasFilters,
        viewMode,
      ];
}

class DuelListError extends DuelListState {
  final String message;

  const DuelListError({required this.message});

  @override
  List<Object> get props => [message];
}

class DuelJoining extends DuelListState {
  final String duelId;

  const DuelJoining({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelJoined extends DuelListState {
  final String duelId;
  final String message;

  const DuelJoined({
    required this.duelId,
    this.message = 'Successfully joined duel!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelJoinError extends DuelListState {
  final String duelId;
  final String message;

  const DuelJoinError({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}
