import 'dart:math' as math;
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/models/terrain_segment.dart';
import 'package:rucking_app/core/services/terrain_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for tracking terrain during an active session
class TerrainTracker {
  static const double _minSegmentDistanceKm =
      0.005; // Reduced to 5m for better accuracy
  static const Duration _queryThrottle =
      Duration(seconds: 2); // Reduced from 5s to 2s for testing

  LocationPoint? _lastTerrainQueryLocation;
  DateTime? _lastQueryTime;

  /// Check if we should query terrain for this location
  bool shouldQueryTerrain(LocationPoint newLocation) {
    final now = DateTime.now();

    // Throttle by time
    if (_lastQueryTime != null &&
        now.difference(_lastQueryTime!) < _queryThrottle) {
      AppLogger.debug(
          '[TERRAIN_THROTTLE] Time throttled: ${now.difference(_lastQueryTime!).inSeconds}s < ${_queryThrottle.inSeconds}s');
      return false;
    }

    // Throttle by distance
    if (_lastTerrainQueryLocation != null) {
      final distance =
          _calculateDistance(_lastTerrainQueryLocation!, newLocation);
      if (distance < _minSegmentDistanceKm) {
        AppLogger.debug(
            '[TERRAIN_THROTTLE] Distance throttled: ${(distance * 1000).toStringAsFixed(1)}m < ${(_minSegmentDistanceKm * 1000).toStringAsFixed(1)}m');
        return false;
      }
    }

    AppLogger.debug(
        '[TERRAIN_THROTTLE] Query allowed - distance: ${_lastTerrainQueryLocation != null ? (_calculateDistance(_lastTerrainQueryLocation!, newLocation) * 1000).toStringAsFixed(1) : 'first'}m');
    return true;
  }

  /// Add terrain data for a route segment
  Future<TerrainSegment?> trackTerrainSegment({
    required LocationPoint startLocation,
    required LocationPoint endLocation,
  }) async {
    try {
      final distance = _calculateDistance(startLocation, endLocation);
      AppLogger.debug(
          '[TERRAIN_TRACKER] Querying terrain for ${(distance * 1000).toStringAsFixed(1)}m segment');

      final terrainData = await TerrainService.getTerrainForSegment(
        startLat: startLocation.latitude,
        startLon: startLocation.longitude,
        endLat: endLocation.latitude,
        endLon: endLocation.longitude,
      );

      final segment = TerrainSegment(
        distanceKm: distance,
        surfaceType: terrainData.surfaceType,
        energyMultiplier: terrainData.energyMultiplier,
        timestamp: DateTime.now(),
      );

      // Update tracking state
      _lastTerrainQueryLocation = endLocation;
      _lastQueryTime = DateTime.now();

      AppLogger.debug(
          '[TERRAIN_TRACKER] Created terrain segment: ${segment.surfaceType} (${segment.energyMultiplier}x) - ${(segment.distanceKm * 1000).toStringAsFixed(1)}m');

      return segment;
    } catch (e) {
      AppLogger.error('[TERRAIN_TRACKER] Error tracking terrain segment: $e');

      // Create a fallback segment with default values instead of returning null
      final distance = _calculateDistance(startLocation, endLocation);
      final fallbackSegment = TerrainSegment(
        distanceKm: distance,
        surfaceType: 'paved', // Default surface type
        energyMultiplier: 1.0, // Default multiplier
        timestamp: DateTime.now(),
      );

      // Update tracking state even for fallback
      _lastTerrainQueryLocation = endLocation;
      _lastQueryTime = DateTime.now();

      AppLogger.debug(
          '[TERRAIN_TRACKER] Created fallback terrain segment: ${(fallbackSegment.distanceKm * 1000).toStringAsFixed(1)}m (paved/1.0x)');

      return fallbackSegment;
    }
  }

  /// Calculate distance between two points in kilometers
  double _calculateDistance(LocationPoint start, LocationPoint end) {
    const double earthRadius = 6371; // km

    final lat1Rad = start.latitude * (math.pi / 180);
    final lat2Rad = end.latitude * (math.pi / 180);
    final deltaLatRad = (end.latitude - start.latitude) * (math.pi / 180);
    final deltaLonRad = (end.longitude - start.longitude) * (math.pi / 180);

    final a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);

    final c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  /// Reset terrain tracking state
  void reset() {
    _lastTerrainQueryLocation = null;
    _lastQueryTime = null;
    AppLogger.debug('[TERRAIN_TRACKER] Reset tracking state');
  }
}
