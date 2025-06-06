import '../../domain/entities/duel_comment.dart';

class DuelCommentModel extends DuelComment {
  const DuelCommentModel({
    required super.id,
    required super.duelId,
    required super.userId,
    required super.userDisplayName,
    super.userAvatarUrl,
    required super.content,
    required super.createdAt,
    required super.updatedAt,
  });

  factory DuelCommentModel.fromJson(Map<String, dynamic> json) {
    return DuelCommentModel(
      id: json['id'] as String,
      duelId: json['duel_id'] as String,
      userId: json['user_id'] as String,
      userDisplayName: json['user_display_name'] as String,
      userAvatarUrl: json['user_avatar_url'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

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

  factory DuelCommentModel.fromEntity(DuelComment comment) {
    return DuelCommentModel(
      id: comment.id,
      duelId: comment.duelId,
      userId: comment.userId,
      userDisplayName: comment.userDisplayName,
      userAvatarUrl: comment.userAvatarUrl,
      content: comment.content,
      createdAt: comment.createdAt,
      updatedAt: comment.updatedAt,
    );
  }
}
