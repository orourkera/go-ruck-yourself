import 'package:equatable/equatable.dart';

/// Status of a ruck session
enum RuckSessionStatus {
  created,
  inProgress,
  paused,
  completed
}

/// Model representing a ruck session with related statistics
class RuckSession extends Equatable {
  /// Unique identifier for the session
  final String id;
  
  /// Current status of the session
  final RuckSessionStatus status;
  
  /// Weight of the rucksack in kg
  final double ruckWeightKg;
  
  /// Weight of the user in kg (optional)
  final double? userWeightKg;
  
  /// Planned duration in minutes (optional)
  final int? plannedDurationMinutes;
  
  /// Notes about the session (optional)
  final String? notes;
  
  /// User's rating of the session (1-5)
  final int? rating;
  
  /// User's perceived exertion (1-10)
  final int? perceivedExertion;
  
  /// Tags associated with the session
  final List<String>? tags;
  
  /// When the session was created
  final DateTime createdAt;
  
  /// When the session was started (null if not started)
  final DateTime? startedAt;
  
  /// When the session was completed (null if not completed)
  final DateTime? completedAt;
  
  /// Session statistics
  final RuckSessionStats? stats;
  
  /// Final average pace of the session (optional)
  final double? finalAveragePace;
  
  /// Final elevation gain in meters (optional, from backend)
  final double? finalElevationGain;
  
  /// Final elevation loss in meters (optional, from backend)
  final double? finalElevationLoss;
  
  const RuckSession({
    required this.id,
    required this.status,
    required this.ruckWeightKg,
    required this.createdAt,
    this.userWeightKg,
    this.plannedDurationMinutes,
    this.notes,
    this.rating,
    this.perceivedExertion,
    this.tags,
    this.startedAt,
    this.completedAt,
    this.stats,
    this.finalAveragePace,
    this.finalElevationGain,
    this.finalElevationLoss,
  });
  
  @override
  List<Object?> get props => [
    id, 
    status, 
    ruckWeightKg, 
    userWeightKg,
    plannedDurationMinutes,
    notes,
    rating,
    perceivedExertion,
    tags,
    createdAt,
    startedAt,
    completedAt,
    stats,
    finalAveragePace,
    finalElevationGain,
    finalElevationLoss,
  ];
  
  /// Create a copy of this RuckSession with some modified fields
  RuckSession copyWith({
    String? id,
    RuckSessionStatus? status,
    double? ruckWeightKg,
    double? userWeightKg,
    int? plannedDurationMinutes,
    String? notes,
    int? rating,
    int? perceivedExertion,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    RuckSessionStats? stats,
    double? finalAveragePace,
    double? finalElevationGain,
    double? finalElevationLoss,
  }) {
    return RuckSession(
      id: id ?? this.id,
      status: status ?? this.status,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      userWeightKg: userWeightKg ?? this.userWeightKg,
      plannedDurationMinutes: plannedDurationMinutes ?? this.plannedDurationMinutes,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      perceivedExertion: perceivedExertion ?? this.perceivedExertion,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      stats: stats ?? this.stats,
      finalAveragePace: finalAveragePace ?? this.finalAveragePace,
      finalElevationGain: finalElevationGain ?? this.finalElevationGain,
      finalElevationLoss: finalElevationLoss ?? this.finalElevationLoss,
    );
  }
  
  /// Create a RuckSession from JSON
  factory RuckSession.fromJson(Map<String, dynamic> json) {
    return RuckSession(
      id: json['ruck_id'] as String,
      status: _parseStatus(json['status'] as String),
      ruckWeightKg: json['ruck_weight_kg'] as double,
      userWeightKg: json['user_weight_kg'] as double?,
      plannedDurationMinutes: json['planned_duration_minutes'] as int?,
      notes: json['notes'] as String?,
      rating: json['rating'] as int?,
      perceivedExertion: json['perceived_exertion'] as int?,
      tags: json['tags'] != null 
          ? (json['tags'] as List).map((e) => e as String).toList() 
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      startedAt: json['started_at'] != null 
          ? DateTime.parse(json['started_at'] as String) 
          : null,
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at'] as String) 
          : null,
      stats: json['stats'] != null 
          ? RuckSessionStats.fromJson(json['stats'] as Map<String, dynamic>) 
          : null,
      finalAveragePace: (json['final_average_pace'] as num?)?.toDouble(),
      finalElevationGain: (json['final_elevation_gain'] as num?)?.toDouble(),
      finalElevationLoss: (json['final_elevation_loss'] as num?)?.toDouble(),
    );
  }
  
  /// Convert RuckSession to JSON
  Map<String, dynamic> toJson() {
    return {
      'ruck_id': id,
      'status': _statusToString(status),
      'ruck_weight_kg': ruckWeightKg,
      'user_weight_kg': userWeightKg,
      'planned_duration_minutes': plannedDurationMinutes,
      'notes': notes,
      'rating': rating,
      'perceived_exertion': perceivedExertion,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'stats': stats?.toJson(),
      'final_average_pace': finalAveragePace,
      'final_elevation_gain': finalElevationGain,
      'final_elevation_loss': finalElevationLoss,
    };
  }
  
  /// Parse status string to RuckSessionStatus enum
  static RuckSessionStatus _parseStatus(String status) {
    switch (status) {
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
  
  /// Convert RuckSessionStatus enum to string
  static String _statusToString(RuckSessionStatus status) {
    switch (status) {
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

/// Statistics for a ruck session
class RuckSessionStats extends Equatable {
  /// Total distance in km
  final double distanceKm;
  
  /// Elevation gain in meters
  final double elevationGainMeters;
  
  /// Elevation loss in meters
  final double elevationLossMeters;
  
  /// Calories burned
  final int caloriesBurned;
  
  /// Duration in seconds
  final int durationSeconds;
  
  /// Average pace in minutes per km
  final double averagePaceMinKm;
  
  const RuckSessionStats({
    required this.distanceKm,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
    required this.caloriesBurned,
    required this.durationSeconds,
    required this.averagePaceMinKm,
  });
  
  @override
  List<Object?> get props => [
    distanceKm,
    elevationGainMeters,
    elevationLossMeters,
    caloriesBurned,
    durationSeconds,
    averagePaceMinKm,
  ];
  
  /// Create a RuckSessionStats from JSON
  factory RuckSessionStats.fromJson(Map<String, dynamic> json) {
    return RuckSessionStats(
      distanceKm: json['distance_km'] as double,
      elevationGainMeters: json['elevation_gain_meters'] as double,
      elevationLossMeters: json['elevation_loss_meters'] as double,
      caloriesBurned: json['calories_burned'] as int,
      durationSeconds: json['duration_seconds'] as int,
      averagePaceMinKm: json['average_pace_min_km'] as double,
    );
  }
  
  /// Convert RuckSessionStats to JSON
  Map<String, dynamic> toJson() {
    return {
      'distance_km': distanceKm,
      'elevation_gain_meters': elevationGainMeters,
      'elevation_loss_meters': elevationLossMeters,
      'calories_burned': caloriesBurned,
      'duration_seconds': durationSeconds,
      'average_pace_min_km': averagePaceMinKm,
    };
  }
} 