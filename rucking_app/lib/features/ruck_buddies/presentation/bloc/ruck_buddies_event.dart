part of 'ruck_buddies_bloc.dart';

abstract class RuckBuddiesEvent extends Equatable {
  const RuckBuddiesEvent();

  @override
  List<Object> get props => [];
}

class FetchRuckBuddiesEvent extends RuckBuddiesEvent {
  final int limit;
  final String filter;

  const FetchRuckBuddiesEvent({
    this.limit = 20,
    this.filter = 'closest',
  });

  @override
  List<Object> get props => [limit, filter];
}

class FetchMoreRuckBuddiesEvent extends RuckBuddiesEvent {
  final int limit;

  const FetchMoreRuckBuddiesEvent({
    this.limit = 20,
  });

  @override
  List<Object> get props => [limit];
}

class FilterRuckBuddiesEvent extends RuckBuddiesEvent {
  final String filter;

  const FilterRuckBuddiesEvent({
    required this.filter,
  });

  @override
  List<Object> get props => [filter];
}

class RefreshRuckBuddiesEvent extends RuckBuddiesEvent {}
