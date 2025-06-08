import 'package:equatable/equatable.dart';

class DuelSession extends Equatable {
  final String id;
  final String duelId;
  final String participantId;
  final String sessionId;
  final double contributionValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DuelSession({
    required this.id,
    required this.duelId,
    required this.participantId,
    required this.sessionId,
    required this.contributionValue,
    required this.createdAt,
    required this.updatedAt,
  });

  DuelSession copyWith({
    String? id,
    String? duelId,
    String? participantId,
    String? sessionId,
    double? contributionValue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DuelSession(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      participantId: participantId ?? this.participantId,
      sessionId: sessionId ?? this.sessionId,
      contributionValue: contributionValue ?? this.contributionValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    duelId,
    participantId,
    sessionId,
    contributionValue,
    createdAt,
    updatedAt,
  ];
}
