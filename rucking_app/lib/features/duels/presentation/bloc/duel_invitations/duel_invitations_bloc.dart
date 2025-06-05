import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_duel_invitations.dart';
import '../../../domain/usecases/respond_to_invitation.dart' as respond_invitation_usecase;
import 'duel_invitations_event.dart';
import 'duel_invitations_state.dart';

class DuelInvitationsBloc extends Bloc<DuelInvitationsEvent, DuelInvitationsState> {
  final GetDuelInvitations getDuelInvitations;
  final respond_invitation_usecase.RespondToInvitation respondToInvitation;

  DuelInvitationsBloc({
    required this.getDuelInvitations,
    required this.respondToInvitation,
  }) : super(DuelInvitationsInitial()) {
    on<LoadDuelInvitations>(_onLoadDuelInvitations);
    on<RefreshDuelInvitations>(_onRefreshDuelInvitations);
    on<FilterInvitationsByStatus>(_onFilterInvitationsByStatus);
    on<RespondToInvitation>(_onRespondToInvitation);
    on<ClearInvitationFilters>(_onClearInvitationFilters);
  }

  void _onLoadDuelInvitations(LoadDuelInvitations event, Emitter<DuelInvitationsState> emit) async {
    emit(DuelInvitationsLoading());

    final result = await getDuelInvitations(GetDuelInvitationsParams(status: event.status ?? 'pending'));

    result.fold(
      (failure) => emit(DuelInvitationsError(message: failure.message)),
      (invitations) => emit(DuelInvitationsLoaded(
        invitations: invitations,
        activeStatusFilter: event.status,
        hasFilters: event.status != null,
      )),
    );
  }

  void _onRefreshDuelInvitations(RefreshDuelInvitations event, Emitter<DuelInvitationsState> emit) async {
    // Keep current filters if invitations are loaded
    if (state is DuelInvitationsLoaded) {
      final currentState = state as DuelInvitationsLoaded;
      add(LoadDuelInvitations(status: currentState.activeStatusFilter));
    } else {
      add(const LoadDuelInvitations());
    }
  }

  void _onFilterInvitationsByStatus(FilterInvitationsByStatus event, Emitter<DuelInvitationsState> emit) async {
    emit(DuelInvitationsLoading());

    final result = await getDuelInvitations(GetDuelInvitationsParams(status: event.status ?? 'pending'));

    result.fold(
      (failure) => emit(DuelInvitationsError(message: failure.message)),
      (invitations) => emit(DuelInvitationsLoaded(
        invitations: invitations,
        activeStatusFilter: event.status,
        hasFilters: event.status != null,
      )),
    );
  }

  void _onRespondToInvitation(RespondToInvitation event, Emitter<DuelInvitationsState> emit) async {
    emit(InvitationResponding(
      invitationId: event.invitationId,
      response: event.response,
    ));

    final result = await respondToInvitation(respond_invitation_usecase.RespondToInvitationParams(
      invitationId: event.invitationId,
      action: event.response,
    ));

    result.fold(
      (failure) => emit(InvitationResponseError(
        invitationId: event.invitationId,
        message: failure.message,
      )),
      (_) {
        final successMessage = event.response == 'accept' 
            ? 'Invitation accepted successfully!'
            : 'Invitation declined successfully!';
        
        emit(InvitationResponseSuccess(
          invitationId: event.invitationId,
          response: event.response,
          message: successMessage,
        ));
        
        // Refresh the invitations list to show updated state
        add(RefreshDuelInvitations());
      },
    );
  }

  void _onClearInvitationFilters(ClearInvitationFilters event, Emitter<DuelInvitationsState> emit) async {
    add(const LoadDuelInvitations());
  }
}
