import 'dart:math' as math;
import 'package:equatable/equatable.dart';

/// Route point of interest model for waypoints and landmarks
/// Represents important locations along a route like water sources, rest stops, hazards, etc.
class RoutePointOfInterest extends Equatable {
  const RoutePointOfInterest({
    this.id,
    required this.routeId,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.poiType,
    this.distanceFromStartKm = 0.0,
    this.isUserGenerated = false,
    this.isVerified = false,
    this.createdAt,
  });

  // Core identification
  final String? id;
  final String routeId;

  // Basic information
  final String name;
  final String? description;

  // Location data
  final double latitude;
  final double longitude;
  final double distanceFromStartKm; // Distance from route start

  // POI classification
  final String poiType; // Type of point of interest
  final bool isUserGenerated; // Created by user vs imported
  final bool isVerified; // Verified by moderators or trusted sources

  // Metadata
  final DateTime? createdAt;

  @override
  List<Object?> get props => [
        id,
        routeId,
        name,
        description,
        latitude,
        longitude,
        poiType,
        distanceFromStartKm,
        isUserGenerated,
        isVerified,
        createdAt,
      ];

  /// Create RoutePointOfInterest from API JSON response
  factory RoutePointOfInterest.fromJson(Map<String, dynamic> json) {
    return RoutePointOfInterest(
      id: json['id'] as String?,
      routeId: json['route_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      poiType: json['poi_type'] as String,
      distanceFromStartKm: json['distance_from_start_km'] != null
          ? (json['distance_from_start_km'] as num).toDouble()
          : 0.0,
      isUserGenerated: json['is_user_generated'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  /// Convert RoutePointOfInterest to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'route_id': routeId,
      'name': name,
      if (description != null) 'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'poi_type': poiType,
      'distance_from_start_km': distanceFromStartKm,
      'is_user_generated': isUserGenerated,
      'is_verified': isVerified,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  /// Create a copy of this RoutePointOfInterest with updated fields
  RoutePointOfInterest copyWith({
    String? id,
    String? routeId,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    String? poiType,
    double? distanceFromStartKm,
    bool? isUserGenerated,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return RoutePointOfInterest(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      name: name ?? this.name,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      poiType: poiType ?? this.poiType,
      distanceFromStartKm: distanceFromStartKm ?? this.distanceFromStartKm,
      isUserGenerated: isUserGenerated ?? this.isUserGenerated,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Helper methods and computed properties

  /// Get POI type as enum for easier handling
  PoiType get type {
    switch (poiType.toLowerCase()) {
      case 'water':
        return PoiType.water;
      case 'restroom':
        return PoiType.restroom;
      case 'parking':
        return PoiType.parking;
      case 'viewpoint':
        return PoiType.viewpoint;
      case 'trailhead':
        return PoiType.trailhead;
      case 'shelter':
        return PoiType.shelter;
      case 'food':
        return PoiType.food;
      case 'hazard':
        return PoiType.hazard;
      case 'intersection':
        return PoiType.intersection;
      case 'landmark':
        return PoiType.landmark;
      case 'camping':
        return PoiType.camping;
      case 'bridge':
        return PoiType.bridge;
      case 'gate':
        return PoiType.gate;
      case 'waypoint':
        return PoiType.waypoint;
      default:
        return PoiType.other;
    }
  }

  /// Get formatted distance from route start
  String get formattedDistanceFromStart {
    if (distanceFromStartKm < 1) {
      return '${(distanceFromStartKm * 1000).toStringAsFixed(0)}m from start';
    } else {
      return '${distanceFromStartKm.toStringAsFixed(1)}km from start';
    }
  }

  /// Get display title with verification status
  String get displayTitle {
    String title = name;
    if (isVerified) {
      title += ' ✓';
    }
    return title;
  }

  /// Get appropriate description with fallback
  String get displayDescription {
    return description?.isNotEmpty == true
        ? description!
        : type.defaultDescription;
  }

  /// Check if this POI is critical for safety/planning
  bool get isCritical {
    return type.isCritical;
  }

  /// Check if this POI provides amenities
  bool get providesAmenities {
    return type.providesAmenities;
  }

  /// Calculate distance to another POI or coordinate
  double distanceTo(double otherLat, double otherLng) {
    return _haversineDistance(latitude, longitude, otherLat, otherLng);
  }

  /// Haversine distance calculation (returns meters)
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    // Convert degrees to radians
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = (dLat / 2).sin() * (dLat / 2).sin() +
        lat1.toRadians().cos() *
            lat2.toRadians().cos() *
            (dLon / 2).sin() *
            (dLon / 2).sin();

    final double c = 2 * (a.sqrt()).asin();

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (3.14159265359 / 180);
}

/// Extension for easier radian conversion and math operations
extension on double {
  double toRadians() => this * (3.14159265359 / 180);
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double asin() => math.asin(this);
  double sqrt() => math.sqrt(this);
}

/// Point of Interest types with metadata
enum PoiType {
  water,
  restroom,
  parking,
  viewpoint,
  trailhead,
  shelter,
  food,
  hazard,
  intersection,
  landmark,
  camping,
  bridge,
  gate,
  waypoint,
  other;

  String get displayName {
    switch (this) {
      case PoiType.water:
        return 'Water Source';
      case PoiType.restroom:
        return 'Restroom';
      case PoiType.parking:
        return 'Parking';
      case PoiType.viewpoint:
        return 'Viewpoint';
      case PoiType.trailhead:
        return 'Trailhead';
      case PoiType.shelter:
        return 'Shelter';
      case PoiType.food:
        return 'Food/Store';
      case PoiType.hazard:
        return 'Hazard';
      case PoiType.intersection:
        return 'Trail Junction';
      case PoiType.landmark:
        return 'Landmark';
      case PoiType.camping:
        return 'Camping';
      case PoiType.bridge:
        return 'Bridge';
      case PoiType.gate:
        return 'Gate';
      case PoiType.waypoint:
        return 'Waypoint';
      case PoiType.other:
        return 'Point of Interest';
    }
  }

  String get defaultDescription {
    switch (this) {
      case PoiType.water:
        return 'Water source for refilling bottles';
      case PoiType.restroom:
        return 'Restroom facilities available';
      case PoiType.parking:
        return 'Parking area';
      case PoiType.viewpoint:
        return 'Scenic viewpoint';
      case PoiType.trailhead:
        return 'Trail starting point';
      case PoiType.shelter:
        return 'Shelter or covered area';
      case PoiType.food:
        return 'Food or supply store';
      case PoiType.hazard:
        return 'Caution: potential hazard';
      case PoiType.intersection:
        return 'Trail intersection - check direction';
      case PoiType.landmark:
        return 'Notable landmark';
      case PoiType.camping:
        return 'Camping area';
      case PoiType.bridge:
        return 'Bridge crossing';
      case PoiType.gate:
        return 'Gate - may have access restrictions';
      case PoiType.waypoint:
        return 'Navigation waypoint';
      case PoiType.other:
        return 'Point of interest';
    }
  }

  /// Check if this POI type is critical for safety or navigation
  bool get isCritical {
    switch (this) {
      case PoiType.hazard:
      case PoiType.intersection:
      case PoiType.gate:
        return true;
      default:
        return false;
    }
  }

  /// Check if this POI type provides amenities
  bool get providesAmenities {
    switch (this) {
      case PoiType.water:
      case PoiType.restroom:
      case PoiType.shelter:
      case PoiType.food:
      case PoiType.parking:
      case PoiType.camping:
        return true;
      default:
        return false;
    }
  }

  /// Get icon name for UI display
  String get iconName {
    switch (this) {
      case PoiType.water:
        return 'water_drop';
      case PoiType.restroom:
        return 'wc';
      case PoiType.parking:
        return 'local_parking';
      case PoiType.viewpoint:
        return 'landscape';
      case PoiType.trailhead:
        return 'flag';
      case PoiType.shelter:
        return 'home';
      case PoiType.food:
        return 'restaurant';
      case PoiType.hazard:
        return 'warning';
      case PoiType.intersection:
        return 'alt_route';
      case PoiType.landmark:
        return 'place';
      case PoiType.camping:
        return 'camping';
      case PoiType.bridge:
        return 'bridge';
      case PoiType.gate:
        return 'gate';
      case PoiType.waypoint:
        return 'location_on';
      case PoiType.other:
        return 'place';
    }
  }

  /// Get priority level for display order (higher = more important)
  int get priority {
    switch (this) {
      case PoiType.hazard:
        return 10;
      case PoiType.trailhead:
        return 9;
      case PoiType.intersection:
        return 8;
      case PoiType.water:
        return 7;
      case PoiType.restroom:
        return 6;
      case PoiType.shelter:
        return 5;
      case PoiType.viewpoint:
        return 4;
      case PoiType.parking:
        return 3;
      case PoiType.food:
        return 3;
      case PoiType.camping:
        return 3;
      case PoiType.bridge:
        return 2;
      case PoiType.gate:
        return 2;
      case PoiType.landmark:
        return 1;
      case PoiType.waypoint:
        return 1;
      case PoiType.other:
        return 0;
    }
  }
}
