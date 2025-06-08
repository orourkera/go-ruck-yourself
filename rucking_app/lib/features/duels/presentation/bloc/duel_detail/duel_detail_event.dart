import 'package:equatable/equatable.dart';

abstract class DuelDetailEvent extends Equatable {
  const DuelDetailEvent();

  @override
  List<Object?> get props => [];
}

class LoadDuelDetail extends DuelDetailEvent {
  final String duelId;

  const LoadDuelDetail({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class RefreshDuelDetail extends DuelDetailEvent {
  final String duelId;

  const RefreshDuelDetail({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class JoinDuelFromDetail extends DuelDetailEvent {
  final String duelId;

  const JoinDuelFromDetail({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class LoadLeaderboard extends DuelDetailEvent {
  final String duelId;

  const LoadLeaderboard({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class UpdateDuelProgress extends DuelDetailEvent {
  final String duelId;
  final String participantId;
  final String sessionId;
  final double contributionValue;

  const UpdateDuelProgress({
    required this.duelId,
    required this.participantId,
    required this.sessionId,
    required this.contributionValue,
  });

  @override
  List<Object> get props => [duelId, participantId, sessionId, contributionValue];
}

class StartDuelManually extends DuelDetailEvent {
  final String duelId;

  const StartDuelManually({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

// Comment-related events
class LoadDuelComments extends DuelDetailEvent {
  final String duelId;

  const LoadDuelComments({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

// Session-related events
class LoadDuelSessions extends DuelDetailEvent {
  final String duelId;

  const LoadDuelSessions({required this.duelId});

  @override
  List<Object> get props => [duelId];
}

class AddDuelComment extends DuelDetailEvent {
  final String duelId;
  final String content;

  const AddDuelComment({
    required this.duelId,
    required this.content,
  });

  @override
  List<Object> get props => [duelId, content];
}

class UpdateDuelComment extends DuelDetailEvent {
  final String commentId;
  final String content;

  const UpdateDuelComment({
    required this.commentId,
    required this.content,
  });

  @override
  List<Object> get props => [commentId, content];
}

class DeleteDuelComment extends DuelDetailEvent {
  final String commentId;

  const DeleteDuelComment({required this.commentId});

  @override
  List<Object> get props => [commentId];
}
