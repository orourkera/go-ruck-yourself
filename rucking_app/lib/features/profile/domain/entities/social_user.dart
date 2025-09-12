class SocialUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final bool isFollowing;
  final DateTime followedAt;

  SocialUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.isFollowing,
    required this.followedAt,
  });

  factory SocialUser.fromJson(Map<String, dynamic> json) => SocialUser(
        id: json['id'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        isFollowing: json['isFollowing'] as bool? ?? false,
        followedAt: DateTime.tryParse(json['followedAt'] as String ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatarUrl': avatarUrl,
        'isFollowing': isFollowing,
        'followedAt': followedAt.toIso8601String(),
      };

  SocialUser copyWith({bool? isFollowing}) => SocialUser(
        id: id,
        username: username,
        avatarUrl: avatarUrl,
        isFollowing: isFollowing ?? this.isFollowing,
        followedAt: followedAt,
      );
}
