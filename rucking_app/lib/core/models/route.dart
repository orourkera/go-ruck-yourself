import 'package:equatable/equatable.dart';
import 'route_elevation_point.dart';
import 'route_point_of_interest.dart';

/// Core route model for AllTrails integration
/// Represents a shareable route with geographic data, difficulty, and metadata
class Route extends Equatable {
  const Route({
    this.id,
    required this.name,
    this.description,
    required this.source,
    this.externalId,
    this.externalUrl,
    required this.routePolyline,
    required this.startLatitude,
    required this.startLongitude,
    this.endLatitude,
    this.endLongitude,
    required this.distanceKm,
    this.elevationGainM,
    this.elevationLossM,
    this.trailDifficulty,
    this.trailType,
    this.surfaceType,
    this.totalPlannedCount = 0,
    this.totalCompletedCount = 0,
    this.averageRating,
    this.isPublic = false,
    this.isVerified = false,
    this.createdByUserId,
    this.createdAt,
    this.updatedAt,
    this.elevationPoints = const [],
    this.pointsOfInterest = const [],
  });

  // Core identification
  final String? id;
  final String name;
  final String? description;
  final String source; // 'alltrails', 'custom', 'gpx_import', 'community'
  final String? externalId; // External route ID (e.g., AllTrails route ID)
  final String? externalUrl; // Link to original route source

  // Geographic data
  final String routePolyline; // Encoded polyline or coordinate string
  final double startLatitude;
  final double startLongitude;
  final double? endLatitude;
  final double? endLongitude;

  // Route metrics
  final double distanceKm;
  final double? elevationGainM;
  final double? elevationLossM;

  // Route characteristics
  final String? trailDifficulty; // 'easy', 'moderate', 'hard', 'extreme'
  final String? trailType; // 'loop', 'out_and_back', 'point_to_point'
  final String? surfaceType; // 'paved', 'dirt', 'gravel', 'mixed', 'varied'

  // Community data
  final int totalPlannedCount;
  final int totalCompletedCount;
  final double? averageRating; // 1-5 stars from user ratings

  // Privacy and verification
  final bool isPublic;
  final bool isVerified; // Verified routes from trusted sources

