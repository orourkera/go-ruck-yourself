part of 'ruck_buddies_bloc.dart';

abstract class RuckBuddiesState extends Equatable {
  const RuckBuddiesState();
  
  @override
  List<Object> get props => [];
}

class RuckBuddiesInitial extends RuckBuddiesState {}

class RuckBuddiesLoading extends RuckBuddiesState {}

class RuckBuddiesLoaded extends RuckBuddiesState {
  final List<RuckBuddy> ruckBuddies;
  final bool hasReachedMax;
  final String filter;
  final double? latitude;
  final double? longitude;
  final bool isLoadingMore;

  const RuckBuddiesLoaded({
    required this.ruckBuddies,
    required this.hasReachedMax,
    required this.filter,
    this.latitude,
    this.longitude,
    this.isLoadingMore = false,
  });

  @override
  List<Object?> get props => [ruckBuddies, hasReachedMax, filter, latitude, longitude, isLoadingMore];
}

class RuckBuddiesError extends RuckBuddiesState {
  final String message;

  const RuckBuddiesError({required this.message});

  @override
  List<Object> get props => [message];
}
