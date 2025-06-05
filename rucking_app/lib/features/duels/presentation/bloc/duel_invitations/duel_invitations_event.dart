import 'package:equatable/equatable.dart';

abstract class DuelInvitationsEvent extends Equatable {
  const DuelInvitationsEvent();

  @override
  List<Object?> get props => [];
}

class LoadDuelInvitations extends DuelInvitationsEvent {
  final String? status; // 'pending', 'accepted', 'declined'

  const LoadDuelInvitations({this.status});

  @override
  List<Object?> get props => [status];
}

class RefreshDuelInvitations extends DuelInvitationsEvent {}

class FilterInvitationsByStatus extends DuelInvitationsEvent {
  final String? status;

  const FilterInvitationsByStatus({this.status});

  @override
  List<Object?> get props => [status];
}

class RespondToInvitation extends DuelInvitationsEvent {
  final String invitationId;
  final String response; // 'accept' or 'decline'

  const RespondToInvitation({
    required this.invitationId,
    required this.response,
  });

  @override
  List<Object> get props => [invitationId, response];
}

class ClearInvitationFilters extends DuelInvitationsEvent {}
