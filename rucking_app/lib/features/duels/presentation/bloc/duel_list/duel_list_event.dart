import 'package:equatable/equatable.dart';

abstract class DuelListEvent extends Equatable {
  const DuelListEvent();

  @override
  List<Object?> get props => [];
}

class LoadDuels extends DuelListEvent {
  final String? status;
  final String? challengeType;
  final String? location;
  final int? limit;

  const LoadDuels({
    this.status,
    this.challengeType,
    this.location,
    this.limit,
  });

  @override
  List<Object?> get props => [status, challengeType, location, limit];
}

class RefreshDuels extends DuelListEvent {}

class LoadMyDuels extends DuelListEvent {}

class LoadDiscoverDuels extends DuelListEvent {}

class FilterDuels extends DuelListEvent {
  final String? status;
  final String? challengeType;
  final String? location;

  const FilterDuels({
    this.status,
    this.challengeType,
    this.location,
  });

  @override
  List<Object?> get props => [status, challengeType, location];
}

class JoinDuel extends DuelListEvent {
  final String duelId;

  const JoinDuel({required this.duelId});

  @override
  List<Object?> get props => [duelId];
}

class ClearFilters extends DuelListEvent {}
