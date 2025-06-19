/// Model for tracking terrain data during a session
class TerrainSegment {
  final double distanceKm;
  final String surfaceType;
  final double energyMultiplier;
  final DateTime timestamp;
  
  const TerrainSegment({
    required this.distanceKm,
    required this.surfaceType,
    required this.energyMultiplier,
    required this.timestamp,
  });
  
  /// Calculate weighted average terrain multiplier for a list of segments
  static double calculateWeightedTerrainMultiplier(List<TerrainSegment> segments) {
    if (segments.isEmpty) return 1.0;
    
    double totalDistance = 0;
    double weightedSum = 0;
    
    for (final segment in segments) {
      totalDistance += segment.distanceKm;
      weightedSum += segment.distanceKm * segment.energyMultiplier;
    }
    
    return totalDistance > 0 ? weightedSum / totalDistance : 1.0;
  }
  
  /// Get terrain statistics for a session
  static Map<String, dynamic> getTerrainStats(List<TerrainSegment> segments) {
    if (segments.isEmpty) {
      return {
        'total_distance_km': 0.0,
        'weighted_multiplier': 1.0,
        'surface_breakdown': <String, double>{},
        'most_common_surface': 'paved',
      };
    }
    
    double totalDistance = 0;
    final Map<String, double> surfaceDistances = {};
    
    for (final segment in segments) {
      totalDistance += segment.distanceKm;
      surfaceDistances[segment.surfaceType] = 
          (surfaceDistances[segment.surfaceType] ?? 0) + segment.distanceKm;
    }
    
    // Find most common surface by distance
    String mostCommonSurface = 'paved';
    double maxDistance = 0;
    surfaceDistances.forEach((surface, distance) {
      if (distance > maxDistance) {
        maxDistance = distance;
        mostCommonSurface = surface;
      }
    });
    
    return {
      'total_distance_km': totalDistance,
      'weighted_multiplier': calculateWeightedTerrainMultiplier(segments),
      'surface_breakdown': surfaceDistances,
      'most_common_surface': mostCommonSurface,
    };
  }
  
  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'distanceKm': distanceKm,
      'surfaceType': surfaceType,
      'energyMultiplier': energyMultiplier,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  /// Create from JSON for deserialization
  factory TerrainSegment.fromJson(Map<String, dynamic> json) {
    return TerrainSegment(
      distanceKm: (json['distanceKm'] as num).toDouble(),
      surfaceType: json['surfaceType'] as String,
      energyMultiplier: (json['energyMultiplier'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  @override
  String toString() => 'TerrainSegment(distance: ${distanceKm}km, surface: $surfaceType, multiplier: $energyMultiplier)';
}
