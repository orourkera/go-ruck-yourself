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
  
  /// Total distance in kilometers
  final double? distanceKm;
  
  /// Total elevation gain in meters
  final double? elevationGainMeters;
  
  /// Total elevation loss in meters
  final double? elevationLossMeters;
  
  /// Estimated calories burned
  final double? caloriesBurned;
  
  /// Power points calculated from weight × distance × elevation gain
  final double? powerPoints;
  
  /// Duration in seconds
  final int? durationSeconds;
  
  /// Average pace in minutes per kilometer
  final double? averagePaceMinKm;
  
  /// URL for route map (may be null)
  final String? routeMapUrl;
  
  /// Route waypoints (may be null)
  final List<LocationPoint>? waypoints;
  
  /// Session review (may be null)
  final SessionReview? review;
  
  /// Tags for the session
  final List<String> tags;
  
  /// Whether this session is publicly shared
  final bool isPublic;
  
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
    this.distanceKm,
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.caloriesBurned,
    this.powerPoints,
    this.durationSeconds,
    this.averagePaceMinKm,
    this.routeMapUrl,
    this.waypoints,
    this.review,
    this.tags = const <String>[],
    this.isPublic = false,
  });
  
  /// Formatted duration as HH:MM:SS
  String get formattedDuration {
    final secs = durationSeconds ?? 0;
    final hours = secs ~/ 3600;
    final minutes = (secs % 3600) ~/ 60;
    final seconds = secs % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  /// Formatted pace as MM:SS per km
  String get formattedPace {
    final pace = averagePaceMinKm ?? 0.0;
    final totalMinutes = pace.floor();
    final seconds = ((pace - totalMinutes) * 60).round();
    return '${totalMinutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  
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
    double? distanceKm,
    double? elevationGainMeters,
    double? elevationLossMeters,
    double? caloriesBurned,
    double? powerPoints,
    int? durationSeconds,
    double? averagePaceMinKm,
    String? routeMapUrl,
    List<LocationPoint>? waypoints,
    SessionReview? review,
    List<String>? tags,
    bool? isPublic,
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
      distanceKm: distanceKm ?? this.distanceKm,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      elevationLossMeters: elevationLossMeters ?? this.elevationLossMeters,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      powerPoints: powerPoints ?? this.powerPoints,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      averagePaceMinKm: averagePaceMinKm ?? this.averagePaceMinKm,
      routeMapUrl: routeMapUrl ?? this.routeMapUrl,
      waypoints: waypoints ?? this.waypoints,
      review: review ?? this.review,
      tags: tags ?? this.tags,
      isPublic: isPublic ?? this.isPublic,
    );
  }
  
  /// Factory constructor for creating a RuckSession from JSON
  factory RuckSession.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse numbers
    num? safeParseNum(dynamic value) {
      if (value == null) return null;
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    }

    // Robustly parse ruckId as String regardless of int/String/null
    String? ruckId;
    var rawId = json['id'] ?? json['ruck_id'];
    if (rawId != null) {
      ruckId = rawId.toString();
    }

    // Robustly parse userId as String regardless of int/String/null
    String userId = '';
    var rawUserId = json['user_id'];
    if (rawUserId != null) {
      userId = rawUserId.toString();
    }

    return RuckSession(
      ruckId: ruckId,
      userId: userId,
      status: RuckSessionStatus.fromString(json['status'] as String),
      ruckWeightKg: (safeParseNum(json['ruck_weight_kg']) ?? 0).toDouble(),
      userWeightKg: safeParseNum(json['user_weight_kg'])?.toDouble(),
      plannedDurationMinutes: safeParseNum(json['planned_duration_minutes'])?.toInt(),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
      startedAt: json['started_at'] as String?,
      pausedAt: json['paused_at'] as String?,
      completedAt: json['completed_at'] as String?,
      distanceKm: safeParseNum(json['distance_km'])?.toDouble(),
      elevationGainMeters: safeParseNum(json['elevation_gain_meters'])?.toDouble(),
      elevationLossMeters: safeParseNum(json['elevation_loss_meters'])?.toDouble(),
      caloriesBurned: safeParseNum(json['calories_burned'])?.toDouble(),
      powerPoints: safeParseNum(json['power_points'])?.toDouble(),
      durationSeconds: safeParseNum(json['duration_seconds'])?.toInt(),
      averagePaceMinKm: safeParseNum(json['average_pace_min_km'])?.toDouble(),
      routeMapUrl: json['route_map_url'] as String?,
      waypoints: json['waypoints'] != null && json['waypoints'] is List
          ? (json['waypoints'] as List<dynamic>)
              .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
              .toList() 
          : null,
      review: json['review'] != null 
          ? SessionReview.fromJson(json['review'] as Map<String, dynamic>) 
          : null,
      tags: json['tags'] != null && json['tags'] is List 
          ? (json['tags'] as List<dynamic>).map((e) => e.toString()).toList() 
          : const <String>[],
      isPublic: json['is_public'] ?? false,
    );
  }
  
  /// Convert ruck session to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'user_id': userId,
      'status': status.toJson(),
      'ruck_weight_kg': ruckWeightKg,
    };
    
    if (ruckId != null) result['id'] = ruckId; // Use 'id' for consistency
    if (userWeightKg != null) result['user_weight_kg'] = userWeightKg;
    if (plannedDurationMinutes != null) result['planned_duration_minutes'] = plannedDurationMinutes;
    if (notes != null) result['notes'] = notes;
    if (createdAt != null) result['created_at'] = createdAt;
    if (startedAt != null) result['started_at'] = startedAt;
    if (pausedAt != null) result['paused_at'] = pausedAt;
    if (completedAt != null) result['completed_at'] = completedAt;
    if (distanceKm != null) result['distance_km'] = distanceKm;
    if (elevationGainMeters != null) result['elevation_gain_meters'] = elevationGainMeters;
    if (elevationLossMeters != null) result['elevation_loss_meters'] = elevationLossMeters;
    if (caloriesBurned != null) result['calories_burned'] = caloriesBurned;
    if (powerPoints != null) result['power_points'] = powerPoints;
    if (durationSeconds != null) result['duration_seconds'] = durationSeconds;
    if (averagePaceMinKm != null) result['average_pace_min_km'] = averagePaceMinKm;
    if (routeMapUrl != null) result['route_map_url'] = routeMapUrl;
    if (waypoints != null) result['waypoints'] = waypoints!.map((e) => e.toJson()).toList();
    if (review != null) result['review'] = review!.toJson();
    if (tags.isNotEmpty) result['tags'] = tags;
    if (isPublic != false) result['is_public'] = isPublic;
    
    return result;
  }
  
  @override
  List<Object?> get props => [
    ruckId, userId, status, ruckWeightKg, userWeightKg, plannedDurationMinutes,
    notes, createdAt, startedAt, pausedAt, completedAt, 
    distanceKm, elevationGainMeters, elevationLossMeters, caloriesBurned, powerPoints, 
    durationSeconds, averagePaceMinKm, routeMapUrl,
    waypoints, review, tags, isPublic
  ];
} 