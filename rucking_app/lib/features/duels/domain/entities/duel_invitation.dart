import 'package:equatable/equatable.dart';

enum DuelInvitationStatus {
  pending,
  accepted,
  declined,
  expired,
  cancelled,
}

class DuelInvitation extends Equatable {
  final String id;
  final String duelId;
  final String inviterId;
  final String inviteeEmail;
  final DuelInvitationStatus status;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Duel information (from API join)
  final String? duelTitle;
  final String? challengeType;
  final double? targetValue;
  final int? timeframeHours;
  final String? creatorCity;
  final String? creatorState;
  final String? inviterUsername;

  const DuelInvitation({
    required this.id,
    required this.duelId,
    required this.inviterId,
    required this.inviteeEmail,
    required this.status,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.duelTitle,
    this.challengeType,
    this.targetValue,
    this.timeframeHours,
    this.creatorCity,
    this.creatorState,
    this.inviterUsername,
  });

  // Utility getters
  bool get isPending => status == DuelInvitationStatus.pending;
  bool get isAccepted => status == DuelInvitationStatus.accepted;
  bool get isDeclined => status == DuelInvitationStatus.declined;
  bool get isExpired => status == DuelInvitationStatus.expired;
  bool get isCancelled => status == DuelInvitationStatus.cancelled;

  bool get canRespond => isPending && !hasExpired;
  bool get canCancel => isPending;

  bool get hasExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Duration? get timeUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now();
    if (now.isAfter(expiresAt!)) return Duration.zero;
    return expiresAt!.difference(now);
  }

  String get statusDisplayName {
    switch (status) {
      case DuelInvitationStatus.pending:
        return 'Pending';
      case DuelInvitationStatus.accepted:
        return 'Accepted';
      case DuelInvitationStatus.declined:
        return 'Declined';
      case DuelInvitationStatus.expired:
        return 'Expired';
      case DuelInvitationStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get locationString {
    if (creatorCity != null && creatorState != null) {
      return '$creatorCity, $creatorState';
    } else if (creatorCity != null) {
      return creatorCity!;
    } else if (creatorState != null) {
      return creatorState!;
    }
    return 'Unknown location';
  }

  String? get challengeTypeDisplay {
    if (challengeType == null) return null;
    switch (challengeType!) {
      case 'distance':
        return 'Distance';
      case 'time':
        return 'Time';
      case 'elevation':
        return 'Elevation';
      case 'power_points':
        return 'Power Points';
      default:
        return challengeType;
    }
  }

  String? get targetValueDisplay {
    if (targetValue == null || challengeType == null) return null;

    String unit;
    switch (challengeType!) {
      case 'distance':
        unit = 'miles';
        break;
      case 'time':
        unit = 'minutes';
        break;
      case 'elevation':
        unit = 'feet';
        break;
      case 'power_points':
        unit = 'points';
        break;
      default:
        unit = '';
    }

    return '${targetValue!.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 1)} $unit';
  }

  DuelInvitation copyWith({
    String? id,
    String? duelId,
    String? inviterId,
    String? inviteeEmail,
    DuelInvitationStatus? status,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? duelTitle,
    String? challengeType,
    double? targetValue,
    int? timeframeHours,
    String? creatorCity,
    String? creatorState,
    String? inviterUsername,
  }) {
    return DuelInvitation(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      inviterId: inviterId ?? this.inviterId,
      inviteeEmail: inviteeEmail ?? this.inviteeEmail,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      duelTitle: duelTitle ?? this.duelTitle,
      challengeType: challengeType ?? this.challengeType,
      targetValue: targetValue ?? this.targetValue,
      timeframeHours: timeframeHours ?? this.timeframeHours,
      creatorCity: creatorCity ?? this.creatorCity,
      creatorState: creatorState ?? this.creatorState,
      inviterUsername: inviterUsername ?? this.inviterUsername,
    );
  }

  @override
  List<Object?> get props => [
        id,
        duelId,
        inviterId,
        inviteeEmail,
        status,
        expiresAt,
        createdAt,
        updatedAt,
        duelTitle,
        challengeType,
        targetValue,
        timeframeHours,
        creatorCity,
        creatorState,
        inviterUsername,
      ];
}
