import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for tracking terrain during an active session
class TerrainTracker {
  static const double _minSegmentDistanceKm = 0.1; // Only query terrain every 100m
  static const Duration _queryThrottle = Duration(seconds: 30); // Throttle API calls
  
  LocationPoint? _lastTerrainQueryLocation;
  DateTime? _lastQueryTime;
  
  /// Check if we should query terrain for this location
  bool shouldQueryTerrain(LocationPoint newLocation) {
    final now = DateTime.now();
    
    // Throttle by time
    if (_lastQueryTime != null && now.difference(_lastQueryTime!) < _queryThrottle) {
      return false;
    }
    
    // Throttle by distance
    if (_lastTerrainQueryLocation != null) {
      final distance = _calculateDistance(_lastTerrainQueryLocation!, newLocation);
      if (distance < _minSegmentDistanceKm) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Add terrain data for a route segment
  Future<TerrainSegment?> trackTerrainSegment({
    required LocationPoint startLocation,
    required LocationPoint endLocation,
  }) async {
    try {
      AppLogger.debug('[TERRAIN_TRACKER] Querying terrain for segment');
      
      final terrainData = await TerrainService.getTerrainForSegment(
        startLat: startLocation.latitude,
        startLon: startLocation.longitude,
        endLat: endLocation.latitude,
        endLon: endLocation.longitude,
      );
      
      final distance = _calculateDistance(startLocation, endLocation);
      
      final segment = TerrainSegment(
        distanceKm: distance,
        surfaceType: terrainData.surfaceType,
        energyMultiplier: terrainData.energyMultiplier,
        timestamp: DateTime.now(),
      );
      
      // Update tracking state
      _lastTerrainQueryLocation = endLocation;
      _lastQueryTime = DateTime.now();
      
      AppLogger.debug('[TERRAIN_TRACKER] Created terrain segment: $segment');
      
      return segment;
      
    } catch (e) {
      AppLogger.error('[TERRAIN_TRACKER] Error tracking terrain segment: $e');
      return null;
    }
  }
  
  /// Calculate distance between two points in kilometers
  double _calculateDistance(LocationPoint start, LocationPoint end) {
    const double earthRadius = 6371; // km
    
    final lat1Rad = start.latitude * (3.14159 / 180);
    final lat2Rad = end.latitude * (3.14159 / 180);
    final deltaLatRad = (end.latitude - start.latitude) * (3.14159 / 180);
    final deltaLonRad = (end.longitude - start.longitude) * (3.14159 / 180);
    
    final a = (deltaLatRad / 2).sin() * (deltaLatRad / 2).sin() +
        lat1Rad.cos() * lat2Rad.cos() *
        (deltaLonRad / 2).sin() * (deltaLonRad / 2).sin();
    
    final c = 2 * (a.sqrt()).asin();
    
    return earthRadius * c;
  }
  
  /// Reset terrain tracking state
  void reset() {
    _lastTerrainQueryLocation = null;
    _lastQueryTime = null;
    AppLogger.debug('[TERRAIN_TRACKER] Reset tracking state');
  }
}
