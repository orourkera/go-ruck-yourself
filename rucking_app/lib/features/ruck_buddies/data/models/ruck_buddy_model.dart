import 'package:rucking_app/features/ruck_buddies/domain/entities/ruck_buddy.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';

class RuckBuddyModel extends RuckBuddy {
  const RuckBuddyModel({
    required String id,
    required String userId,
    required double ruckWeightKg,
    required int durationSeconds,
    required double distanceKm,
    required int caloriesBurned,
    required double elevationGainM,
    required double elevationLossM,
    DateTime? startedAt,
    DateTime? completedAt,
    required DateTime createdAt,
    int? avgHeartRate,
    required UserInfo user,
    List<dynamic>? locationPoints,
    List<RuckPhoto>? photos,
    int likeCount = 0,
    int commentCount = 0,
    bool isLikedByCurrentUser = false,
  }) : super(
    id: id,
    userId: userId,
    ruckWeightKg: ruckWeightKg,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    caloriesBurned: caloriesBurned,
    elevationGainM: elevationGainM,
    elevationLossM: elevationLossM,
    startedAt: startedAt,
    completedAt: completedAt,
    createdAt: createdAt,
    avgHeartRate: avgHeartRate,
    user: user,
    locationPoints: locationPoints,
    photos: photos,
    likeCount: likeCount,
    commentCount: commentCount,
    isLikedByCurrentUser: isLikedByCurrentUser,
  );

  factory RuckBuddyModel.fromJson(Map<String, dynamic> json) {
    DateTime? startedAtDate;
    if (json['started_at'] != null) {
      startedAtDate = DateTime.parse(json['started_at']);
    }
    DateTime? completedAtDate;
    if (json['completed_at'] != null) {
      completedAtDate = DateTime.parse(json['completed_at']);
    }
    DateTime createdAtDate;
    if (json['created_at'] != null) {
      createdAtDate = DateTime.parse(json['created_at']);
    } else if (json['started_at'] != null) {
      createdAtDate = DateTime.parse(json['started_at']);
    } else {
      createdAtDate = DateTime.now();
    }
    Map<String, dynamic> userData = (json['users'] ?? json['user']) ?? {};

    // Handle location points (could be list of maps or list of [lat,lng])
    List<dynamic>? locationPoints;
    if (json['location_points'] != null) {
      locationPoints = json['location_points'] as List<dynamic>;
    } else if (json['route'] != null) {
      locationPoints = json['route'] as List<dynamic>;
    }

    // Parse photos if available
    List<RuckPhoto>? photos;
    if (json['photos'] != null) {
      photos = (json['photos'] as List)
          .map((photoJson) => RuckPhoto.fromJson(photoJson))
          .toList();
    }

    return RuckBuddyModel(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      ruckWeightKg: (json['ruck_weight_kg'] ?? 0).toDouble(),
      durationSeconds: json['duration_seconds'] ?? 0,
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      caloriesBurned: json['calories_burned'] ?? 0,
      elevationGainM: (json['elevation_gain_m'] ?? 0).toDouble(),
      elevationLossM: (json['elevation_loss_m'] ?? 0).toDouble(),
      startedAt: startedAtDate,
      completedAt: completedAtDate,
      createdAt: createdAtDate,
      avgHeartRate: json['avg_heart_rate'],
      user: UserInfo.fromJson({
        'id': userData['id'],
        'username': userData['username'],
        'avatar_url': userData['avatar_url'],
      }),
      locationPoints: locationPoints,
      photos: photos,
      likeCount: json['like_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      isLikedByCurrentUser: json['is_liked_by_current_user'] ?? false,
    );
  }
}