  // Metadata
  final String? createdByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Related data (loaded separately)
  final List<RouteElevationPoint> elevationPoints;
  final List<RoutePointOfInterest> pointsOfInterest;

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        source,
        externalId,
        externalUrl,
        routePolyline,
        startLatitude,
        startLongitude,
        endLatitude,
        endLongitude,
        distanceKm,
        elevationGainM,
        elevationLossM,
        trailDifficulty,
        trailType,
        surfaceType,
        totalPlannedCount,
        totalCompletedCount,
        averageRating,
        isPublic,
        isVerified,
        createdByUserId,
        createdAt,
        updatedAt,
        elevationPoints,
        pointsOfInterest,
      ];

  /// Create Route from API JSON response
  factory Route.fromJson(Map<String, dynamic> json) {
    return Route(
      id: json['id'] as String?,
      name: json['name']?.toString() ?? 'Unknown Route',
      description: json['description'] as String?,
      source: json['source']?.toString() ?? 'unknown',
      externalId: json['external_id'] as String?,
      externalUrl: json['external_url'] as String?,
      routePolyline: json['route_polyline']?.toString() ?? '',
      startLatitude: json['start_latitude'] != null ? (json['start_latitude'] as num).toDouble() : 0.0,
      startLongitude: json['start_longitude'] != null ? (json['start_longitude'] as num).toDouble() : 0.0,
      endLatitude: json['end_latitude'] != null 
          ? (json['end_latitude'] as num).toDouble() 
          : null,
      endLongitude: json['end_longitude'] != null 
          ? (json['end_longitude'] as num).toDouble() 
          : null,
      distanceKm: (json['distance_km'] as num).toDouble(),
      elevationGainM: json['elevation_gain_m'] != null 
          ? (json['elevation_gain_m'] as num).toDouble() 
          : null,
      elevationLossM: json['elevation_loss_m'] != null 
          ? (json['elevation_loss_m'] as num).toDouble() 
          : null,
      trailDifficulty: json['trail_difficulty'] as String?,
      trailType: json['trail_type'] as String?,
      surfaceType: json['surface_type'] as String?,
      totalPlannedCount: json['total_planned_count'] as int? ?? 0,
      totalCompletedCount: json['total_completed_count'] as int? ?? 0,
      averageRating: json['average_rating'] != null 
          ? (json['average_rating'] as num).toDouble() 
          : null,
      isPublic: json['is_public'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      createdByUserId: json['created_by_user_id'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : null,
      elevationPoints: json['elevation_points'] != null
          ? (json['elevation_points'] as List)
              .map((e) => RouteElevationPoint.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      pointsOfInterest: json['points_of_interest'] != null
          ? (json['points_of_interest'] as List)
              .map((e) => RoutePointOfInterest.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  /// Convert Route to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (description != null) 'description': description,
      'source': source,
      if (externalId != null) 'external_id': externalId,
      if (externalUrl != null) 'external_url': externalUrl,
      'route_polyline': routePolyline,
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      if (endLatitude != null) 'end_latitude': endLatitude,
      if (endLongitude != null) 'end_longitude': endLongitude,
      'distance_km': distanceKm,
      if (elevationGainM != null) 'elevation_gain_m': elevationGainM,
      if (elevationLossM != null) 'elevation_loss_m': elevationLossM,
      if (trailDifficulty != null) 'trail_difficulty': trailDifficulty,
      if (trailType != null) 'trail_type': trailType,
      if (surfaceType != null) 'surface_type': surfaceType,
      'total_planned_count': totalPlannedCount,
      'total_completed_count': totalCompletedCount,
      if (averageRating != null) 'average_rating': averageRating,
      'is_public': isPublic,
      'is_verified': isVerified,
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (elevationPoints.isNotEmpty) 
        'elevation_points': elevationPoints.map((e) => e.toJson()).toList(),
      if (pointsOfInterest.isNotEmpty) 
        'points_of_interest': pointsOfInterest.map((e) => e.toJson()).toList(),
    };
  }

  /// Create a copy of this Route with updated fields
  Route copyWith({
    String? id,
    String? name,
    String? description,
    String? source,
    String? externalId,
    String? externalUrl,
    String? routePolyline,
    double? startLatitude,
    double? startLongitude,
    double? endLatitude,
    double? endLongitude,
    double? distanceKm,
    double? elevationGainM,
    double? elevationLossM,
    String? trailDifficulty,
    String? trailType,
    String? surfaceType,
    int? totalPlannedCount,
    int? totalCompletedCount,
    double? averageRating,
    bool? isPublic,
    bool? isVerified,
    String? createdByUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<RouteElevationPoint>? elevationPoints,
    List<RoutePointOfInterest>? pointsOfInterest,
  }) {
    return Route(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      externalUrl: externalUrl ?? this.externalUrl,
      routePolyline: routePolyline ?? this.routePolyline,
      startLatitude: startLatitude ?? this.startLatitude,
      startLongitude: startLongitude ?? this.startLongitude,
      endLatitude: endLatitude ?? this.endLatitude,
      endLongitude: endLongitude ?? this.endLongitude,
      distanceKm: distanceKm ?? this.distanceKm,
      elevationGainM: elevationGainM ?? this.elevationGainM,
      elevationLossM: elevationLossM ?? this.elevationLossM,
      trailDifficulty: trailDifficulty ?? this.trailDifficulty,
      trailType: trailType ?? this.trailType,
      surfaceType: surfaceType ?? this.surfaceType,
      totalPlannedCount: totalPlannedCount ?? this.totalPlannedCount,
      totalCompletedCount: totalCompletedCount ?? this.totalCompletedCount,
      averageRating: averageRating ?? this.averageRating,
      isPublic: isPublic ?? this.isPublic,
      isVerified: isVerified ?? this.isVerified,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      elevationPoints: elevationPoints ?? this.elevationPoints,
      pointsOfInterest: pointsOfInterest ?? this.pointsOfInterest,
    );
  }

  // Computed properties and helper methods

  /// Get difficulty level as enum for easier handling
  RouteDifficulty get difficultyLevel {
    switch (trailDifficulty?.toLowerCase()) {
      case 'easy':
        return RouteDifficulty.easy;
      case 'moderate':
        return RouteDifficulty.moderate;
      case 'hard':
        return RouteDifficulty.hard;
      case 'extreme':
        return RouteDifficulty.extreme;
      default:
        return RouteDifficulty.moderate;
    }
  }

  /// Get trail type as enum for easier handling
  RouteType get routeType {
    switch (trailType?.toLowerCase()) {
      case 'loop':
        return RouteType.loop;
      case 'out_and_back':
        return RouteType.outAndBack;
      case 'point_to_point':
        return RouteType.pointToPoint;
      default:
        return RouteType.outAndBack;
    }
  }

  /// Get formatted distance string
  String get formattedDistance {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).toStringAsFixed(0)}m';
    } else {
      return '${distanceKm.toStringAsFixed(1)}km';
    }
  }

  /// Get formatted elevation gain string
  String get formattedElevationGain {
    if (elevationGainM == null) return 'Unknown elevation';
    return '${elevationGainM!.toStringAsFixed(0)}m elevation';
  }

  /// Get popularity score based on usage
  double get popularityScore {
    if (totalCompletedCount == 0) return 0.0;
    
    double score = totalCompletedCount * 10.0;
    
    // Bonus for high rating
    if (averageRating != null && averageRating! >= 4.0) {
      score += averageRating! * 5;
    }
    
    // Bonus for verified routes
    if (isVerified) {
      score += 10;
    }
    
    return score.clamp(0.0, 100.0);
  }

  /// Check if route has elevation profile data
  bool get hasElevationProfile => elevationPoints.isNotEmpty;

  /// Check if route has points of interest
  bool get hasPointsOfInterest => pointsOfInterest.isNotEmpty;

  /// Get estimated duration in minutes based on difficulty and distance
  int get estimatedDurationMinutes {
    // Base pace in minutes per km
    double pacePerKm = switch (difficultyLevel) {
      RouteDifficulty.easy => 12.0,
      RouteDifficulty.moderate => 15.0,
      RouteDifficulty.hard => 18.0,
      RouteDifficulty.extreme => 22.0,
    };
    
    // Adjust for elevation gain
    if (elevationGainM != null && elevationGainM! > 0) {
      double elevationAdjustment = (elevationGainM! / 100) * 2; // 2 minutes per 100m elevation
      pacePerKm += elevationAdjustment;
    }
    
    return (distanceKm * pacePerKm).round();
  }

  /// Get formatted estimated duration
  String get formattedEstimatedDuration {
    final minutes = estimatedDurationMinutes;
    if (minutes < 60) {
      return '${minutes}min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}min';
      }
    }
  }

  /// Check if user can access this route
  bool canUserAccess(String? userId) {
    return isPublic || createdByUserId == userId;
  }

  /// Get source display name
  String get sourceDisplayName {
    switch (source.toLowerCase()) {
      case 'alltrails':
        return 'AllTrails';
      case 'custom':
        return 'Custom Route';
      case 'gpx_import':
        return 'GPX Import';
      case 'community':
        return 'Community';
      default:
        return source;
    }
  }
}

/// Route difficulty levels
enum RouteDifficulty {
  easy,
  moderate,
  hard,
  extreme;

  String get displayName {
    switch (this) {
      case RouteDifficulty.easy:
        return 'Easy';
      case RouteDifficulty.moderate:
        return 'Moderate';
      case RouteDifficulty.hard:
        return 'Hard';
      case RouteDifficulty.extreme:
        return 'Extreme';
    }
  }

  String get description {
    switch (this) {
      case RouteDifficulty.easy:
        return 'Suitable for beginners';
      case RouteDifficulty.moderate:
        return 'Some fitness required';
      case RouteDifficulty.hard:
        return 'Challenging route';
      case RouteDifficulty.extreme:
        return 'Very challenging';
    }
  }
}

/// Route types
enum RouteType {
  loop,
  outAndBack,
  pointToPoint;

  String get displayName {
    switch (this) {
      case RouteType.loop:
        return 'Loop';
      case RouteType.outAndBack:
        return 'Out & Back';
      case RouteType.pointToPoint:
        return 'Point to Point';
    }
  }
}
