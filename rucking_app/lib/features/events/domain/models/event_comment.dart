import 'package:equatable/equatable.dart';

class EventComment extends Equatable {
  final String id;
  final String eventId;
  final String userId;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final EventCommentUser? user;

  const EventComment({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.user,
  });

  factory EventComment.fromJson(Map<String, dynamic> json) {
    return EventComment(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      userId: json['user_id'] as String,
      comment: json['comment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      user: json['user'] != null
          ? EventCommentUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'user_id': userId,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'user': user?.toJson(),
    };
  }

  bool get isEdited => createdAt != updatedAt;

  @override
  List<Object?> get props => [
        id,
        eventId,
        userId,
        comment,
        createdAt,
        updatedAt,
        user,
      ];
}

class EventCommentUser extends Equatable {
  final String id;
  final String username;
  final String avatarUrl;

  const EventCommentUser({
    required this.id,
    required this.username,
    required this.avatarUrl,
  });

  factory EventCommentUser.fromJson(Map<String, dynamic> json) {
    return EventCommentUser(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
    };
  }

  @override
  List<Object?> get props => [id, username, avatarUrl];
}
