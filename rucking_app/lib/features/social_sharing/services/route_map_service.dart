import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

/// Service for generating route map images for social sharing
class RouteMapService {
  static const String _stadiaBaseUrl = 'https://tiles.stadiamaps.com/render/stamen_terrain';
  static const int _mapSize = 1024; // High resolution for Instagram
  static const double _routeStrokeWidth = 8.0;
  static const String _routeColor = '#FF6B35'; // Ruck orange color

  /// Generate a route map image for Instagram sharing
  /// Returns the image as bytes, or null if generation fails
  Future<Uint8List?> generateInstagramRouteMap({
    required RuckSession session,
    bool preferMetric = true,
  }) async {
    try {
      AppLogger.info('[ROUTE_MAP] Generating Instagram route map for session ${session.id}');

      // Check if we have location points
      if (session.locationPoints?.isEmpty ?? true) {
        AppLogger.warning('[ROUTE_MAP] No location points available for session ${session.id}');
        return null;
      }

      // Convert dynamic location points to LocationPoint objects
      final locationPoints = _convertToLocationPoints(session.locationPoints!);
      if (locationPoints.isEmpty) {
        AppLogger.warning('[ROUTE_MAP] Could not convert location points for session ${session.id}');
        return null;
      }

      // Generate map image using Stadia Maps API
      final mapImageBytes = await _fetchStadiaMapImage(
        locationPoints: locationPoints,
        session: session,
      );

      if (mapImageBytes != null) {
        AppLogger.info('[ROUTE_MAP] Successfully generated route map image');
        return mapImageBytes;
      } else {
        AppLogger.warning('[ROUTE_MAP] Failed to generate map image');
        return null;
      }
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error generating route map: $e');
      return null;
    }
  }

