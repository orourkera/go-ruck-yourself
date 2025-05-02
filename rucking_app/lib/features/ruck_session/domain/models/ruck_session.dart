import 'package:intl/intl.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

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
  final String? notes;
  final int? rating;
  final List<Map<String, dynamic>>? locationPoints;

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
    this.notes,
    this.rating,
    this.locationPoints,
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
        notes: json['notes']?.toString(),
        rating: json['rating'] is int ? json['rating'] : null,
        locationPoints: json['location_points'] is List ? 
            (json['location_points'] as List).cast<Map<String, dynamic>>() : null,
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
      );
    }
  }

  /// Convert the RuckSession to a JSON map
  Map<String, dynamic> toJson() {
    final dateFormat = DateFormat("yyyy-MM-ddTHH:mm:ss");
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
      'notes': notes,
      'rating': rating,
      'location_points': locationPoints,
    };
  }
}
