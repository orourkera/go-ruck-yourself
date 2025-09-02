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

  /// Vertical accuracy in meters (optional)
  final double? verticalAccuracyM;

  /// Speed accuracy in meters per second (optional)
  final double? speedAccuracyMps;

  /// Course/bearing in degrees (0-360, optional)
  final double? courseDeg;

  /// Course accuracy in degrees (optional)
  final double? courseAccuracyDeg;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.timestamp,
    required this.accuracy,
    this.speed,
    this.verticalAccuracyM,
    this.speedAccuracyMps,
    this.courseDeg,
    this.courseAccuracyDeg,
  });
  
  @override
  List<Object?> get props => [
    latitude,
    longitude,
    elevation,
    timestamp,
    accuracy,
    speed,
    verticalAccuracyM,
    speedAccuracyMps,
    courseDeg,
    courseAccuracyDeg,
  ];
  
  /// Create a LocationPoint from JSON
  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] as num).toDouble();
    final lng = (json['longitude'] as num).toDouble();
    final elevation = (json['elevation_meters'] ?? json['altitude']) as num;
    final horizontalAccuracy = (json['accuracy_meters'] ?? json['accuracy'] ?? json['horizontal_accuracy_m']) as num;
    final speed = json['speed'] ?? json['speed_mps'];
    return LocationPoint(
      latitude: lat,
      longitude: lng,
      elevation: (elevation as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: (horizontalAccuracy as num).toDouble(),
      speed: speed != null ? (speed as num).toDouble() : null,
      verticalAccuracyM: (json['vertical_accuracy_m'] as num?)?.toDouble(),
      speedAccuracyMps: (json['speed_accuracy_mps'] as num?)?.toDouble(),
      courseDeg: (json['course_deg'] as num?)?.toDouble(),
      courseAccuracyDeg: (json['course_accuracy_deg'] as num?)?.toDouble(),
    );
  }
  
  /// Convert LocationPoint to JSON
  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,  // Backend expects 'lat' format
      'lng': longitude,  // Backend expects 'lng' format
      'latitude': latitude,  // Keep for compatibility with other endpoints
      'longitude': longitude,  // Keep for compatibility with other endpoints
      'altitude': elevation,  // Backend expects 'altitude', not 'elevation_meters'
      'elevation_meters': elevation,  // Keep for compatibility
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,  // Legacy compatibility
      'accuracy_meters': accuracy,  // Legacy compatibility
      'horizontal_accuracy_m': accuracy,
      if (verticalAccuracyM != null) 'vertical_accuracy_m': verticalAccuracyM,
      if (speed != null) 'speed': speed, // Legacy
      if (speed != null) 'speed_mps': speed,
      if (speedAccuracyMps != null) 'speed_accuracy_mps': speedAccuracyMps,
      if (courseDeg != null) 'heading': courseDeg,
      if (courseDeg != null) 'course_deg': courseDeg,
      if (courseAccuracyDeg != null) 'course_accuracy_deg': courseAccuracyDeg,
      // Generate a unique ID based on timestamp and coordinates
      'unique_id': '${timestamp.millisecondsSinceEpoch}_${latitude.toStringAsFixed(6)}_${longitude.toStringAsFixed(6)}',
    };
  }
} 