import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for querying terrain surface data from OpenStreetMap
class TerrainService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const Duration _requestTimeout = Duration(seconds: 10);
  
  // Cache for surface data to avoid repeated API calls
  static final Map<String, TerrainData> _surfaceCache = {};
  
  /// Get terrain data for a route segment between two GPS points
  static Future<TerrainData> getTerrainForSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    // Create cache key for this segment
    final cacheKey = '${startLat.toStringAsFixed(4)},${startLon.toStringAsFixed(4)}-${endLat.toStringAsFixed(4)},${endLon.toStringAsFixed(4)}';
    
    // Check cache first
    if (_surfaceCache.containsKey(cacheKey)) {
      AppLogger.debug('[TERRAIN] Using cached data for segment: $cacheKey');
      return _surfaceCache[cacheKey]!;
    }
    
    try {
      // Create bounding box around the route segment
      final bbox = _createBoundingBox(startLat, startLon, endLat, endLon);
      
      // Query OSM for surface data
      final surfaceType = await _queryOSMSurface(bbox);
      
      // Create terrain data
      final terrainData = TerrainData(
        surfaceType: surfaceType,
        energyMultiplier: getEnergyMultiplier(surfaceType),
      );
      
      // Cache the result
      _surfaceCache[cacheKey] = terrainData;
      
      AppLogger.debug('[TERRAIN] Found surface: $surfaceType (multiplier: ${terrainData.energyMultiplier}) for segment: $cacheKey');
      
      return terrainData;
      
    } catch (e) {
      AppLogger.error('[TERRAIN] Error getting terrain data: $e');
      
      // Return default (pavement) on error
      final defaultTerrain = TerrainData(
        surfaceType: 'paved',
        energyMultiplier: 1.0,
      );
      
      _surfaceCache[cacheKey] = defaultTerrain;
      return defaultTerrain;
    }
  }
  
  /// Query OpenStreetMap Overpass API for surface data
  static Future<String> _queryOSMSurface(BoundingBox bbox) async {
    // Overpass QL query to find ways with surface tags in the bounding box
    final query = '''
[out:json][timeout:5];
(
  way["highway"]["surface"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["footway"]["surface"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
  way["path"]["surface"](${bbox.south},${bbox.west},${bbox.north},${bbox.east});
);
out tags;
''';
    
    try {
      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=$query',
      ).timeout(_requestTimeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _extractMostCommonSurface(data);
      } else {
        AppLogger.warning('[TERRAIN] OSM API returned status: ${response.statusCode}');
        return 'paved'; // Default fallback
      }
      
    } catch (e) {
      AppLogger.error('[TERRAIN] Error querying OSM: $e');
      return 'paved'; // Default fallback
    }
  }
  
  /// Extract the most common surface type from OSM response
  static String _extractMostCommonSurface(Map<String, dynamic> osmData) {
    final Map<String, int> surfaceCounts = {};
    
    final elements = osmData['elements'] as List<dynamic>? ?? [];
    
    for (final element in elements) {
      final tags = element['tags'] as Map<String, dynamic>? ?? {};
      final surface = tags['surface'] as String?;
      
      if (surface != null) {
        surfaceCounts[surface] = (surfaceCounts[surface] ?? 0) + 1;
      }
    }
    
    if (surfaceCounts.isEmpty) {
      return 'paved'; // Default if no surface data found
    }
    
    // Return the most common surface type
    return surfaceCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
  
  /// Create bounding box around two GPS points with some padding
  static BoundingBox _createBoundingBox(double lat1, double lon1, double lat2, double lon2) {
    const double padding = 0.001; // ~100m padding
    
    return BoundingBox(
      north: [lat1, lat2].reduce((a, b) => a > b ? a : b) + padding,
      south: [lat1, lat2].reduce((a, b) => a < b ? a : b) - padding,
      east: [lon1, lon2].reduce((a, b) => a > b ? a : b) + padding,
      west: [lon1, lon2].reduce((a, b) => a < b ? a : b) - padding,
    );
  }
  
  /// Get energy cost multiplier for different surface types
  static double getEnergyMultiplier(String surfaceType) {
    switch (surfaceType.toLowerCase()) {
      // Paved surfaces (baseline)
      case 'paved':
      case 'asphalt':
      case 'concrete':
        return 1.0;
        
      // Unpaved but firm
      case 'unpaved':
      case 'gravel':
      case 'dirt':
      case 'compacted':
        return 1.15;
        
      // Natural surfaces
      case 'grass':
      case 'earth':
      case 'ground':
        return 1.2;
        
      // Challenging surfaces
      case 'sand':
        return 1.9;
      case 'mud':
        return 1.6;
      case 'snow':
        return 1.3;
      case 'ice':
        return 1.4;
        
      // Rocky/technical terrain
      case 'rock':
      case 'stone':
      case 'cobblestone':
        return 1.4;
        
      // Trail surfaces
      case 'fine_gravel':
        return 1.1;
      case 'wood':
      case 'boardwalk':
        return 1.05;
        
      // Default to paved if unknown
      default:
        AppLogger.debug('[TERRAIN] Unknown surface type: $surfaceType, using default multiplier');
        return 1.0;
    }
  }
  
  /// Clear the surface cache (useful for memory management)
  static void clearCache() {
    _surfaceCache.clear();
    AppLogger.debug('[TERRAIN] Surface cache cleared');
  }
  
  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'cached_segments': _surfaceCache.length,
      'cache_size_kb': (_surfaceCache.toString().length / 1024).toStringAsFixed(2),
    };
  }
}

/// Data class for terrain information
class TerrainData {
  final String surfaceType;
  final double energyMultiplier;
  
  const TerrainData({
    required this.surfaceType,
    required this.energyMultiplier,
  });
  
  @override
  String toString() => 'TerrainData(surface: $surfaceType, multiplier: $energyMultiplier)';
}

/// Bounding box for OSM queries
class BoundingBox {
  final double north;
  final double south;
  final double east;
  final double west;
  
  const BoundingBox({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });
}
