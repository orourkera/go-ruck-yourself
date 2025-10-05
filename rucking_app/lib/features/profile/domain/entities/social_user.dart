class SocialUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final bool isFollowing;
  final DateTime followedAt;
  final String? activeRuckId; // ID of currently active ruck (if any)
  final bool? allowLiveFollowing; // Whether active ruck allows live following

  SocialUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.isFollowing,
    required this.followedAt,
    this.activeRuckId,
    this.allowLiveFollowing,
  });

  factory SocialUser.fromJson(Map<String, dynamic> json) => SocialUser(
        id: json['id'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        isFollowing: json['isFollowing'] as bool? ?? false,
        followedAt: DateTime.tryParse(json['followedAt'] as String ?? '') ??
            DateTime.now(),
        activeRuckId: json['activeRuckId'] as String?,
        allowLiveFollowing: json['allowLiveFollowing'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatarUrl': avatarUrl,
        'isFollowing': isFollowing,
        'followedAt': followedAt.toIso8601String(),
        'activeRuckId': activeRuckId,
        'allowLiveFollowing': allowLiveFollowing,
      };

  SocialUser copyWith({bool? isFollowing}) => SocialUser(
        id: id,
        username: username,
        avatarUrl: avatarUrl,
        isFollowing: isFollowing ?? this.isFollowing,
        followedAt: followedAt,
        activeRuckId: activeRuckId,
        allowLiveFollowing: allowLiveFollowing,
      );

  /// Check if user is currently rucking and allows live following
  bool get isLiveRuckingNow => activeRuckId != null && (allowLiveFollowing ?? false);
}
