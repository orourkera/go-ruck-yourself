import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel_invitation.dart';

abstract class DuelInvitationsState extends Equatable {
  const DuelInvitationsState();

  @override
  List<Object?> get props => [];
}

class DuelInvitationsInitial extends DuelInvitationsState {}

class DuelInvitationsLoading extends DuelInvitationsState {}

class DuelInvitationsLoaded extends DuelInvitationsState {
  final List<DuelInvitation> invitations;
  final String? activeStatusFilter;
  final bool hasFilters;

  const DuelInvitationsLoaded({
    required this.invitations,
    this.activeStatusFilter,
    this.hasFilters = false,
  });

  DuelInvitationsLoaded copyWith({
    List<DuelInvitation>? invitations,
    String? activeStatusFilter,
    bool? hasFilters,
  }) {
    return DuelInvitationsLoaded(
      invitations: invitations ?? this.invitations,
      activeStatusFilter: activeStatusFilter ?? this.activeStatusFilter,
      hasFilters: hasFilters ?? this.hasFilters,
    );
  }

  @override
  List<Object?> get props => [invitations, activeStatusFilter, hasFilters];
}

class DuelInvitationsError extends DuelInvitationsState {
  final String message;

  const DuelInvitationsError({required this.message});

  @override
  List<Object> get props => [message];
}

class InvitationResponding extends DuelInvitationsState {
  final String invitationId;
  final String response;

  const InvitationResponding({
    required this.invitationId,
    required this.response,
  });

  @override
  List<Object> get props => [invitationId, response];
}

class InvitationResponseSuccess extends DuelInvitationsState {
  final String invitationId;
  final String response;
  final String message;

  const InvitationResponseSuccess({
    required this.invitationId,
    required this.response,
    required this.message,
  });

  @override
  List<Object> get props => [invitationId, response, message];
}

class InvitationResponseError extends DuelInvitationsState {
  final String invitationId;
  final String message;

  const InvitationResponseError({
    required this.invitationId,
    required this.message,
  });

  @override
  List<Object> get props => [invitationId, message];
}
