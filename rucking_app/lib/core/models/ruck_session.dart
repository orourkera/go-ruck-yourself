import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/session_review.dart';

/// Status of a ruck session
enum RuckSessionStatus {
  created,
  inProgress,
  paused,
  completed;
  
  factory RuckSessionStatus.fromString(String value) {
    switch (value) {
      case 'created':
        return RuckSessionStatus.created;
      case 'in_progress':
        return RuckSessionStatus.inProgress;
      case 'paused':
        return RuckSessionStatus.paused;
      case 'completed':
        return RuckSessionStatus.completed;
      default:
        return RuckSessionStatus.created;
    }
  }
  
  String toJson() {
    switch (this) {
      case RuckSessionStatus.created:
        return 'created';
      case RuckSessionStatus.inProgress:
        return 'in_progress';
      case RuckSessionStatus.paused:
        return 'paused';
      case RuckSessionStatus.completed:
        return 'completed';
    }
  }
}

/// Model representing a ruck session
class RuckSession extends Equatable {
  /// Unique identifier for the session
  final String? ruckId;
  
  /// User ID of the session owner
  final String userId;
  
  /// Current status of the session
  final RuckSessionStatus status;
  
  /// Weight of the ruck in kilograms
  final double ruckWeightKg;
  
  /// Weight of the user in kilograms (may be null)
  final double? userWeightKg;
  
  /// Planned duration in minutes (may be null)
  final int? plannedDurationMinutes;
  
  /// Notes about the session
  final String? notes;
  
  /// When the session was created
  final String? createdAt;
  
  /// When the session was started
  final String? startedAt;
  
  /// When the session was paused
  final String? pausedAt;
  
  /// When the session was completed
  final String? completedAt;
  
  /// Session statistics
  final RuckSessionStats? stats;
  
  /// Route waypoints (may be null)
  final List<LocationPoint>? waypoints;
  
  /// Session review (may be null)
  final SessionReview? review;
  
  /// Tags for the session
  final List<String> tags;
  
  /// Creates a new ruck session
  const RuckSession({
    this.ruckId,
    required this.userId,
    required this.status,
    required this.ruckWeightKg,
    this.userWeightKg,
    this.plannedDurationMinutes,
    this.notes,
    this.createdAt,
    this.startedAt,
    this.pausedAt,
    this.completedAt,
    this.stats,
    this.waypoints,
    this.review,
    this.tags = const <String>[],
  });
  
  /// Creates a copy with the given fields replaced with new values
  RuckSession copyWith({
    String? ruckId,
    String? userId,
    RuckSessionStatus? status,
    double? ruckWeightKg,
    double? userWeightKg,
    int? plannedDurationMinutes,
    String? notes,
    String? createdAt,
    String? startedAt,
    String? pausedAt,
    String? completedAt,
    RuckSessionStats? stats,
    List<LocationPoint>? waypoints,
    SessionReview? review,
    List<String>? tags,
  }) {
    return RuckSession(
      ruckId: ruckId ?? this.ruckId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      userWeightKg: userWeightKg ?? this.userWeightKg,
      plannedDurationMinutes: plannedDurationMinutes ?? this.plannedDurationMinutes,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      completedAt: completedAt ?? this.completedAt,
      stats: stats ?? this.stats,
      waypoints: waypoints ?? this.waypoints,
      review: review ?? this.review,
      tags: tags ?? this.tags,
    );
  }
  
  /// Factory constructor for creating a RuckSession from JSON
  factory RuckSession.fromJson(Map<String, dynamic> json) {
    return RuckSession(
      ruckId: json['ruck_id'] as String?,
      userId: json['user_id'] as String,
      status: RuckSessionStatus.fromString(json['status'] as String),
      ruckWeightKg: (json['ruck_weight_kg'] as num).toDouble(),
      userWeightKg: json['user_weight_kg'] != null 
          ? (json['user_weight_kg'] as num).toDouble() 
          : null,
      plannedDurationMinutes: json['planned_duration_minutes'] as int?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
      startedAt: json['started_at'] as String?,
      pausedAt: json['paused_at'] as String?,
      completedAt: json['completed_at'] as String?,
      stats: json['stats'] != null 
          ? RuckSessionStats.fromJson(json['stats'] as Map<String, dynamic>) 
          : null,
      waypoints: json['waypoints'] != null 
          ? (json['waypoints'] as List<dynamic>)
              .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
              .toList() 
          : null,
      review: json['review'] != null 
          ? SessionReview.fromJson(json['review'] as Map<String, dynamic>) 
          : null,
      tags: json['tags'] != null 
          ? (json['tags'] as List<dynamic>).map((e) => e as String).toList() 
          : const <String>[],
    );
  }
  
