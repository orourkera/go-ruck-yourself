import 'package:equatable/equatable.dart';

enum DuelParticipantStatus {
  invited,
  accepted,
  declined,
  completed,
}

class DuelParticipant extends Equatable {
  final String id;
  final String duelId;
  final String userId;
  final String username;
  final String? email;
  final DuelParticipantStatus status;
  final double currentValue;
  final String? lastSessionId;
  final DateTime? joinedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? rank;
  final bool? targetReached;

  const DuelParticipant({
    required this.id,
    required this.duelId,
    required this.userId,
    required this.username,
    this.email,
    required this.status,
    required this.currentValue,
    this.lastSessionId,
    this.joinedAt,
    required this.createdAt,
    required this.updatedAt,
    this.rank,
    this.targetReached,
  });

  // Utility getters
  bool get isActive => status == DuelParticipantStatus.accepted;
  bool get hasDeclined => status == DuelParticipantStatus.declined;
  bool get isInvited => status == DuelParticipantStatus.invited;
  bool get hasCompleted => status == DuelParticipantStatus.completed;

  String get statusDisplayName {
    switch (status) {
      case DuelParticipantStatus.invited:
        return 'Invited';
      case DuelParticipantStatus.accepted:
        return 'Participating';
      case DuelParticipantStatus.declined:
        return 'Declined';
      case DuelParticipantStatus.completed:
        return 'Completed';
    }
  }

  double progressPercentage(double targetValue) {
    if (targetValue <= 0) return 0.0;
    return (currentValue / targetValue * 100).clamp(0.0, 100.0);
  }

  DuelParticipant copyWith({
    String? id,
    String? duelId,
    String? userId,
    String? username,
    String? email,
    DuelParticipantStatus? status,
    double? currentValue,
    String? lastSessionId,
    DateTime? joinedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? rank,
    bool? targetReached,
  }) {
    return DuelParticipant(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
      status: status ?? this.status,
      currentValue: currentValue ?? this.currentValue,
      lastSessionId: lastSessionId ?? this.lastSessionId,
      joinedAt: joinedAt ?? this.joinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rank: rank ?? this.rank,
      targetReached: targetReached ?? this.targetReached,
    );
  }

  @override
  List<Object?> get props => [
        id,
        duelId,
        userId,
        username,
        email,
        status,
        currentValue,
        lastSessionId,
        joinedAt,
        createdAt,
        updatedAt,
        rank,
        targetReached,
      ];
}
