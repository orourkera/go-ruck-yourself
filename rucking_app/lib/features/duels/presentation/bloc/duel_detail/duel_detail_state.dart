import 'package:equatable/equatable.dart';
import '../../../domain/entities/duel.dart';
import '../../../domain/entities/duel_participant.dart';
import '../../../domain/entities/duel_comment.dart';

abstract class DuelDetailState extends Equatable {
  const DuelDetailState();

  @override
  List<Object?> get props => [];
}

class DuelDetailInitial extends DuelDetailState {}

class DuelDetailLoading extends DuelDetailState {}

class DuelDetailLoaded extends DuelDetailState {
  final Duel duel;
  final List<DuelParticipant> leaderboard;
  final bool isLeaderboardLoading;
  final List<DuelComment> comments;

  const DuelDetailLoaded({
    required this.duel,
    this.leaderboard = const [],
    this.isLeaderboardLoading = false,
    this.comments = const [],
  });

  DuelDetailLoaded copyWith({
    Duel? duel,
    List<DuelParticipant>? leaderboard,
    bool? isLeaderboardLoading,
    List<DuelComment>? comments,
  }) {
    return DuelDetailLoaded(
      duel: duel ?? this.duel,
      leaderboard: leaderboard ?? this.leaderboard,
      isLeaderboardLoading: isLeaderboardLoading ?? this.isLeaderboardLoading,
      comments: comments ?? this.comments,
    );
  }

  @override
  List<Object?> get props => [duel, leaderboard, isLeaderboardLoading, comments];
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
