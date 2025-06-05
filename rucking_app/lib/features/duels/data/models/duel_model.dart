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
    try {
      return DuelModel(
        id: json['id']?.toString() ?? '',
        creatorId: json['creator_id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Unknown Title',
        challengeType: _parseChallengeType(json['challenge_type']?.toString() ?? 'distance'),
        targetValue: (json['target_value'] as num?)?.toDouble() ?? 0.0,
        timeframeHours: json['timeframe_hours'] as int? ?? 24,
        creatorCity: json['creator_city']?.toString(),
        creatorState: json['creator_state']?.toString(),
        isPublic: json['is_public'] as bool? ?? true,
        status: _parseStatus(json['status']?.toString() ?? 'pending'),
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : DateTime.now(),
        startsAt: json['starts_at'] != null 
            ? DateTime.parse(json['starts_at'] as String) 
            : null,
        endsAt: json['ends_at'] != null 
            ? DateTime.parse(json['ends_at'] as String) 
            : null,
        winnerId: json['winner_id']?.toString(),
        description: json['description']?.toString(),
        maxParticipants: json['max_participants'] as int? ?? 2,
        currentParticipants: json['current_participants'] as int?,
        minParticipants: json['min_participants'] as int?,
        participants: (json['participants'] as List<dynamic>?)
            ?.map((p) => DuelParticipantModel.fromJson(p as Map<String, dynamic>))
            .toList() ?? [],
      );
    } catch (e, stackTrace) {
      print('[ERROR] DuelModel.fromJson failed: $e');
      print('[ERROR] JSON data: $json');
      print('[ERROR] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static DuelChallengeType _parseChallengeType(String challengeType) {
    // Handle both backend format (power_points) and frontend format (powerPoints)
    switch (challengeType) {
      case 'distance':
        return DuelChallengeType.distance;
      case 'time':
        return DuelChallengeType.time;
      case 'elevation':
        return DuelChallengeType.elevation;
      case 'power_points':
      case 'powerPoints':
        return DuelChallengeType.powerPoints;
      default:
        throw ArgumentError('Unknown challenge type: $challengeType');
    }
  }

  static DuelStatus _parseStatus(String status) {
    try {
      return DuelStatus.values.firstWhere((e) => e.name == status);
    } catch (e) {
      throw ArgumentError('Unknown duel status: $status');
    }
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