  /// Convert ruck session to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'user_id': userId,
      'status': status.toJson(),
      'ruck_weight_kg': ruckWeightKg,
    };
    
    if (ruckId != null) result['ruck_id'] = ruckId;
    if (userWeightKg != null) result['user_weight_kg'] = userWeightKg;
    if (plannedDurationMinutes != null) result['planned_duration_minutes'] = plannedDurationMinutes;
    if (notes != null) result['notes'] = notes;
    if (createdAt != null) result['created_at'] = createdAt;
    if (startedAt != null) result['started_at'] = startedAt;
    if (pausedAt != null) result['paused_at'] = pausedAt;
    if (completedAt != null) result['completed_at'] = completedAt;
    if (stats != null) result['stats'] = stats!.toJson();
    if (waypoints != null) result['waypoints'] = waypoints!.map((e) => e.toJson()).toList();
    if (review != null) result['review'] = review!.toJson();
    if (tags.isNotEmpty) result['tags'] = tags;
    
    return result;
  }
  
  @override
  List<Object?> get props => [
    ruckId, userId, status, ruckWeightKg, userWeightKg, plannedDurationMinutes,
    notes, createdAt, startedAt, pausedAt, completedAt, stats, waypoints, review, tags
  ];
}

/// Statistics for a ruck session
class RuckSessionStats extends Equatable {
  /// Total distance in kilometers
  final double distanceKm;
  
  /// Total elevation gain in meters
  final double elevationGainMeters;
  
  /// Total elevation loss in meters
  final double elevationLossMeters;
  
  /// Estimated calories burned
  final double caloriesBurned;
  
  /// Duration in seconds
  final int durationSeconds;
  
  /// Average pace in minutes per kilometer
  final double averagePaceMinKm;
  
  /// URL for route map (may be null)
  final String? routeMapUrl;
  
  /// Creates a new ruck session stats instance
  const RuckSessionStats({
    required this.distanceKm,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
    required this.caloriesBurned,
    required this.durationSeconds,
    required this.averagePaceMinKm,
    this.routeMapUrl,
  });
  
  /// Formatted duration as HH:MM:SS
  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  /// Formatted pace as MM:SS per km
  String get formattedPace {
    final totalMinutes = averagePaceMinKm.floor();
    final seconds = ((averagePaceMinKm - totalMinutes) * 60).round();
    return '${totalMinutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  
  /// Factory constructor for creating RuckSessionStats from JSON
  factory RuckSessionStats.fromJson(Map<String, dynamic> json) {
    return RuckSessionStats(
      distanceKm: (json['distance_km'] as num).toDouble(),
      elevationGainMeters: (json['elevation_gain_meters'] as num).toDouble(),
      elevationLossMeters: (json['elevation_loss_meters'] as num).toDouble(),
      caloriesBurned: (json['calories_burned'] as num).toDouble(),
      durationSeconds: json['duration_seconds'] as int,
      averagePaceMinKm: (json['average_pace_min_km'] as num).toDouble(),
      routeMapUrl: json['route_map_url'] as String?,
    );
  }
  
  /// Convert ruck session stats to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'distance_km': distanceKm,
      'elevation_gain_meters': elevationGainMeters,
      'elevation_loss_meters': elevationLossMeters,
      'calories_burned': caloriesBurned,
      'duration_seconds': durationSeconds,
      'average_pace_min_km': averagePaceMinKm,
    };
    
    if (routeMapUrl != null) result['route_map_url'] = routeMapUrl;
    
    return result;
  }
  
  @override
  List<Object?> get props => [
    distanceKm, elevationGainMeters, elevationLossMeters, 
    caloriesBurned, durationSeconds, averagePaceMinKm, routeMapUrl
  ];
} 