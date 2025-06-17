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
  final String? logoUrl;
  final String? location;
  final double? latitude;
  final double? longitude;

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
    this.logoUrl,
    this.location,
    this.latitude,
    this.longitude,
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
      updatedAt: DateTime.parse(json['updated_at'] as String? ?? json['created_at'] as String),
      memberCount: json['member_count'] as int? ?? 0, // Default to 0 if null
      userRole: json['user_role'] as String?,
      userStatus: json['user_status'] as String?,
      logoUrl: json['logo_url'] as String?,
      location: json['location'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
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
      'logo_url': logoUrl,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
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
        logoUrl,
        location,
        latitude,
        longitude,
      ];
}

class ClubMember extends Equatable {
  final String userId;
  final String? username;
  final String? avatarUrl;
  final String role; // 'admin' or 'member'
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime joinedAt;

  const ClubMember({
    required this.userId,
    this.username,
    this.avatarUrl,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  factory ClubMember.fromJson(Map<String, dynamic> json) {
    return ClubMember(
      userId: json['user_id'] as String,
      username: json['username'] as String?,
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
  final ClubMember adminUser;

  const ClubDetails({
    required this.club,
    required this.members,
    required this.pendingRequests,
    required this.adminUser,
  });

  factory ClubDetails.fromJson(Map<String, dynamic> json) {
    // Support both old and new API formats
    final clubJson = json.containsKey('club') ? json['club'] as Map<String, dynamic> : json;

    // Get admin user data
    ClubMember adminUser;
    if (clubJson['admin_user'] != null) {
      // Create a ClubMember from admin_user data
      final adminData = clubJson['admin_user'] as Map<String, dynamic>;
      adminUser = ClubMember(
        userId: adminData['id'] as String,
        username: adminData['username'] as String?,
        avatarUrl: adminData['avatar_url'] as String?,
        role: 'admin',
        status: 'approved',
        joinedAt: DateTime.parse(clubJson['created_at'] as String),
      );
    } else {
      // Fallback: try to find admin in members list
      final members = (clubJson['members'] as List<dynamic>? ?? [])
          .map((member) => ClubMember.fromJson(member as Map<String, dynamic>))
          .toList();
      adminUser = members.firstWhere(
        (member) => member.role == 'admin',
        orElse: () => ClubMember(
          userId: clubJson['admin_user_id'] as String? ?? '',
          username: 'Unknown',
          role: 'admin',
          status: 'approved',
          joinedAt: DateTime.parse(clubJson['created_at'] as String),
        ),
      );
    }

    return ClubDetails(
      club: Club.fromJson(clubJson),
      members: (clubJson['members'] as List<dynamic>? ?? [])
          .map((member) => ClubMember.fromJson(member as Map<String, dynamic>))
          .toList(),
      pendingRequests: (clubJson['pending_requests'] as List<dynamic>? ?? [])
          .map((request) => ClubMember.fromJson(request as Map<String, dynamic>))
          .toList(),
      adminUser: adminUser,
    );
  }

  @override
  List<Object?> get props => [club, members, pendingRequests, adminUser];
}
