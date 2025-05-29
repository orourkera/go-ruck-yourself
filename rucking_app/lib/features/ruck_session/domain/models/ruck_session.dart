import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/domain/models/session_split.dart';

/// Enum representing the status of a ruck session
enum RuckStatus {
  inProgress,
  completed,
  cancelled,
  unknown // Default/fallback
}

/// Model representing a completed ruck session
class RuckSession {
  // Returns a copy of this RuckSession with updated fields
  RuckSession copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    double? distance,
    double? elevationGain,
    double? elevationLoss,
    int? caloriesBurned,
    double? averagePace,
    double? ruckWeightKg,
    RuckStatus? status,
    String? notes,
    int? rating,
    List<Map<String, dynamic>>? locationPoints,
    double? finalElevationGain,
    double? finalElevationLoss,
    List<HeartRateSample>? heartRateSamples,
    int? avgHeartRate,
    int? maxHeartRate,
    int? minHeartRate,
    List<String>? tags,
    int? perceivedExertion,
    double? weightKg,
    int? plannedDurationMinutes,
    int? pausedDurationSeconds,
    List<SessionSplit>? splits,
  }) {
    return RuckSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      distance: distance ?? this.distance,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      averagePace: averagePace ?? this.averagePace,
      ruckWeightKg: ruckWeightKg ?? this.ruckWeightKg,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      rating: rating ?? this.rating,
      locationPoints: locationPoints ?? this.locationPoints,
      finalElevationGain: finalElevationGain ?? this.finalElevationGain,
      finalElevationLoss: finalElevationLoss ?? this.finalElevationLoss,
      heartRateSamples: heartRateSamples ?? this.heartRateSamples,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      minHeartRate: minHeartRate ?? this.minHeartRate,
      tags: tags ?? this.tags,
      perceivedExertion: perceivedExertion ?? this.perceivedExertion,
      weightKg: weightKg ?? this.weightKg,
      plannedDurationMinutes: plannedDurationMinutes ?? this.plannedDurationMinutes,
      pausedDurationSeconds: pausedDurationSeconds ?? this.pausedDurationSeconds,
      splits: splits ?? this.splits,
    );
  }

  // ...existing fields...
  final List<String>? tags;
  final int? perceivedExertion;
  final double? weightKg;
  final int? plannedDurationMinutes;
  final int? pausedDurationSeconds;
  final String? id;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final int caloriesBurned;
  final double averagePace;
  final double ruckWeightKg;
  final RuckStatus status;
  final String? notes;
  final int? rating;
  final List<Map<String, dynamic>>? locationPoints;
  final double? finalElevationGain;
  final double? finalElevationLoss;
  final List<HeartRateSample>? heartRateSamples;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? minHeartRate;
  final List<SessionSplit>? splits;

  RuckSession({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.caloriesBurned,
    required this.averagePace,
    required this.ruckWeightKg,
    required this.status,
    this.notes,
    this.rating,
    this.locationPoints,
    this.finalElevationGain,
    this.finalElevationLoss,
    this.heartRateSamples,
    this.avgHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
    this.tags,
    this.perceivedExertion,
    this.weightKg,
    this.plannedDurationMinutes,
    this.pausedDurationSeconds,
    this.splits,
  });

  /// Calculate pace in minutes per kilometer
  double get paceMinPerKm {
    if (distance <= 0) return 0;
    return (duration.inSeconds / 60) / distance;
  }

  /// Format pace as MM:SS string
  String get formattedPace {
    final double paceValue = paceMinPerKm;
    if (paceValue <= 0) return '--:--';
    
    final int minutes = paceValue.floor();
    final int seconds = ((paceValue - minutes) * 60).round();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format duration as HH:MM:SS
  String get formattedDuration {
    final int hours = duration.inSeconds ~/ 3600;
    final int minutes = (duration.inSeconds % 3600) ~/ 60;
    final int seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Create a RuckSession from a JSON map
  /// Handles various API response formats
  static DateTime? parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

factory RuckSession.fromJson(Map<String, dynamic> json) {
  try {
    // Strictly use 'started_at' for start time
    final parsedStartTime = RuckSession.parseDateTime(json['started_at']);
    if (parsedStartTime == null) {
      AppLogger.error(
        "RuckSession.fromJson: Missing or invalid 'started_at'. Session ID: ${json['id']}. JSON: $json"
      );
      throw FormatException(
          "RuckSession.fromJson: 'started_at' is null or invalid for session ID: ${json['id']}. Received data must include a valid 'started_at'.");
    }
    final DateTime startTime = parsedStartTime;

    // Strictly use 'completed_at' for end time, with fallback to duration_seconds calculation
    DateTime? potentialEndTime = RuckSession.parseDateTime(json['completed_at']);

    if (potentialEndTime == null) {
      final durationSeconds = (json['duration_seconds'] as num?)?.toInt();
      if (durationSeconds != null) {
        potentialEndTime = startTime.add(Duration(seconds: durationSeconds));
        AppLogger.info("RuckSession.fromJson: 'completed_at' is null, calculated endTime from startTime and duration_seconds. Session ID: ${json['id']}");
      } else {
        final statusString = json['status']?.toString().toLowerCase();
        if (statusString == 'in_progress' || statusString == 'inprogress') {
            AppLogger.info("RuckSession.fromJson: 'completed_at' and 'duration_seconds' are null for an in-progress session. Setting endTime to startTime. Session ID: ${json['id']}");
            potentialEndTime = startTime; // For in-progress, use startTime if no end data
        } else {
            AppLogger.error(
              "RuckSession.fromJson: Missing or invalid 'completed_at' AND 'duration_seconds' for a session not marked 'in_progress'. Session ID: ${json['id']}. Session status: '$statusString'. JSON: $json"
            );
            throw FormatException(
                "RuckSession.fromJson: 'completed_at' and 'duration_seconds' are both null or invalid for session ID: ${json['id']}. Session status: '$statusString'.");
        }
      }
    }
    final DateTime endTime = potentialEndTime;
    
    // Calculate duration from start/end time or use duration_seconds field
    final duration = json['duration_seconds'] != null
        ? Duration(seconds: (json['duration_seconds'] as num).toInt())
        : endTime.difference(startTime);
      
      // Handle various ways distance might be stored
      double parseDistance(dynamic value) {
        if (value == null) return 0.0;
        if (value is double) return value;
        if (value is int) return value.toDouble();
        try {
          return double.parse(value.toString());
        } catch (e) {
          return 0.0;
        }
      }
      
      final distance = parseDistance(json['distance_km'] ?? json['distance'] ?? 0.0);
      
      // Handle status (map string to enum)
      RuckStatus status = RuckStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (json['status'] ?? '').toString(),
        orElse: () {
          AppLogger.warning("RuckSession.fromJson: Unknown or null status string '${json['status']}'. Defaulting to RuckStatus.unknown. Session ID: ${json['id']}. JSON: $json");
          return RuckStatus.unknown;
        },
      );
      
      // Extract other fields with sensible defaults
      return RuckSession(
        id: json['id']?.toString(),
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        distance: distance,
        elevationGain: parseDistance(json['elevation_gain_meters'] ?? json['elevation_gain_m'] ?? json['elevationGain'] ?? 0.0),
        elevationLoss: parseDistance(json['elevation_loss_meters'] ?? json['elevation_loss_m'] ?? json['elevationLoss'] ?? 0.0),
        caloriesBurned: (json['calories_burned'] ?? json['caloriesBurned'] ?? 0) is int
            ? (json['calories_burned'] ?? json['caloriesBurned'] ?? 0)
            : (json['calories_burned'] ?? json['caloriesBurned'] ?? 0).toInt(),
        averagePace: parseDistance(json['average_pace'] ?? json['averagePace'] ?? 0.0),
        ruckWeightKg: parseDistance(json['ruck_weight_kg'] ?? json['ruckWeightKg'] ?? 0.0),
        status: status,
        notes: json['notes']?.toString(),
        rating: json['rating'] is int ? json['rating'] : null,
        locationPoints: ((json['route'] as List<dynamic>?) ?? (json['location_points'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>(),
        finalElevationGain: json['final_elevation_gain'] != null ? parseDistance(json['final_elevation_gain']) : null,
        finalElevationLoss: json['final_elevation_loss'] != null ? parseDistance(json['final_elevation_loss']) : null,
        heartRateSamples: json['heart_rate_samples'] != null
            ? (json['heart_rate_samples'] as List<dynamic>)
                .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        avgHeartRate: json['avg_heart_rate'] != null ? (json['avg_heart_rate'] as num).toInt() : null,
        maxHeartRate: json['max_heart_rate'] != null ? (json['max_heart_rate'] as num).toInt() : null,
        minHeartRate: json['min_heart_rate'] != null ? (json['min_heart_rate'] as num).toInt() : null,
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
        perceivedExertion: json['perceived_exertion'] != null ? (json['perceived_exertion'] as num).toInt() : null,
        weightKg: json['weight_kg'] != null ? parseDistance(json['weight_kg']) : null,
        plannedDurationMinutes: json['planned_duration_minutes'] != null ? (json['planned_duration_minutes'] as num).toInt() : null,
        pausedDurationSeconds: json['paused_duration_seconds'] != null ? (json['paused_duration_seconds'] as num).toInt() : null,
        splits: json['splits'] != null
            ? (json['splits'] as List<dynamic>)
                .map((e) => SessionSplit.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
      );
    } catch (e) {
      AppLogger.error("Error parsing RuckSession from JSON: $e");
      rethrow;
    }
  }

  /// Convert the RuckSession to a JSON map
  Map<String, dynamic> toJson() {
    final dateFormat = DateFormat("yyyy-MM-ddTHH:mm:ss");
    
    // Helper to convert enum back to string for API
    String statusToString(RuckStatus status) {
      switch (status) {
        case RuckStatus.inProgress:
          return 'in_progress';
        case RuckStatus.completed:
          return 'completed';
        case RuckStatus.cancelled:
          return 'cancelled';
        case RuckStatus.unknown:
        default:
          return 'unknown'; // Or maybe null?
      }
    }
    
    return {
      'id': id,
      'start_time': dateFormat.format(startTime),
      'average_pace': averagePace,
      'end_time': dateFormat.format(endTime),
      'duration_seconds': duration.inSeconds,
      'distance_km': distance,
      'elevation_gain_meters': elevationGain,
      'elevation_loss_meters': elevationLoss,
      'calories_burned': caloriesBurned,
      'average_pace': averagePace,
      'ruck_weight_kg': ruckWeightKg,
      'status': statusToString(status),
      'notes': notes,
      'rating': rating,
      'location_points': locationPoints,
      'final_elevation_gain': finalElevationGain,
      'final_elevation_loss': finalElevationLoss,
      'heart_rate_samples': heartRateSamples?.map((e) => e.toJson()).toList(),
      'avg_heart_rate': avgHeartRate,
      'max_heart_rate': maxHeartRate,
      'min_heart_rate': minHeartRate,
      'tags': tags,
      'perceived_exertion': perceivedExertion,
      'weight_kg': weightKg,
      'planned_duration_minutes': plannedDurationMinutes,
      'paused_duration_seconds': pausedDurationSeconds,
      'splits': splits?.map((e) => e.toJson()).toList(),
    };
  }
}