  /// Fetch route map image from Stadia Maps API
  Future<Uint8List?> _fetchStadiaMapImage({
    required List<LocationPoint> locationPoints,
    required RuckSession session,
  }) async {
    try {
      // Get API key
      String apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        try {
          await dotenv.load();
          apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
        } catch (e) {
          AppLogger.error('[ROUTE_MAP] Error loading .env file: $e');
        }
      }

      if (apiKey.isEmpty) {
        AppLogger.error('[ROUTE_MAP] Stadia Maps API key not found');
        return null;
      }

      // Calculate bounds for the route
      final bounds = _calculateBounds(locationPoints);
      if (bounds == null) {
        AppLogger.error('[ROUTE_MAP] Could not calculate route bounds');
        return null;
      }

      // Build the API request
      final requestBody = _buildStadiaMapRequest(
        bounds: bounds,
        locationPoints: locationPoints,
        session: session,
      );

      AppLogger.info('[ROUTE_MAP] Making Stadia Maps API request');

      // Make the API request
      final response = await http.post(
        Uri.parse('$_stadiaBaseUrl?api_key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        AppLogger.info('[ROUTE_MAP] Successfully fetched map image from Stadia Maps');
        return response.bodyBytes;
      } else {
        AppLogger.error('[ROUTE_MAP] Stadia Maps API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error fetching map from Stadia Maps: $e');
      return null;
    }
  }

  /// Calculate the bounding box for the route
  Map<String, double>? _calculateBounds(List<LocationPoint> locationPoints) {
    if (locationPoints.isEmpty) return null;

    double minLat = locationPoints.first.latitude;
    double maxLat = locationPoints.first.latitude;
    double minLng = locationPoints.first.longitude;
    double maxLng = locationPoints.first.longitude;

    for (final point in locationPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    // Add padding (10% of the range)
    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    return {
      'minLat': minLat - latPadding,
      'maxLat': maxLat + latPadding,
      'minLng': minLng - lngPadding,
      'maxLng': maxLng + lngPadding,
    };
  }

  /// Build the request body for Stadia Maps API
  Map<String, dynamic> _buildStadiaMapRequest({
    required Map<String, double> bounds,
    required List<LocationPoint> locationPoints,
    required RuckSession session,
  }) {
    // Build polyline path
    final routePath = locationPoints
        .map((point) => [point.longitude, point.latitude])
        .toList();

    return {
      'width': _mapSize,
      'height': _mapSize,
      'bbox': [
        bounds['minLng']!,
        bounds['minLat']!,
        bounds['maxLng']!,
        bounds['maxLat']!,
      ],
      'format': 'png',
      'layers': [
        {
          'type': 'fill',
          'source': {
            'type': 'geojson',
            'data': {
              'type': 'Feature',
              'properties': {},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [[
                  [bounds['minLng']!, bounds['minLat']!],
                  [bounds['maxLng']!, bounds['minLat']!],
                  [bounds['maxLng']!, bounds['maxLat']!],
                  [bounds['minLng']!, bounds['maxLat']!],
                  [bounds['minLng']!, bounds['minLat']!],
                ]],
              },
            },
          },
          'paint': {
            'fill-color': '#000000',
            'fill-opacity': 0.0, // Transparent fill, just for bounds
          },
        },
        {
          'type': 'line',
          'source': {
            'type': 'geojson',
            'data': {
              'type': 'Feature',
              'properties': {},
              'geometry': {
                'type': 'LineString',
                'coordinates': routePath,
              },
            },
          },
          'paint': {
            'line-color': _routeColor,
            'line-width': _routeStrokeWidth,
            'line-opacity': 0.9,
          },
        },
        // Start point marker
        if (locationPoints.isNotEmpty)
          {
            'type': 'circle',
            'source': {
              'type': 'geojson',
              'data': {
                'type': 'Feature',
                'properties': {},
                'geometry': {
                  'type': 'Point',
                  'coordinates': [
                    locationPoints.first.longitude,
                    locationPoints.first.latitude,
                  ],
                },
              },
            },
            'paint': {
              'circle-color': '#4CAF50', // Green for start
              'circle-radius': 12,
              'circle-stroke-color': '#FFFFFF',
              'circle-stroke-width': 3,
            },
          },
        // End point marker
        if (locationPoints.length > 1)
          {
            'type': 'circle',
            'source': {
              'type': 'geojson',
              'data': {
                'type': 'Feature',
                'properties': {},
                'geometry': {
                  'type': 'Point',
                  'coordinates': [
                    locationPoints.last.longitude,
                    locationPoints.last.latitude,
                  ],
                },
              },
            },
            'paint': {
              'circle-color': '#F44336', // Red for finish
              'circle-radius': 12,
              'circle-stroke-color': '#FFFFFF',
              'circle-stroke-width': 3,
            },
          },
      ],
    };
  }

  /// Generate a simple map URL as fallback (without API key requirements)
  String? generateMapUrl({
    required RuckSession session,
  }) {
    if (session.locationPoints?.isEmpty ?? true) return null;

    // Convert dynamic location points to LocationPoint objects
    final locationPoints = _convertToLocationPoints(session.locationPoints!);
    if (locationPoints.isEmpty) return null;

    try {
      // Calculate center point
      double centerLat = locationPoints.map((p) => p.latitude).reduce((a, b) => a + b) / locationPoints.length;
      double centerLng = locationPoints.map((p) => p.longitude).reduce((a, b) => a + b) / locationPoints.length;

      // Calculate zoom level based on bounds
      final bounds = _calculateBounds(locationPoints);
      if (bounds == null) return null;

      final latDiff = bounds['maxLat']! - bounds['minLat']!;
      final lngDiff = bounds['maxLng']! - bounds['minLng']!;
      final maxDiff = math.max(latDiff, lngDiff);

      // Approximate zoom level calculation
      int zoom = 15;
      if (maxDiff > 0.1) {
        zoom = 12;
      } else if (maxDiff > 0.05) {
        zoom = 13;
      } else if (maxDiff > 0.01) {
        zoom = 14;
      }

      // Use OpenStreetMap-based tile service (no API key needed)
      return 'https://tile.openstreetmap.org/$zoom/${_lngToTileX(centerLng, zoom)}/${_latToTileY(centerLat, zoom)}.png';
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error generating map URL: $e');
      return null;
    }
  }

  /// Convert longitude to tile X coordinate
  int _lngToTileX(double lng, int zoom) {
    return ((lng + 180) / 360 * math.pow(2, zoom)).floor();
  }

  /// Convert latitude to tile Y coordinate
  int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    return ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * math.pow(2, zoom)).floor();
  }

  /// Convert dynamic location points to LocationPoint objects
  List<LocationPoint> _convertToLocationPoints(List<dynamic> dynamicPoints) {
    final locationPoints = <LocationPoint>[];

    for (final point in dynamicPoints) {
      try {
        if (point is Map<String, dynamic>) {
          // Handle map format
          final lat = (point['latitude'] ?? point['lat']) as double?;
          final lng = (point['longitude'] ?? point['lng']) as double?;
          final timestamp = point['timestamp'];

          if (lat != null && lng != null) {
            locationPoints.add(LocationPoint(
              latitude: lat,
              longitude: lng,
              elevation: (point['elevation'] ?? point['altitude'] ?? 0.0) as double,
              timestamp: timestamp is DateTime ? timestamp : DateTime.now(),
              accuracy: (point['accuracy'] ?? 10.0) as double,
            ));
          }
        } else if (point is LocationPoint) {
          // Already a LocationPoint
          locationPoints.add(point);
        }
      } catch (e) {
        AppLogger.warning('[ROUTE_MAP] Error converting location point: $e');
      }
    }

    return locationPoints;
  }
}