import '../../domain/entities/duel.dart';
import 'duel_participant_model.dart';

class DuelModel extends Duel {
  final int? currentParticipants;
  final int? minParticipants;
  final List<DuelParticipantModel> participants;

  const DuelModel({
    required super.id,
    required super.title,
    super.description,
    required super.challengeType,
    required super.targetValue,
    required super.timeframeHours,
    required super.maxParticipants,
    required super.isPublic,
    required super.status,
    required super.creatorId,
    super.winnerId,
    super.creatorCity,
    super.creatorState,
    super.startsAt,
    super.endsAt,
    required super.createdAt,
    required super.updatedAt,
    this.currentParticipants,
    this.minParticipants,
    this.participants = const [],
  });

  factory DuelModel.fromJson(Map<String, dynamic> json) {
    return DuelModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String,
      challengeType: DuelChallengeType.values.firstWhere(
        (e) => e.name == json['challenge_type'],
      ),
      targetValue: (json['target_value'] as num).toDouble(),
      timeframeHours: json['timeframe_hours'] as int,
      creatorCity: json['creator_city'] as String,
      creatorState: json['creator_state'] as String,
      isPublic: json['is_public'] as bool,
      status: DuelStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      startsAt: json['starts_at'] != null 
          ? DateTime.parse(json['starts_at'] as String) 
          : null,
      endsAt: json['ends_at'] != null 
          ? DateTime.parse(json['ends_at'] as String) 
          : null,
      winnerId: json['winner_id'] as String?,
      description: json['description'] as String?,
      maxParticipants: json['max_participants'] as int,
      currentParticipants: json['current_participants'] as int?,
      minParticipants: json['min_participants'] as int?,
      participants: (json['participants'] as List<dynamic>?)
          ?.map((p) => DuelParticipantModel.fromJson(p as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creator_id': creatorId,
      'title': title,
      'challenge_type': challengeType.name,
      'target_value': targetValue,
      'timeframe_hours': timeframeHours,
      'creator_city': creatorCity,
      'creator_state': creatorState,
      'is_public': isPublic,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'starts_at': startsAt?.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'winner_id': winnerId,
      'description': description,
      'max_participants': maxParticipants,
      'current_participants': currentParticipants,
      'min_participants': minParticipants,
      'participants': participants.map((p) => p.toJson()).toList(),
    };
  }

  @override
  DuelModel copyWith({
    String? id,
    String? creatorId,
    String? title,
    DuelChallengeType? challengeType,
    double? targetValue,
    int? timeframeHours,
    String? creatorCity,
    String? creatorState,
    bool? isPublic,
    DuelStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startsAt,
    DateTime? endsAt,
    String? winnerId,
    String? description,
    int? maxParticipants,
    int? currentParticipants,
    int? minParticipants,
    List<DuelParticipantModel>? participants,
  }) {
    return DuelModel(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      title: title ?? this.title,
      challengeType: challengeType ?? this.challengeType,
      targetValue: targetValue ?? this.targetValue,
      timeframeHours: timeframeHours ?? this.timeframeHours,
      creatorCity: creatorCity ?? this.creatorCity,
      creatorState: creatorState ?? this.creatorState,
      isPublic: isPublic ?? this.isPublic,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      winnerId: winnerId ?? this.winnerId,
      description: description ?? this.description,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentParticipants: currentParticipants ?? this.currentParticipants,
      minParticipants: minParticipants ?? this.minParticipants,
      participants: participants ?? this.participants,
    );
  }

  String get targetValueWithUnit {
    switch (challengeType) {
      case DuelChallengeType.distance:
        return '${targetValue.toStringAsFixed(1)} km';
      case DuelChallengeType.time:
        return '${(targetValue ~/ 60)} hours';
      case DuelChallengeType.elevation:
        return '${targetValue.toStringAsFixed(0)} m';
      case DuelChallengeType.powerPoints:
        return '${targetValue.toStringAsFixed(0)} pts';
    }
  }

  @override
  List<Object?> get props => [
        id,
        creatorId,
        title,
        challengeType,
        targetValue,
        timeframeHours,
        creatorCity,
        creatorState,
        isPublic,
        status,
        createdAt,
        updatedAt,
        startsAt,
        endsAt,
        winnerId,
        description,
        maxParticipants,
        currentParticipants,
        minParticipants,
        participants,
      ];
}
