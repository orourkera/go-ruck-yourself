import 'package:equatable/equatable.dart';

/// Model representing a comment on a duel
class DuelComment extends Equatable {
  /// Unique ID of the comment
  final String id;
  
  /// ID of the duel that was commented on
  final int duelId;
  
  /// ID of the user who wrote the comment
  final String userId;
  
  /// Display name of the user who wrote the comment
  final String userDisplayName;
  
  /// Optional user avatar URL
  final String? userAvatarUrl;
  
  /// The comment text content
  final String content;
  
  /// Timestamp when the comment was created
  final DateTime createdAt;
  
  /// Optional timestamp when the comment was last edited
  final DateTime? updatedAt;
  
  /// Whether this comment has been edited
  bool get isEdited => updatedAt != null && updatedAt != createdAt;

  /// Creates a new DuelComment instance
  const DuelComment({
    required this.id,
    required this.duelId,
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [id, duelId, userId, content, createdAt, updatedAt];

  /// Creates a DuelComment from a JSON map
  factory DuelComment.fromJson(Map<String, dynamic> json) {
    return DuelComment(
      id: json['id'],
      duelId: json['duel_id'],
      userId: json['user_id'],
      userDisplayName: json['user_display_name'] ?? 'Anonymous',
      userAvatarUrl: json['user_avatar_url'],
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
    );
  }

  /// Converts a DuelComment to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'duel_id': duelId,
      'user_id': userId,
      'user_display_name': userDisplayName,
      'user_avatar_url': userAvatarUrl,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Creates a copy of this DuelComment with the given fields replaced
  DuelComment copyWith({
    String? id,
    int? duelId,
    String? userId,
    String? userDisplayName,
    String? userAvatarUrl,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DuelComment(
      id: id ?? this.id,
      duelId: duelId ?? this.duelId,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
