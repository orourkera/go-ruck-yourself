import 'package:equatable/equatable.dart';
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
      'inviter_username': inviterUsername,
    };
  }

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
      inviterUsername: inviterUsername ?? this.inviterUsername,
    );
  }

  bool get isPending => status == DuelInvitationStatus.pending;
  bool get isAccepted => status == DuelInvitationStatus.accepted;
  bool get isDeclined => status == DuelInvitationStatus.declined;
  bool get isExpired => status == DuelInvitationStatus.expired;

  bool get hasExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  @override
  List<Object?> get props => [
        id,
        duelId,
        inviterId,
        inviteeEmail,
        status,
        createdAt,
        updatedAt,
        expiresAt,
        duelTitle,
        inviterUsername,
      ];
}
