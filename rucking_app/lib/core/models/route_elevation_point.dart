import 'package:equatable/equatable.dart';

/// Route elevation point model for detailed elevation profiles
/// Represents a single point along a route with elevation and gradient data
class RouteElevationPoint extends Equatable {
  const RouteElevationPoint({
    this.id,
    required this.routeId,
    required this.distanceKm,
    required this.elevationM,
    this.latitude,
    this.longitude,
    this.terrainType,
    this.gradePercent,
    this.createdAt,
  });

  // Core identification
  final String? id;
  final String routeId;

  // Position data
  final double distanceKm; // Distance from route start
  final double elevationM; // Elevation above sea level
  final double? latitude;
  final double? longitude;

  // Terrain and gradient data
  final String? terrainType; // 'paved', 'dirt', 'gravel', 'rock', 'grass'
  final double? gradePercent; // Gradient percentage (positive = uphill, negative = downhill)

  // Metadata
  final DateTime? createdAt;

  @override
  List<Object?> get props => [
        id,
        routeId,
        distanceKm,
        elevationM,
        latitude,
        longitude,
        terrainType,
        gradePercent,
        createdAt,
      ];

  /// Create RouteElevationPoint from API JSON response
  factory RouteElevationPoint.fromJson(Map<String, dynamic> json) {
    return RouteElevationPoint(
      id: json['id'] as String?,
      routeId: json['route_id'] as String,
      distanceKm: (json['distance_km'] as num).toDouble(),
      elevationM: (json['elevation_m'] as num).toDouble(),
      latitude: json['latitude'] != null 
          ? (json['latitude'] as num).toDouble() 
          : null,
      longitude: json['longitude'] != null 
          ? (json['longitude'] as num).toDouble() 
          : null,
      terrainType: json['terrain_type'] as String?,
      gradePercent: json['grade_percent'] != null 
          ? (json['grade_percent'] as num).toDouble() 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : null,
    );
  }

  /// Convert RouteElevationPoint to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'route_id': routeId,
      'distance_km': distanceKm,
      'elevation_m': elevationM,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (terrainType != null) 'terrain_type': terrainType,
      if (gradePercent != null) 'grade_percent': gradePercent,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  /// Create a copy of this RouteElevationPoint with updated fields
  RouteElevationPoint copyWith({
    String? id,
    String? routeId,
    double? distanceKm,
    double? elevationM,
    double? latitude,
    double? longitude,
    String? terrainType,
    double? gradePercent,
    DateTime? createdAt,
  }) {
    return RouteElevationPoint(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      distanceKm: distanceKm ?? this.distanceKm,
      elevationM: elevationM ?? this.elevationM,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      terrainType: terrainType ?? this.terrainType,
      gradePercent: gradePercent ?? this.gradePercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Helper methods and computed properties

  /// Get formatted distance from start
  String get formattedDistance {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).toStringAsFixed(0)}m';
    } else {
      return '${distanceKm.toStringAsFixed(1)}km';
    }
  }

  /// Get formatted elevation
  String get formattedElevation {
    return '${elevationM.toStringAsFixed(0)}m';
  }

  /// Get formatted grade percentage
  String get formattedGrade {
    if (gradePercent == null) return 'Unknown grade';
    
    final absGrade = gradePercent!.abs();
    final direction = gradePercent! >= 0 ? 'uphill' : 'downhill';
    
    return '${absGrade.toStringAsFixed(1)}% $direction';
  }

  /// Get grade category for UI styling
  GradeCategory get gradeCategory {
    if (gradePercent == null) return GradeCategory.flat;
    
    final absGrade = gradePercent!.abs();
    
    if (absGrade < 3) {
      return GradeCategory.flat;
    } else if (absGrade < 8) {
      return GradeCategory.gentle;
    } else if (absGrade < 15) {
      return GradeCategory.moderate;
    } else if (absGrade < 25) {
      return GradeCategory.steep;
    } else {
      return GradeCategory.extreme;
    }
  }

  /// Check if this point represents uphill
  bool get isUphill => gradePercent != null && gradePercent! > 1;

  /// Check if this point represents downhill  
  bool get isDownhill => gradePercent != null && gradePercent! < -1;

  /// Check if this point is relatively flat
  bool get isFlat => gradePercent != null && gradePercent!.abs() <= 1;

  /// Get terrain type as enum for easier handling
  TerrainType get terrain {
    switch (terrainType?.toLowerCase()) {
      case 'paved':
        return TerrainType.paved;
      case 'dirt':
        return TerrainType.dirt;
      case 'gravel':
        return TerrainType.gravel;
      case 'rock':
        return TerrainType.rock;
      case 'grass':
        return TerrainType.grass;
      case 'sand':
        return TerrainType.sand;
      case 'snow':
        return TerrainType.snow;
      default:
        return TerrainType.mixed;
    }
  }

  /// Check if coordinates are available
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Calculate distance between this point and another point (in meters)
  double distanceToPoint(RouteElevationPoint other) {
    if (!hasCoordinates || !other.hasCoordinates) {
      return 0.0;
    }
    
    return _haversineDistance(
      latitude!, longitude!, 
      other.latitude!, other.longitude!
    );
  }

  /// Calculate elevation change from this point to another
  double elevationChangeTo(RouteElevationPoint other) {
    return other.elevationM - elevationM;
  }

  /// Haversine distance calculation
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    // Convert degrees to radians
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = 
        (dLat / 2).sin() * (dLat / 2).sin() +
        lat1.toRadians().cos() * lat2.toRadians().cos() *
        (dLon / 2).sin() * (dLon / 2).sin();
    
    final double c = 2 * (a.sqrt()).asin();
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (3.14159265359 / 180);
}

