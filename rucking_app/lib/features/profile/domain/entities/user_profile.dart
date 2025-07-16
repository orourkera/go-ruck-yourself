class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime createdAt;
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isPrivateProfile;

  UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.createdAt,
    required this.isFollowing,
    required this.isFollowedBy,
    required this.isPrivateProfile,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    username: json['username'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String ?? '') ?? DateTime.now(),
    isFollowing: json['isFollowing'] as bool? ?? false,
    isFollowedBy: json['isFollowedBy'] as bool? ?? false,
    isPrivateProfile: json['isPrivateProfile'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'avatarUrl': avatarUrl,
    'createdAt': createdAt.toIso8601String(),
    'isFollowing': isFollowing,
    'isFollowedBy': isFollowedBy,
    'isPrivateProfile': isPrivateProfile,
  };

  UserProfile copyWith({bool? isFollowing}) => UserProfile(
    id: id,
    username: username,
    avatarUrl: avatarUrl,
    createdAt: createdAt,
    isFollowing: isFollowing ?? this.isFollowing,
    isFollowedBy: isFollowedBy,
    isPrivateProfile: isPrivateProfile,
  );
} 