import 'package:equatable/equatable.dart';

class Event extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String creatorUserId;
  final String? clubId;
  final DateTime scheduledStartTime;
  final int durationMinutes;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final int? maxParticipants;
  final int? minParticipants;
  final bool approvalRequired;
  final int? difficultyLevel;
  final double? ruckWeightKg;
  final String? bannerImageUrl;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Additional fields from API response
  final int participantCount;
  final String? userParticipationStatus;
  final bool isCreator;
  final EventCreator? creator;
  final EventHostingClub? hostingClub;

  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.creatorUserId,
    this.clubId,
    required this.scheduledStartTime,
    required this.durationMinutes,
    this.locationName,
    this.latitude,
    this.longitude,
    this.maxParticipants,
    this.minParticipants = 1,
    this.approvalRequired = false,
    this.difficultyLevel,
    this.ruckWeightKg,
    this.bannerImageUrl,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
    this.participantCount = 0,
    this.userParticipationStatus,
    this.isCreator = false,
    this.creator,
    this.hostingClub,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Event',
      description: json['description'] as String?,
      creatorUserId: json['creator_user_id'] as String? ?? '',
      clubId: json['club_id'] as String?,
      scheduledStartTime: json['scheduled_start_time'] != null
          ? DateTime.parse(json['scheduled_start_time'] as String)
          : DateTime.now(),
      durationMinutes: json['duration_minutes'] as int,
      locationName: json['location_name'] as String?,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      maxParticipants: json['max_participants'] as int?,
      minParticipants: json['min_participants'] as int? ?? 1,
      approvalRequired: json['approval_required'] as bool? ?? false,
      difficultyLevel: json['difficulty_level'] as int?,
      ruckWeightKg: json['ruck_weight_kg'] != null
          ? (json['ruck_weight_kg'] as num).toDouble()
          : null,
      bannerImageUrl: json['banner_image_url'] as String?,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      participantCount: json['participant_count'] as int? ?? 0,
      userParticipationStatus: json['user_participation_status'] as String?,
      isCreator: json['is_creator'] as bool? ?? false,
      creator: json['creator'] != null
          ? EventCreator.fromJson(json['creator'] as Map<String, dynamic>)
          : null,
      hostingClub: json['hosting_club'] != null
          ? EventHostingClub.fromJson(
              json['hosting_club'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'creator_user_id': creatorUserId,
      'club_id': clubId,
      'scheduled_start_time': scheduledStartTime.toIso8601String(),
      'duration_minutes': durationMinutes,
      'location_name': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'max_participants': maxParticipants,
      'min_participants': minParticipants,
      'approval_required': approvalRequired,
      'difficulty_level': difficultyLevel,
      'ruck_weight_kg': ruckWeightKg,
      'banner_image_url': bannerImageUrl,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'participant_count': participantCount,
      'user_participation_status': userParticipationStatus,
      'is_creator': isCreator,
      'creator': creator?.toJson(),
      'hosting_club': hostingClub?.toJson(),
    };
  }

  // Computed properties
  bool get isActive => status == 'active';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted =>
      DateTime.now().isAfter(scheduledStartTime.add(Duration(hours: 4)));
  bool get isPast =>
      DateTime.now().isAfter(scheduledStartTime.add(Duration(hours: 4)));
  bool get isUpcoming => DateTime.now().isBefore(scheduledStartTime);
  bool get isOngoing =>
      DateTime.now().isAfter(scheduledStartTime) && !isCompleted;
  bool get canStartRuck =>
      (isUpcoming || isOngoing) && isActive && !isCancelled;
  bool get isFull =>
      maxParticipants != null && participantCount >= maxParticipants!;
  bool get isClubEvent => clubId != null;
  bool get canJoin =>
      userParticipationStatus == null && !isPast && !isFull && isActive;
  bool get canLeave => userParticipationStatus != null && !isPast;
  bool get isUserParticipating =>
      userParticipationStatus == 'approved' ||
      userParticipationStatus == 'pending';
  bool get isUserApproved => userParticipationStatus == 'approved';
  bool get isUserPending => userParticipationStatus == 'pending';
  bool get needsApproval => approvalRequired;

  DateTime get scheduledEndTime =>
      scheduledStartTime.add(Duration(minutes: durationMinutes));

  String get participantStatusText {
    switch (userParticipationStatus) {
      case 'approved':
        return 'Joined';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Not Joined';
    }
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        creatorUserId,
        clubId,
        scheduledStartTime,
        durationMinutes,
        locationName,
        latitude,
        longitude,
        maxParticipants,
        minParticipants,
        approvalRequired,
        difficultyLevel,
        ruckWeightKg,
        bannerImageUrl,
        status,
        createdAt,
        updatedAt,
        participantCount,
        userParticipationStatus,
        isCreator,
        creator,
        hostingClub,
      ];
}

