import '../../domain/entities/duel_invitation.dart';

class DuelInvitationModel extends DuelInvitation {
  const DuelInvitationModel({
    required super.id,
    required super.duelId,
    required super.inviterId,
    required super.inviteeEmail,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    super.expiresAt,
    super.duelTitle,
    super.challengeType,
    super.targetValue,
    super.timeframeHours,
    super.creatorCity,
    super.creatorState,
    super.inviterUsername,
  });

  factory DuelInvitationModel.fromJson(Map<String, dynamic> json) {
    return DuelInvitationModel(
      id: json['id'] as String,
      duelId: json['duel_id'] as String,
      inviterId: json['inviter_id'] as String,
      inviteeEmail: json['invitee_email'] as String,
      status: DuelInvitationStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      duelTitle: json['duel_title'] as String?,
      challengeType: json['challenge_type'] as String?,
      targetValue: json['target_value'] != null
          ? (json['target_value'] as num).toDouble()
          : null,
      timeframeHours: json['timeframe_hours'] as int?,
      creatorCity: json['creator_city'] as String?,
      creatorState: json['creator_state'] as String?,
      inviterUsername: json['inviter_username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'duel_id': duelId,
      'inviter_id': inviterId,
      'invitee_email': inviteeEmail,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'duel_title': duelTitle,
      'challenge_type': challengeType,
      'target_value': targetValue,
      'timeframe_hours': timeframeHours,
      'creator_city': creatorCity,
      'creator_state': creatorState,
      'inviter_username': inviterUsername,
    };
  }

  @override
  DuelInvitationModel copyWith({
    String? id,
    String? duelId,
    String? inviterId,
    String? inviteeEmail,
    DuelInvitationStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? duelTitle,
    String? challengeType,
    double? targetValue,
    int? timeframeHours,
    String? creatorCity,
    String? creatorState,
    String? inviterUsername,
  }) {
    return DuelInvitationModel(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      inviterId: inviterId ?? this.inviterId,
      inviteeEmail: inviteeEmail ?? this.inviteeEmail,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      duelTitle: duelTitle ?? this.duelTitle,
      challengeType: challengeType ?? this.challengeType,
      targetValue: targetValue ?? this.targetValue,
      timeframeHours: timeframeHours ?? this.timeframeHours,
      creatorCity: creatorCity ?? this.creatorCity,
      creatorState: creatorState ?? this.creatorState,
      inviterUsername: inviterUsername ?? this.inviterUsername,
    );
  }
}
