import 'package:equatable/equatable.dart';
import '../../domain/entities/duel_participant.dart';

class DuelParticipantModel extends DuelParticipant {
  const DuelParticipantModel({
    required super.id,
    required super.duelId,
    required super.userId,
    required super.status,
    required super.currentValue,
    required super.joinedAt,
    required super.createdAt,
    required super.updatedAt,
    super.lastSessionId,
    super.username,
    super.userEmail,
  });

  factory DuelParticipantModel.fromJson(Map<String, dynamic> json) {
    return DuelParticipantModel(
      id: json['id'] as String,
      duelId: json['duel_id'] as String,
      userId: json['user_id'] as String,
      status: DuelParticipantStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      currentValue: (json['current_value'] as num).toDouble(),
      lastSessionId: json['last_session_id'] as String?,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      username: json['username'] as String?,
      userEmail: json['user_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'duel_id': duelId,
      'user_id': userId,
      'status': status.name,
      'current_value': currentValue,
      'last_session_id': lastSessionId,
      'joined_at': joinedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'username': username,
      'user_email': userEmail,
    };
  }

  DuelParticipantModel copyWith({
    String? id,
    String? duelId,
    String? userId,
    DuelParticipantStatus? status,
    double? currentValue,
    String? lastSessionId,
    DateTime? joinedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? username,
    String? userEmail,
  }) {
    return DuelParticipantModel(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      currentValue: currentValue ?? this.currentValue,
      lastSessionId: lastSessionId ?? this.lastSessionId,
      joinedAt: joinedAt ?? this.joinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      username: username ?? this.username,
      userEmail: userEmail ?? this.userEmail,
    );
  }

  bool get isPending => status == DuelParticipantStatus.pending;
  bool get isAccepted => status == DuelParticipantStatus.accepted;
  bool get isDeclined => status == DuelParticipantStatus.declined;

  String get displayName => username ?? userEmail ?? 'Unknown User';

  @override
  List<Object?> get props => [
        id,
        duelId,
        userId,
        status,
        currentValue,
        lastSessionId,
        joinedAt,
        createdAt,
        updatedAt,
        username,
        userEmail,
      ];
}
