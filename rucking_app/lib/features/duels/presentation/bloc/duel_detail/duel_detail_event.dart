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
