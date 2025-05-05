import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

/// Enum representing the status of a ruck session
enum RuckStatus {
  inProgress,
  completed,
  cancelled,
  unknown // Default/fallback
}

/// Model representing a completed ruck session
class RuckSession {
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
  factory RuckSession.fromJson(Map<String, dynamic> json) {
    try {
      // Handle created_at or start_time fields for start time
      final startTimeStr = json['start_time'] ?? json['created_at'] ?? json['startTime'];
      final startTime = startTimeStr != null 
          ? DateTime.tryParse(startTimeStr is String ? startTimeStr : startTimeStr.toString()) ?? DateTime.now()
          : DateTime.now();
      
      // Handle end_time or completed_at fields for end time
      final endTimeStr = json['end_time'] ?? json['completed_at'] ?? json['endTime'];
      final endTime = endTimeStr != null 
          ? DateTime.tryParse(endTimeStr is String ? endTimeStr : endTimeStr.toString()) ?? 
              startTime.add(Duration(seconds: json['duration_seconds'] as int? ?? 0))
          : startTime.add(Duration(seconds: json['duration_seconds'] as int? ?? 0));
      
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
        orElse: () => RuckStatus.unknown,
      );
      
      // Extract other fields with sensible defaults
      return RuckSession(
        id: json['id']?.toString(),
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        distance: distance,
        elevationGain: parseDistance(json['elevation_gain_meters'] ?? json['elevationGain'] ?? 0.0),
        elevationLoss: parseDistance(json['elevation_loss_meters'] ?? json['elevationLoss'] ?? 0.0),
        caloriesBurned: (json['calories_burned'] ?? json['caloriesBurned'] ?? 0) is int
            ? (json['calories_burned'] ?? json['caloriesBurned'] ?? 0)
            : (json['calories_burned'] ?? json['caloriesBurned'] ?? 0).toInt(),
        averagePace: parseDistance(json['average_pace'] ?? json['averagePace'] ?? 0.0),
        ruckWeightKg: parseDistance(json['ruck_weight_kg'] ?? json['ruckWeightKg'] ?? 0.0),
        status: status,
        notes: json['notes']?.toString(),
        rating: json['rating'] is int ? json['rating'] : null,
        locationPoints: json['location_points'] is List ? 
            (json['location_points'] as List).cast<Map<String, dynamic>>() : null,
        finalElevationGain: (json['final_elevation_gain'] as num?)?.toDouble(),
        finalElevationLoss: (json['final_elevation_loss'] as num?)?.toDouble(),
        heartRateSamples: json['heart_rate_samples'] != null
            ? (json['heart_rate_samples'] as List)
                .map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        avgHeartRate: json['avg_heart_rate'] as int?,
        maxHeartRate: json['max_heart_rate'] as int?,
        minHeartRate: json['min_heart_rate'] as int?,
      );
    } catch (e) {
      AppLogger.error('Error parsing RuckSession from JSON: $e');
      // Return a default session with the ID if available
      return RuckSession(
        id: json['id']?.toString() ?? 'unknown',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now(),
        duration: const Duration(),
        distance: 0,
        elevationGain: 0,
        elevationLoss: 0,
        caloriesBurned: 0,
        averagePace: 0,
        ruckWeightKg: 0,
        status: RuckStatus.unknown,
        notes: null,
        rating: null,
        locationPoints: null,
        finalElevationGain: null,
        finalElevationLoss: null,
        heartRateSamples: null,
        avgHeartRate: null,
        maxHeartRate: null,
        minHeartRate: null,
      );
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
    };
  }
}
