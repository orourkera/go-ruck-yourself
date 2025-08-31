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
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      elevation: json['elevation_meters'] as double,
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: json['accuracy_meters'] as double,
      speed: json['speed'] != null ? json['speed'] as double : null,
    );
  }
  
  /// Convert LocationPoint to JSON
  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,  // Backend expects 'lat' for route-chunk endpoint
      'lng': longitude,  // Backend expects 'lng' for route-chunk endpoint
      'latitude': latitude,  // Keep for compatibility with other endpoints
      'longitude': longitude,  // Keep for compatibility with other endpoints
      'altitude': elevation,  // Backend expects 'altitude', not 'elevation_meters'
      'elevation_meters': elevation,  // Keep for compatibility
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,  // Backend expects 'accuracy', not 'accuracy_meters'
      'accuracy_meters': accuracy,  // Keep for compatibility
      if (speed != null) 'speed': speed,
      if (speed != null) 'heading': 0.0,  // Add heading field expected by backend
      'unique_id': uniqueId,
    };
  }
} 