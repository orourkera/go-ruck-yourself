import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/ruck_buddies/domain/entities/user_info.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_photo.dart';

class RuckBuddy extends Equatable {
  final String id;
  final String userId;
  final double ruckWeightKg;
  final int durationSeconds;
  final double distanceKm;
  final int caloriesBurned;
  final double elevationGainM;
  final double elevationLossM;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final int? avgHeartRate;
  final UserInfo user;
  final List<dynamic>? locationPoints;
  final List<RuckPhoto>? photos;
  final int likeCount;
  final int commentCount;
  final bool isLikedByCurrentUser;

  const RuckBuddy({
    required this.id,
    required this.userId,
    required this.ruckWeightKg,
    required this.durationSeconds,
    required this.distanceKm,
    required this.caloriesBurned,
    required this.elevationGainM,
    required this.elevationLossM,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    this.avgHeartRate,
    required this.user,
    this.locationPoints,
    this.photos,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLikedByCurrentUser = false,
  });

  @override
  List<Object?> get props => [
    id, userId, ruckWeightKg, durationSeconds, 
    distanceKm, caloriesBurned, elevationGainM, 
    elevationLossM, startedAt, completedAt, createdAt, 
    avgHeartRate, user, locationPoints, photos,
    likeCount, commentCount, isLikedByCurrentUser
  ];
}
