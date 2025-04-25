import 'package:equatable/equatable.dart';

/// Represents a GPS location point with timestamp and accuracy data
class LocationPoint extends Equatable {
  /// Latitude in decimal degrees
  final double latitude;
  
  /// Longitude in decimal degrees
  final double longitude;
  
  /// Elevation above sea level in meters
  final double elevation;
  
  /// Timestamp when the point was recorded
  final DateTime timestamp;
  
  /// Accuracy of the reading in meters
  final double accuracy;
  
  /// Speed in meters per second (optional)
  final double? speed;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.timestamp,
    required this.accuracy,
    this.speed,
  });
  
  @override
  List<Object?> get props => [latitude, longitude, elevation, timestamp, accuracy, speed];
  
  /// Create a LocationPoint from JSON
  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      elevation: (json['elevation_meters'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: (json['accuracy_meters'] as num).toDouble(),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
    );
  }
  
  /// Convert LocationPoint to JSON
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'elevation_meters': elevation,
      'timestamp': timestamp.toIso8601String(),
      'accuracy_meters': accuracy,
      if (speed != null) 'speed': speed,
    };
  }
} 