/// Extension for easier radian conversion
extension on double {
  double toRadians() => this * (3.14159265359 / 180);
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double asin() => math.asin(this);
  double sqrt() => math.sqrt(this);
}

// Import dart:math for mathematical functions
import 'dart:math' as math;

/// Grade categories for UI styling and difficulty assessment
enum GradeCategory {
  flat,
  gentle,
  moderate,
  steep,
  extreme;

  String get displayName {
    switch (this) {
      case GradeCategory.flat:
        return 'Flat';
      case GradeCategory.gentle:
        return 'Gentle';
      case GradeCategory.moderate:
        return 'Moderate';
      case GradeCategory.steep:
        return 'Steep';
      case GradeCategory.extreme:
        return 'Extreme';
    }
  }

  String get description {
    switch (this) {
      case GradeCategory.flat:
        return 'Easy walking (0-3% grade)';
      case GradeCategory.gentle:
        return 'Slight incline (3-8% grade)';
      case GradeCategory.moderate:
        return 'Noticeable climb (8-15% grade)';
      case GradeCategory.steep:
        return 'Challenging climb (15-25% grade)';
      case GradeCategory.extreme:
        return 'Very steep (>25% grade)';
    }
  }
}

/// Terrain types for surface conditions
enum TerrainType {
  paved,
  dirt,
  gravel,
  rock,
  grass,
  sand,
  snow,
  mixed;

  String get displayName {
    switch (this) {
      case TerrainType.paved:
        return 'Paved';
      case TerrainType.dirt:
        return 'Dirt';
      case TerrainType.gravel:
        return 'Gravel';
      case TerrainType.rock:
        return 'Rock';
      case TerrainType.grass:
        return 'Grass';
      case TerrainType.sand:
        return 'Sand';
      case TerrainType.snow:
        return 'Snow';
      case TerrainType.mixed:
        return 'Mixed';
    }
  }

  String get description {
    switch (this) {
      case TerrainType.paved:
        return 'Smooth paved surface';
      case TerrainType.dirt:
        return 'Natural dirt trail';
      case TerrainType.gravel:
        return 'Gravel or crushed stone';
      case TerrainType.rock:
        return 'Rocky terrain';
      case TerrainType.grass:
        return 'Grassy surface';
      case TerrainType.sand:
        return 'Sandy surface';
      case TerrainType.snow:
        return 'Snow covered';
      case TerrainType.mixed:
        return 'Various surface types';
    }
  }
}
