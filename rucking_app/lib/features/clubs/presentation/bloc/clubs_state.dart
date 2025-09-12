import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';

abstract class ClubsState extends Equatable {
  const ClubsState();

  @override
  List<Object?> get props => [];
}

class ClubsInitial extends ClubsState {}

class ClubsLoading extends ClubsState {}

class ClubsLoaded extends ClubsState {
  final List<Club> clubs;
  final String? searchQuery;
  final bool? isPublicFilter;
  final String? membershipFilter;

  const ClubsLoaded({
    required this.clubs,
    this.searchQuery,
    this.isPublicFilter,
    this.membershipFilter,
  });

  @override
  List<Object?> get props =>
      [clubs, searchQuery, isPublicFilter, membershipFilter];
}

class ClubsError extends ClubsState {
  final String message;

  const ClubsError(this.message);

  @override
  List<Object?> get props => [message];
}

class ClubDetailsLoading extends ClubsState {
  final String clubId;

  const ClubDetailsLoading(this.clubId);

  @override
  List<Object?> get props => [clubId];
}

class ClubDetailsLoaded extends ClubsState {
  final ClubDetails clubDetails;

  const ClubDetailsLoaded(this.clubDetails);

  @override
  List<Object?> get props => [clubDetails];
}

class ClubDetailsError extends ClubsState {
  final String message;
  final String clubId;

  const ClubDetailsError(this.message, this.clubId);

  @override
  List<Object?> get props => [message, clubId];
}

class ClubActionLoading extends ClubsState {
  final String message;

  const ClubActionLoading(this.message);

  @override
  List<Object?> get props => [message];
}

class ClubActionSuccess extends ClubsState {
  final String message;
  final bool shouldRefresh;

  const ClubActionSuccess(this.message, {this.shouldRefresh = true});

  @override
  List<Object?> get props => [message, shouldRefresh];
}

class ClubActionError extends ClubsState {
  final String message;

  const ClubActionError(this.message);

  @override
  List<Object?> get props => [message];
}
