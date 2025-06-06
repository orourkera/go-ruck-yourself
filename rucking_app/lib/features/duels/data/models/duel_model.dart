import '../../domain/entities/duel.dart';
import 'duel_participant_model.dart';

class DuelModel extends Duel {
  final int? currentParticipants;
  final List<DuelParticipantModel> participants;

  DuelModel({
    required String id,
    required String title,
    String? description,
    required DuelChallengeType challengeType,
    required double targetValue,
    required int timeframeHours,
    required int maxParticipants,
    required bool isPublic,
    required DuelStatus status,
    required String creatorId,
    String? winnerId,
    String? creatorCity,
    String? creatorState,
    DateTime? startsAt,
    DateTime? endsAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DuelStartMode startMode = DuelStartMode.auto,
    this.currentParticipants,
    int minParticipants = 2,
    this.participants = const [],
  }) : super(
    id: id,
    title: title,
    description: description,
    challengeType: challengeType,
    targetValue: targetValue,
    timeframeHours: timeframeHours,
    maxParticipants: maxParticipants,
    isPublic: isPublic,
    status: status,
    creatorId: creatorId,
    winnerId: winnerId,
    creatorCity: creatorCity,
    creatorState: creatorState,
    startsAt: startsAt,
    endsAt: endsAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    minParticipants: minParticipants,
    startMode: startMode
  );

  factory DuelModel.fromJson(Map<String, dynamic> json) {
    try {
      // Parse start mode from string or default to auto
      DuelStartMode startMode = DuelStartMode.auto;
      if (json['start_mode'] != null) {
        final startModeStr = json['start_mode'].toString();
        if (startModeStr == 'manual') {
          startMode = DuelStartMode.manual;
        }
      }

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
        minParticipants: json['min_participants'] as int? ?? 2,
        participants: (json['participants'] as List<dynamic>?)
            ?.map((p) => DuelParticipantModel.fromJson(p as Map<String, dynamic>))
            .toList() ?? [],
        startMode: startMode,
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
      'start_mode': startMode.name,
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
    DuelStartMode? startMode,
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
      minParticipants: minParticipants ?? super.minParticipants,
      startMode: startMode ?? super.startMode,
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
