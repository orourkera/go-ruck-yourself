import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel.dart';
import '../../../domain/entities/duel_participant.dart';
import '../../../domain/entities/duel_comment.dart';
import '../../../domain/entities/duel_session.dart';

abstract class DuelDetailState extends Equatable {
  const DuelDetailState();

  @override
  List<Object?> get props => [];
}

class DuelDetailInitial extends DuelDetailState {}

class DuelDetailLoading extends DuelDetailState {}

class DuelDetailLoaded extends DuelDetailState {
  final Duel duel;
  final List<DuelParticipant> participants;
  final List<DuelParticipant> leaderboard;
  final bool isLeaderboardLoading;
  final List<DuelComment> comments;
  final bool canViewComments;
  final List<DuelSession> sessions;
  final bool isSessionsLoading;

  const DuelDetailLoaded({
    required this.duel,
    this.participants = const [],
    this.leaderboard = const [],
    this.isLeaderboardLoading = false,
    this.comments = const [],
    this.canViewComments = true,
    this.sessions = const [],
    this.isSessionsLoading = false,
  });

  DuelDetailLoaded copyWith({
    Duel? duel,
    List<DuelParticipant>? participants,
    List<DuelParticipant>? leaderboard,
    bool? isLeaderboardLoading,
    List<DuelComment>? comments,
    bool? canViewComments,
    List<DuelSession>? sessions,
    bool? isSessionsLoading,
  }) {
    return DuelDetailLoaded(
      duel: duel ?? this.duel,
      participants: participants ?? this.participants,
      leaderboard: leaderboard ?? this.leaderboard,
      isLeaderboardLoading: isLeaderboardLoading ?? this.isLeaderboardLoading,
      comments: comments ?? this.comments,
      canViewComments: canViewComments ?? this.canViewComments,
      sessions: sessions ?? this.sessions,
      isSessionsLoading: isSessionsLoading ?? this.isSessionsLoading,
    );
  }

  @override
  List<Object?> get props => [duel, participants, leaderboard, isLeaderboardLoading, comments, canViewComments, sessions, isSessionsLoading];
}

class DuelDetailError extends DuelDetailState {
  final String message;

  const DuelDetailError({required this.message});

  @override
  List<Object> get props => [message];
}

class DuelJoiningFromDetail extends DuelDetailState {
  final String duelId;

  const DuelJoiningFromDetail({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelJoinedFromDetail extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelJoinedFromDetail({
    required this.duelId,
    this.message = 'Successfully joined duel!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelJoinErrorFromDetail extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelJoinErrorFromDetail({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelProgressUpdating extends DuelDetailState {
  final String duelId;

  const DuelProgressUpdating({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelProgressUpdated extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelProgressUpdated({
    required this.duelId,
    this.message = 'Progress updated successfully!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelProgressUpdateError extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelProgressUpdateError({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelStartingManually extends DuelDetailState {
  final String duelId;

  const DuelStartingManually({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelStartedManually extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelStartedManually({
    required this.duelId,
    this.message = 'Duel started successfully!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelStartError extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelStartError({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelWithdrawing extends DuelDetailState {
  final String duelId;

  const DuelWithdrawing({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelWithdrawn extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelWithdrawn({
    required this.duelId,
    this.message = 'Successfully withdrawn from duel!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelWithdrawError extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelWithdrawError({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelDeleting extends DuelDetailState {
  final String duelId;

  const DuelDeleting({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class DuelDeleted extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelDeleted({
    required this.duelId,
    this.message = 'Duel deleted successfully!',
  });

  @override
  List<Object> get props => [duelId, message];
}

class DuelDeleteError extends DuelDetailState {
  final String duelId;
  final String message;

  const DuelDeleteError({
    required this.duelId,
    required this.message,
  });

  @override
  List<Object> get props => [duelId, message];
}
