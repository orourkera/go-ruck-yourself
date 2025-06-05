import 'package:equatable/equatable.dart';

class DuelSessionModel extends Equatable {
  final String id;
  final String duelId;
  final String participantId;
  final String sessionId;
  final double contributionValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DuelSessionModel({
    required this.id,
    required this.duelId,
    required this.participantId,
    required this.sessionId,
    required this.contributionValue,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DuelSessionModel.fromJson(Map<String, dynamic> json) {
    return DuelSessionModel(
      id: json['id'] as String,
      duelId: json['duel_id'] as String,
      participantId: json['participant_id'] as String,
      sessionId: json['session_id'] as String,
      contributionValue: (json['contribution_value'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'duel_id': duelId,
      'participant_id': participantId,
      'session_id': sessionId,
      'contribution_value': contributionValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  DuelSessionModel copyWith({
    String? id,
    String? duelId,
    String? participantId,
    String? sessionId,
    double? contributionValue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DuelSessionModel(
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
