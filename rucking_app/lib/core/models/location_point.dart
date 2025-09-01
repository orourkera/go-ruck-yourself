import 'dart:convert' show utf8;
import 'package:crypto/crypto.dart' show sha256;
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

  final bool isEstimated;

  final String uniqueId;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.timestamp,
    required this.accuracy,
    this.speed,
    this.isEstimated = false,  // Default to false for real GPS points
    String? uniqueId,
  }) : uniqueId = uniqueId ?? _generateId(timestamp, latitude, longitude);

  static String _generateId(DateTime timestamp, double lat, double lng) {
    final input = '${timestamp.toIso8601String()}-$lat-$lng';
    return sha256.convert(utf8.encode(input)).toString().substring(0, 16); // Truncated for brevity
  }
  
  @override
  List<Object?> get props => [latitude, longitude, elevation, timestamp, accuracy, speed, isEstimated, uniqueId];
  
  /// Create a LocationPoint from JSON
  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.parse(json['timestamp'] as String);
    final latitude = (json['latitude'] as num).toDouble();
    final longitude = (json['longitude'] as num).toDouble();
    return LocationPoint(
      latitude: latitude,
      longitude: longitude,
      elevation: (json['elevation_meters'] as num).toDouble(),
      timestamp: timestamp,
      accuracy: (json['accuracy_meters'] as num).toDouble(),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      isEstimated: json['is_estimated'] as bool? ?? false,
      uniqueId: json['unique_id'] as String?,
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
      'accuracy': accuracy,  // Backend expects 'accuracy', not 'accuracy_meters'
      'accuracy_meters': accuracy,  // Keep for compatibility
      if (speed != null) 'speed': speed,
      if (speed != null) 'heading': 0.0,  // Add heading field expected by backend
      'is_estimated': isEstimated,
      'unique_id': uniqueId,
    };
  }
} 