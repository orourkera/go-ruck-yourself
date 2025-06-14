import 'package:equatable/equatable.dart';

class Club extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String adminUserId;
  final bool isPublic;
  final int? maxMembers;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final String? userRole; // 'admin', 'member', or null if not a member
  final String? userStatus; // 'pending', 'approved', 'rejected', or null

  const Club({
    required this.id,
    required this.name,
    this.description,
    required this.adminUserId,
    required this.isPublic,
    this.maxMembers,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    this.userRole,
    this.userStatus,
  });

  factory Club.fromJson(Map<String, dynamic> json) {
    return Club(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      adminUserId: json['admin_user_id'] as String,
      isPublic: json['is_public'] as bool,
      maxMembers: json['max_members'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      memberCount: json['member_count'] as int,
      userRole: json['user_role'] as String?,
      userStatus: json['user_status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'admin_user_id': adminUserId,
      'is_public': isPublic,
      'max_members': maxMembers,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'member_count': memberCount,
      'user_role': userRole,
      'user_status': userStatus,
    };
  }

  bool get isUserAdmin => userRole == 'admin';
  bool get isUserMember => userRole == 'member' || userRole == 'admin';
  bool get isUserPending => userStatus == 'pending';
  bool get canJoin => userRole == null && userStatus == null;
  bool get isFull => maxMembers != null && memberCount >= maxMembers!;

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        adminUserId,
        isPublic,
        maxMembers,
        createdAt,
        updatedAt,
        memberCount,
        userRole,
        userStatus,
      ];
}

class ClubMember extends Equatable {
  final String userId;
  final String username;
  final String? avatarUrl;
  final String role; // 'admin' or 'member'
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime joinedAt;

  const ClubMember({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  factory ClubMember.fromJson(Map<String, dynamic> json) {
    return ClubMember(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  @override
  List<Object?> get props => [
        userId,
        username,
        avatarUrl,
        role,
        status,
        joinedAt,
      ];
}

class ClubDetails extends Equatable {
  final Club club;
  final List<ClubMember> members;
  final List<ClubMember> pendingRequests;

  const ClubDetails({
    required this.club,
    required this.members,
    required this.pendingRequests,
  });

  factory ClubDetails.fromJson(Map<String, dynamic> json) {
    return ClubDetails(
      club: Club.fromJson(json['club'] as Map<String, dynamic>),
      members: (json['members'] as List<dynamic>)
          .map((member) => ClubMember.fromJson(member as Map<String, dynamic>))
          .toList(),
      pendingRequests: (json['pending_requests'] as List<dynamic>? ?? [])
          .map((request) => ClubMember.fromJson(request as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [club, members, pendingRequests];
}
