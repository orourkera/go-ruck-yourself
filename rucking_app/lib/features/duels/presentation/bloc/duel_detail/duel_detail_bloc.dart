import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_duel_details.dart';
import '../../../domain/usecases/get_duel_leaderboard.dart';
import '../../../domain/usecases/join_duel.dart' as join_duel_usecase;
import '../../../domain/usecases/update_duel_progress.dart' as update_progress_usecase;
import '../../../domain/usecases/get_duel_comments.dart';
import '../../../domain/usecases/add_duel_comment.dart' as add_comment_usecase;
import '../../../domain/usecases/update_duel_comment.dart' as update_comment_usecase;
import '../../../domain/usecases/delete_duel_comment.dart' as delete_comment_usecase;
import '../../../domain/usecases/start_duel.dart' as start_duel_usecase;
import '../../../domain/usecases/get_duel_sessions.dart';
import '../../../domain/usecases/withdraw_from_duel.dart' as withdraw_usecase;
import '../../../domain/usecases/delete_duel.dart' as delete_duel_usecase;
import '../../../domain/entities/duel_participant.dart';
import '../../../data/models/duel_model.dart';
import 'duel_detail_event.dart';
import 'duel_detail_state.dart';
import 'package:rucking_app/core/services/duel_completion_service.dart';
import 'package:rucking_app/core/services/service_locator.dart';

class DuelDetailBloc extends Bloc<DuelDetailEvent, DuelDetailState> {
  final GetDuelDetails getDuelDetails;
  final GetDuelLeaderboard getDuelLeaderboard;
  final join_duel_usecase.JoinDuel joinDuel;
  final update_progress_usecase.UpdateDuelProgress updateDuelProgress;
  final GetDuelComments getDuelComments;
  final add_comment_usecase.AddDuelComment addDuelComment;
  final update_comment_usecase.UpdateDuelComment updateDuelComment;
  final delete_comment_usecase.DeleteDuelComment deleteDuelComment;
  final start_duel_usecase.StartDuel startDuel;
  final GetDuelSessions getDuelSessions;
  final withdraw_usecase.WithdrawFromDuel withdrawFromDuel;
  final delete_duel_usecase.DeleteDuel deleteDuel;

  DuelDetailBloc({
    required this.getDuelDetails,
    required this.getDuelLeaderboard,
    required this.joinDuel,
    required this.updateDuelProgress,
    required this.getDuelComments,
    required this.addDuelComment,
    required this.updateDuelComment,
    required this.deleteDuelComment,
    required this.startDuel,
    required this.getDuelSessions,
    required this.withdrawFromDuel,
    required this.deleteDuel,
  }) : super(DuelDetailInitial()) {
    on<LoadDuelDetail>(_onLoadDuelDetail);
    on<RefreshDuelDetail>(_onRefreshDuelDetail);
    on<JoinDuelFromDetail>(_onJoinDuelFromDetail);
    on<LoadLeaderboard>(_onLoadLeaderboard);
    on<UpdateDuelProgress>(_onUpdateDuelProgress);
    on<StartDuelManually>(_onStartDuelManually);
    on<LoadDuelComments>(_onLoadDuelComments);
    on<AddDuelComment>(_onAddDuelComment);
    on<UpdateDuelComment>(_onUpdateDuelComment);
    on<DeleteDuelComment>(_onDeleteDuelComment);
    on<LoadDuelSessions>(_onLoadDuelSessions);
    on<WithdrawFromDuel>(_onWithdrawFromDuel);
    on<DeleteDuel>(_onDeleteDuel);
  }

  void _onLoadDuelDetail(LoadDuelDetail event, Emitter<DuelDetailState> emit) async {
    emit(DuelDetailLoading());
    
    final result = await getDuelDetails(GetDuelDetailsParams(duelId: event.duelId));

    result.fold(
      (failure) => emit(DuelDetailError(message: failure.message)),
      (duel) {
        // Extract participants from DuelModel if available
        List<DuelParticipant> participants = [];
        if (duel is DuelModel) {
          participants = duel.participants.cast<DuelParticipant>();
        }
        
        emit(DuelDetailLoaded(
          duel: duel,
          participants: participants,
        ));
        add(LoadLeaderboard(duelId: event.duelId));
        add(LoadDuelComments(duelId: event.duelId));
      },
    );
  }