class EventCreator extends Equatable {
  final String id;
  final String username;
  final String? avatarUrl;

  const EventCreator({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory EventCreator.fromJson(Map<String, dynamic> json) {
    return EventCreator(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
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

class EventHostingClub extends Equatable {
  final String id;
  final String name;
  final String? logoUrl;

  const EventHostingClub({
    required this.id,
    required this.name,
    this.logoUrl,
  });

  factory EventHostingClub.fromJson(Map<String, dynamic> json) {
    return EventHostingClub(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
    };
  }

  @override
  List<Object?> get props => [id, name, logoUrl];
}

class EventParticipant extends Equatable {
  final String id;
  final String eventId;
  final String userId;
  final String status;
  final DateTime joinedAt;
  final EventUser? user;

  const EventParticipant({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.status,
    required this.joinedAt,
    this.user,
  });

  factory EventParticipant.fromJson(Map<String, dynamic> json) {
    // Handle both nested and flat user data structures
    Map<String, dynamic>? userData;
    if (json['user'] != null) {
      // Nested structure from joined query
      userData = json['user'] as Map<String, dynamic>;
    } else if (json['username'] != null) {
      // Flat structure - user data at top level
      userData = {
        'id': json['user_id'],
        'username': json['username'],
        'avatar_url': json['avatar_url'],
      };
    }

    return EventParticipant(
      id: json['id'] as String? ?? '',
      eventId: json['event_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      joinedAt: json['registered_at'] != null
          ? DateTime.parse(json['registered_at'] as String)
          : (json['joined_at'] != null
              ? DateTime.parse(json['joined_at'] as String)
              : DateTime.now()),
      user: userData != null ? EventUser.fromJson(userData) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'user_id': userId,
      'status': status,
      'joined_at': joinedAt.toIso8601String(),
      'user': user?.toJson(),
    };
  }

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  @override
  List<Object?> get props => [id, eventId, userId, status, joinedAt, user];
}

class EventUser extends Equatable {
  final String id;
  final String username;
  final String? avatarUrl;

  const EventUser({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory EventUser.fromJson(Map<String, dynamic> json) {
    return EventUser(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
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

class EventDetails extends Equatable {
  final Event event;
  final List<EventParticipant> participants;

  const EventDetails({
    required this.event,
    required this.participants,
  });

  factory EventDetails.fromJson(Map<String, dynamic> json) {
    return EventDetails(
      event: Event.fromJson(json['event'] as Map<String, dynamic>),
      participants: (json['participants'] as List<dynamic>? ?? [])
          .map((participant) =>
              EventParticipant.fromJson(participant as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event': event.toJson(),
      'participants': participants.map((p) => p.toJson()).toList(),
    };
  }

  List<EventParticipant> get approvedParticipants =>
      participants.where((p) => p.isApproved).toList();

  List<EventParticipant> get pendingParticipants =>
      participants.where((p) => p.isPending).toList();

  @override
  List<Object?> get props => [event, participants];
}
