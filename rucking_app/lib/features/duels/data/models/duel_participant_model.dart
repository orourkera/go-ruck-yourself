import '../../domain/entities/duel_participant.dart';

class DuelParticipantModel extends DuelParticipant {
  const DuelParticipantModel({
    required super.id,
    required super.duelId,
    required super.userId,
    required super.username,
    super.email,
    super.avatarUrl,
    required super.status,
    required super.currentValue,
    super.lastSessionId,
    super.joinedAt,
    required super.createdAt,
    required super.updatedAt,
    super.rank,
    super.targetReached,
    super.role,
  });

  factory DuelParticipantModel.fromJson(Map<String, dynamic> json) {
    try {
      return DuelParticipantModel(
        id: json['id'] as String,
        duelId: json['duel_id'] as String,
        userId: json['user_id'] as String,
        username: json['username']?.toString() ?? 'Unknown User',
        email: json['email']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        status: DuelParticipantStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DuelParticipantStatus.invited,
        ),
        currentValue: (json['current_value'] as num).toDouble(),
        lastSessionId: json['_session_id'] as String?,
        joinedAt: json['joined_at'] != null
            ? DateTime.parse(json['joined_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        rank: json['rank'] as int?,
        targetReached: json['target_reached'] as bool?,
        role: json['role']?.toString(),
      );
    } catch (e, stackTrace) {
      print('[ERROR] DuelParticipantModel.fromJson failed: $e');
      print('[ERROR] JSON data: $json');
      print('[ERROR] Stack trace: $stackTrace');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'duel_id': duelId,
      'user_id': userId,
      'username': username,
      'email': email,
      'avatar_url': avatarUrl,
      'status': status.name,
      'current_value': currentValue,
      '_session_id': lastSessionId,
      'joined_at': joinedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'rank': rank,
      'target_reached': targetReached,
      'role': role,
    };
  }

  @override
  DuelParticipantModel copyWith({
    String? id,
    String? duelId,
    String? userId,
    String? username,
    String? email,
    String? avatarUrl,
    DuelParticipantStatus? status,
    double? currentValue,
    String? lastSessionId,
    DateTime? joinedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? rank,
    bool? targetReached,
    String? role,
  }) {
    return DuelParticipantModel(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      currentValue: currentValue ?? this.currentValue,
      lastSessionId: lastSessionId ?? this.lastSessionId,
      joinedAt: joinedAt ?? this.joinedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rank: rank ?? this.rank,
      targetReached: targetReached ?? this.targetReached,
      role: role ?? this.role,
    );
  }

  String get displayName => username;

  @override
  List<Object?> get props => [
        id,
        duelId,
        userId,
        username,
        email,
        avatarUrl,
        status,
        currentValue,
        lastSessionId,
        joinedAt,
        createdAt,
        updatedAt,
        rank,
        targetReached,
        role,
      ];
}
