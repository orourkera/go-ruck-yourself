import 'package:equatable/equatable.dart';

enum DuelChallengeType {
  distance,
  time,
  elevation,
  powerPoints,
}

enum DuelStatus {
  pending,
  active,
  completed,
  cancelled,
}

class Duel extends Equatable {
  final String id;
  final String title;
  final String? description;
  final DuelChallengeType challengeType;
  final double targetValue;
  final int timeframeHours;
  final int maxParticipants;
  final bool isPublic;
  final DuelStatus status;
  final String creatorId;
  final String? winnerId;
  final String? creatorCity;
  final String? creatorState;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Duel({
    required this.id,
    required this.title,
    this.description,
    required this.challengeType,
    required this.targetValue,
    required this.timeframeHours,
    required this.maxParticipants,
    required this.isPublic,
    required this.status,
    required this.creatorId,
    this.winnerId,
    this.creatorCity,
    this.creatorState,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // Utility getters
  bool get isActive => status == DuelStatus.active;
  bool get isCompleted => status == DuelStatus.completed;
  bool get isPending => status == DuelStatus.pending;
  bool get hasEnded => endsAt != null && DateTime.now().isAfter(endsAt!);
  bool get hasStarted => startsAt != null && DateTime.now().isAfter(startsAt!);

  Duration? get timeRemaining {
    if (endsAt == null) return null;
    final now = DateTime.now();
    if (now.isAfter(endsAt!)) return Duration.zero;
    return endsAt!.difference(now);
  }

  String get challengeTypeDisplayName {
    switch (challengeType) {
      case DuelChallengeType.distance:
        return 'Distance';
      case DuelChallengeType.time:
        return 'Time';
      case DuelChallengeType.elevation:
        return 'Elevation';
      case DuelChallengeType.powerPoints:
        return 'Power Points';
    }
  }

  String get challengeTypeUnit {
    switch (challengeType) {
      case DuelChallengeType.distance:
        return 'miles';
      case DuelChallengeType.time:
        return 'minutes';
      case DuelChallengeType.elevation:
        return 'feet';
      case DuelChallengeType.powerPoints:
        return 'points';
    }
  }

  String get statusDisplayName {
    switch (status) {
      case DuelStatus.pending:
        return 'Pending';
      case DuelStatus.active:
        return 'Active';
      case DuelStatus.completed:
        return 'Completed';
      case DuelStatus.cancelled:
        return 'Cancelled';
    }
  }

  Duel copyWith({
    String? id,
    String? title,
    String? description,
    DuelChallengeType? challengeType,
    double? targetValue,
    int? timeframeHours,
    int? maxParticipants,
    bool? isPublic,
    DuelStatus? status,
    String? creatorId,
    String? winnerId,
    String? creatorCity,
    String? creatorState,
    DateTime? startsAt,
    DateTime? endsAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Duel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      challengeType: challengeType ?? this.challengeType,
      targetValue: targetValue ?? this.targetValue,
      timeframeHours: timeframeHours ?? this.timeframeHours,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      isPublic: isPublic ?? this.isPublic,
      status: status ?? this.status,
      creatorId: creatorId ?? this.creatorId,
      winnerId: winnerId ?? this.winnerId,
      creatorCity: creatorCity ?? this.creatorCity,
      creatorState: creatorState ?? this.creatorState,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        challengeType,
        targetValue,
        timeframeHours,
        maxParticipants,
        isPublic,
        status,
        creatorId,
        winnerId,
        creatorCity,
        creatorState,
        startsAt,
        endsAt,
        createdAt,
        updatedAt,
      ];
}
