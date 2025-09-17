import 'package:equatable/equatable.dart';

/// Model representing a like on a ruck session
class RuckLike extends Equatable {
  /// Unique ID of the like record
  final String id;

  /// ID of the ruck session that was liked
  final int ruckId;

  /// ID of the user who liked the ruck session
  final String userId;

  /// Display name of the user who liked the ruck session
  final String userDisplayName;

  /// Optional user avatar URL
  final String? userAvatarUrl;

  /// Timestamp when the like was created
  final DateTime createdAt;

  /// Creates a new RuckLike instance
  const RuckLike({
    required this.id,
    required this.ruckId,
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, ruckId, userId, createdAt];

  /// Creates a RuckLike from a JSON map
  factory RuckLike.fromJson(Map<String, dynamic> json) {
    // Gracefully handle ruck_id that may arrive as String or null
    int parsedRuckId;
    final rawRuckId = json['ruck_id'];
    if (rawRuckId is int) {
      parsedRuckId = rawRuckId;
    } else if (rawRuckId is String) {
      parsedRuckId = int.tryParse(rawRuckId) ?? 0;
    } else {
      parsedRuckId = 0; // fallback value – callers should validate
    }

    return RuckLike(
      id: json['id'] ?? '',
      ruckId: parsedRuckId,
      userId: json['user_id'] ?? '',
      userDisplayName: json['user_display_name'] ?? 'Anonymous',
      userAvatarUrl: json['user_avatar_url'],
      createdAt: (DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now()).toUtc(),
    );
  }

  /// Converts a RuckLike to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ruck_id': ruckId,
      'user_id': userId,
      'user_display_name': userDisplayName,
      'user_avatar_url': userAvatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Creates a copy of this RuckLike with the given fields replaced
  RuckLike copyWith({
    String? id,
    int? ruckId,
    String? userId,
    String? userDisplayName,
    String? userAvatarUrl,
    DateTime? createdAt,
  }) {
    return RuckLike(
      id: id ?? this.id,
      ruckId: ruckId ?? this.ruckId,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