  void _onRefreshDuelDetail(RefreshDuelDetail event, Emitter<DuelDetailState> emit) async {
    // If we're already loaded, just refresh the data without showing loading
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      
      final result = await getDuelDetails(GetDuelDetailsParams(duelId: event.duelId));

      result.fold(
        (failure) => emit(DuelDetailError(message: failure.message)),
        (duel) {
          // Extract participants from DuelModel if available
          List<DuelParticipant> participants = [];
          if (duel is DuelModel) {
            participants = duel.participants.cast<DuelParticipant>();
          }
          
          emit(currentState.copyWith(duel: duel, participants: participants));
          // Refresh leaderboard too
          add(LoadLeaderboard(duelId: event.duelId));
        },
      );
    } else {
      add(LoadDuelDetail(duelId: event.duelId));
    }
  }

  void _onJoinDuelFromDetail(JoinDuelFromDetail event, Emitter<DuelDetailState> emit) async {
    emit(DuelJoiningFromDetail(duelId: event.duelId));

    final result = await joinDuel(join_duel_usecase.JoinDuelParams(duelId: event.duelId));

    result.fold(
      (failure) => emit(DuelJoinErrorFromDetail(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelJoinedFromDetail(duelId: event.duelId));
        // Refresh the duel details to show updated participant list
        add(RefreshDuelDetail(duelId: event.duelId));
      },
    );
  }

  void _onStartDuelManually(StartDuelManually event, Emitter<DuelDetailState> emit) async {
    emit(DuelStartingManually(duelId: event.duelId));

    final result = await startDuel(start_duel_usecase.StartDuelParams(
      duelId: event.duelId,
    ));

    result.fold(
      (failure) => emit(DuelStartError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelStartedManually(duelId: event.duelId));
        // Refresh the duel details to show updated status
        add(RefreshDuelDetail(duelId: event.duelId));
      },
    );
  }

  void _onLoadLeaderboard(LoadLeaderboard event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      emit(currentState.copyWith(isLeaderboardLoading: true));

      final result = await getDuelLeaderboard(GetDuelLeaderboardParams(duelId: event.duelId));

      result.fold(
        (failure) {
          // Don't emit error for leaderboard failure, just stop loading
          emit(currentState.copyWith(isLeaderboardLoading: false));
        },
        (leaderboard) {
          emit(currentState.copyWith(
            leaderboard: leaderboard,
            isLeaderboardLoading: false,
          ));
        },
      );
    }
  }

  void _onUpdateDuelProgress(UpdateDuelProgress event, Emitter<DuelDetailState> emit) async {
    emit(DuelProgressUpdating(duelId: event.duelId));

    final result = await updateDuelProgress(update_progress_usecase.UpdateDuelProgressParams(
      duelId: event.duelId,
      participantId: event.participantId,
      sessionId: event.sessionId,
      contributionValue: event.contributionValue,
    ));

    result.fold(
      (failure) => emit(DuelProgressUpdateError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelProgressUpdated(duelId: event.duelId));
        // Refresh the duel details and leaderboard to show updated progress
        add(RefreshDuelDetail(duelId: event.duelId));
        
        // Check if this progress update should trigger duel completion
        try {
          final duelCompletionService = getIt<DuelCompletionService>();
          duelCompletionService.checkDuelCompletion(event.duelId);
        } catch (e) {
          // Log error but don't fail the progress update
          print('Failed to check duel completion: $e');
        }
      },
    );
  }

  void _onLoadDuelComments(LoadDuelComments event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;

      final result = await getDuelComments(GetDuelCommentsParams(duelId: event.duelId));

      result.fold(
        (failure) {
          // Check if the failure is due to permission issues (user not being a participant)
          if (failure.message.contains('must be a participant') || 
              failure.message.contains('participant to view comments') ||
              failure.message.contains('403') ||
              failure.message.contains('Forbidden')) {
            // Handle permission error gracefully - don't emit error state
            emit(currentState.copyWith(canViewComments: false, comments: []));
          } else {
            // For other errors, emit error state
            emit(DuelDetailError(message: failure.message));
          }
        },
        (comments) {
          emit(currentState.copyWith(comments: comments, canViewComments: true));
        },
      );
    }
  }

  void _onAddDuelComment(AddDuelComment event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;

      final result = await addDuelComment(add_comment_usecase.AddDuelCommentParams(
        duelId: event.duelId,
        content: event.content,
      ));

      result.fold(
        (failure) => emit(DuelDetailError(message: failure.message)),
        (_) {
          // Refresh comments
          add(LoadDuelComments(duelId: event.duelId));
        },
      );
    }
  }

  void _onUpdateDuelComment(UpdateDuelComment event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      final result = await updateDuelComment(update_comment_usecase.UpdateDuelCommentParams(
        duelId: currentState.duel.id,
        commentId: event.commentId,
        content: event.content,
      ));

      result.fold(
        (failure) => emit(DuelDetailError(message: failure.message)),
        (_) {
          // Need duelId to refresh comments - get it from current state
          add(LoadDuelComments(duelId: currentState.duel.id));
        },
      );
    }
  }

  void _onDeleteDuelComment(DeleteDuelComment event, Emitter<DuelDetailState> emit) async {
    if (state is DuelDetailLoaded) {
      final currentState = state as DuelDetailLoaded;
      
      final result = await deleteDuelComment(delete_comment_usecase.DeleteDuelCommentParams(
        duelId: currentState.duel.id,
        commentId: event.commentId,
      ));

      result.fold(
        (failure) => emit(DuelDetailError(message: failure.message)),
        (_) {
          // Emit success state for user feedback
          emit(DuelCommentDeleted(commentId: event.commentId));
          
          // Refresh comments to sync with server
          add(LoadDuelComments(duelId: currentState.duel.id));
        },
      );
    }
  }

  void _onLoadDuelSessions(LoadDuelSessions event, Emitter<DuelDetailState> emit) async {
    // TO DO: implement _onLoadDuelSessions
  }

  void _onWithdrawFromDuel(WithdrawFromDuel event, Emitter<DuelDetailState> emit) async {
    emit(DuelWithdrawing(duelId: event.duelId));

    final result = await withdrawFromDuel(withdraw_usecase.WithdrawFromDuelParams(
      duelId: event.duelId,
    ));

    result.fold(
      (failure) => emit(DuelWithdrawError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelWithdrawn(duelId: event.duelId));
        // Don't refresh duel details after withdrawal since user will be navigated away
      },
    );
  }

  void _onDeleteDuel(DeleteDuel event, Emitter<DuelDetailState> emit) async {
    emit(DuelDeleting(duelId: event.duelId));

    final result = await deleteDuel(delete_duel_usecase.DeleteDuelParams(
      duelId: event.duelId,
    ));

    result.fold(
      (failure) => emit(DuelDeleteError(
        duelId: event.duelId,
        message: failure.message,
      )),
      (_) {
        emit(DuelDeleted(duelId: event.duelId));
      },
    );
  }
}
