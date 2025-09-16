import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';
import 'package:rucking_app/shared/utils/route_privacy_utils.dart';
import 'package:latlong2/latlong.dart';

/// Service for generating route map images for social sharing
class RouteMapService {
  static const String _stadiaStaticUrl =
      'https://tiles.stadiamaps.com/static_cacheable/stamen_terrain';
  static const int _mapSize = 1024;
  static const double _routeStrokeWidth = 8.0;
  static const String _routeColor = 'FF6B35'; // Stadia expects AARRGGBB without '#'
  static const ui.Color _fallbackBackgroundTop = ui.Color(0xFF1B5E20);
  static const ui.Color _fallbackBackgroundBottom = ui.Color(0xFF43A047);
  static const ui.Color _fallbackRouteColor = ui.Color(0xFFFF6B35);

  Future<Uint8List?> generateInstagramRouteMap({
    required RuckSession session,
    bool preferMetric = true,
    bool applyPrivacyClipping = true,
  }) async {
    try {
      AppLogger.info('[ROUTE_MAP] Generating Instagram route map for session ${session.id}');

      // Get API key
      String apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        try {
          await dotenv.load();
          apiKey = dotenv.env['STADIA_MAPS_API_KEY'] ?? '';
        } catch (_) {}
      }

      if (apiKey.isEmpty) {
        AppLogger.error('STADIA_MAPS_API_KEY is not set. Map generation will fail.');
        return null;
      }

      // Get location points
      final points = session.locationPoints ?? [];
      if (points.isEmpty) return null;

      // Convert to LatLng points for privacy processing
      final routePoints = <LatLng>[];
      for (final point in points) {
        final lat = (point['lat'] ?? point['latitude'] as num?)?.toDouble();
        final lng = (point['lng'] ?? point['longitude'] as num?)?.toDouble();

        if (lat != null && lng != null) {
          routePoints.add(LatLng(lat, lng));
        }
      }

      if (routePoints.isEmpty) return null;

      // Apply privacy clipping if requested (for Last Ruck sharing)
      List<LatLng> routeToDisplay = routePoints;
      if (applyPrivacyClipping) {
        final privacySegments = RoutePrivacyUtils.splitRouteForPrivacy(
          routePoints,
          preferMetric: preferMetric,
        );

        // Only show the visible middle segment for Instagram sharing
        if (privacySegments.visibleMiddleSegment.isNotEmpty) {
          routeToDisplay = privacySegments.visibleMiddleSegment;
          AppLogger.info('[ROUTE_MAP] Applied privacy clipping - using ${routeToDisplay.length} points from visible middle segment');
        } else {
          AppLogger.warning('[ROUTE_MAP] Privacy clipping resulted in no visible segment - route too short');
          return null;
        }
      }

      // Convert to coordinates format for map generation
      final coordinates = routeToDisplay.map((point) => {
        'lat': point.latitude,
        'lng': point.longitude,
      }).toList();

      if (coordinates.isEmpty) return null;

      // Simplify the route by sampling points (max 50 points for better performance)
      final simplifiedCoordinates = _simplifyRoute(coordinates, 50);

      // Calculate bounds for better zoom
      final lats = simplifiedCoordinates.map((p) => p['lat']!);
      final lngs = simplifiedCoordinates.map((p) => p['lng']!);
      final minLat = lats.reduce((a, b) => a < b ? a : b);
      final maxLat = lats.reduce((a, b) => a > b ? a : b);
      final minLng = lngs.reduce((a, b) => a < b ? a : b);
      final maxLng = lngs.reduce((a, b) => a > b ? a : b);

      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;

      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Calculate zoom level based on span (smaller span = higher zoom)
      final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
      int zoom;
      if (maxSpan > 0.1) {
        zoom = 10; // Very large area
      } else if (maxSpan > 0.05) {
        zoom = 12; // Large area
      } else if (maxSpan > 0.02) {
        zoom = 14; // Medium area
      } else if (maxSpan > 0.01) {
        zoom = 15; // Small area
      } else {
        zoom = 16; // Very small area
      }

      // Build request body using center/zoom approach
      final encodedPolyline = _encodePolyline(simplifiedCoordinates);

      AppLogger.info('[ROUTE_MAP] Simplified coordinates count: ${simplifiedCoordinates.length}');
      AppLogger.info('[ROUTE_MAP] First coordinate: ${simplifiedCoordinates.isNotEmpty ? simplifiedCoordinates.first : 'none'}');
      AppLogger.info('[ROUTE_MAP] Last coordinate: ${simplifiedCoordinates.isNotEmpty ? simplifiedCoordinates.last : 'none'}');
      AppLogger.info('[ROUTE_MAP] Encoded polyline length: ${encodedPolyline.length}');
      AppLogger.info('[ROUTE_MAP] Encoded polyline preview: ${encodedPolyline.length > 50 ? encodedPolyline.substring(0, 50) + '...' : encodedPolyline}');

      final requestBody = {
        'center': '$centerLat,$centerLng',
        'zoom': zoom,
        'size': '800x800',
        'style': 'stamen_terrain',
        'line_precision': 5, // Google's polyline precision
        'lines': [
          {
            'shape': encodedPolyline,
            'stroke_color': 'FF9500',
            'stroke_width': 5
          }
        ],
      };

      AppLogger.info('[ROUTE_MAP] Request body: ${requestBody.toString()}');

      // Send POST request to the cacheable endpoint
      final response = await http.post(
        Uri.parse('https://tiles.stadiamaps.com/static_cacheable/stamen_terrain?api_key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        AppLogger.info('[ROUTE_MAP] Successfully generated route map image');
        return response.bodyBytes;
      } else {
        AppLogger.error('Stadia Maps API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error generating route map: $e');
      return null;
    }
  }

  Future<Uint8List?> _fetchStadiaMapImage(List<Map<String, double>> coordinates) async {
    try {
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

      // Simplify the route (max 50 points for better performance like the working version)
      final simplifiedCoordinates = _simplifyRoute(coordinates, 50);
      if (simplifiedCoordinates.isEmpty) {
        AppLogger.warning('[ROUTE_MAP] Simplified route had no points');
        return null;
      }

      // Calculate bounds for better zoom (same as working version)
      final lats = simplifiedCoordinates.map((p) => p['lat']!);
      final lngs = simplifiedCoordinates.map((p) => p['lng']!);
      final minLat = lats.reduce((a, b) => a < b ? a : b);
      final maxLat = lats.reduce((a, b) => a > b ? a : b);
      final minLng = lngs.reduce((a, b) => a < b ? a : b);
      final maxLng = lngs.reduce((a, b) => a > b ? a : b);

      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;

      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Calculate zoom level based on span (same logic as working version)
      final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
      int zoom;
      if (maxSpan > 0.1) {
        zoom = 10; // Very large area
      } else if (maxSpan > 0.05) {
        zoom = 12; // Large area
      } else if (maxSpan > 0.02) {
        zoom = 14; // Medium area
      } else if (maxSpan > 0.01) {
        zoom = 15; // Small area
      } else {
        zoom = 16; // Very small area
      }

      final encodedPolyline = _encodePolyline(simplifiedCoordinates);

      final requestBody = {
        'center': '$centerLat,$centerLng',
        'zoom': zoom,
        'size': '${_mapSize}x${_mapSize}',
        'style': 'stamen_terrain',
        'lines': [
          {
            'shape': encodedPolyline,
            'color': 'FF9500', // Use same color as working version
            'width': 5, // Use same width as working version
            'cap': 'round',
            'join': 'round'
          }
        ],
      };

      AppLogger.info('[ROUTE_MAP] Requesting Stadia static cacheable map');

      // Send POST request to the cacheable endpoint (exactly like working share card widget)
      final response = await http.post(
        Uri.parse('https://tiles.stadiamaps.com/static_cacheable/stamen_terrain?api_key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      AppLogger.error('[ROUTE_MAP] Stadia static API error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error fetching map from Stadia Maps: $e');
      return null;
    }
  }

  List<Map<String, double>> _extractCoordinates(List<dynamic> points) {
    final coordinates = <Map<String, double>>[];
    for (final point in points) {
      try {
        if (point is Map) {
          final latRaw = point['latitude'] ?? point['lat'];
          final lngRaw = point['longitude'] ?? point['lng'];
          final double? lat = _toDouble(latRaw);
          final double? lng = _toDouble(lngRaw);
          if (lat != null && lng != null) {
            coordinates.add({'lat': lat, 'lng': lng});
          }
        }
      } catch (e) {
        AppLogger.warning('[ROUTE_MAP] Error converting location point: $e');
      }
    }
    return coordinates;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, double>? _calculateBounds(List<Map<String, double>> coordinates) {
    if (coordinates.isEmpty) return null;

    double minLat = coordinates.first['lat']!;
    double maxLat = coordinates.first['lat']!;
    double minLng = coordinates.first['lng']!;
    double maxLng = coordinates.first['lng']!;

    for (final point in coordinates) {
      minLat = math.min(minLat, point['lat']!);
      maxLat = math.max(maxLat, point['lat']!);
      minLng = math.min(minLng, point['lng']!);
      maxLng = math.max(maxLng, point['lng']!);
    }

    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    return {
      'minLat': minLat - latPadding,
      'maxLat': maxLat + latPadding,
      'minLng': minLng - lngPadding,
      'maxLng': maxLng + lngPadding,
    };
  }

  List<Map<String, double>> _simplifyRoute(List<Map<String, double>> coordinates, int maxPoints) {
    if (coordinates.length <= maxPoints) return coordinates;

    final simplified = <Map<String, double>>[];
    final step = coordinates.length / maxPoints;

    for (int i = 0; i < coordinates.length; i += step.floor()) {
      simplified.add(coordinates[i]);
    }

    return simplified;
  }

  Map<String, dynamic> _calculateCenterZoom(Map<String, double> bounds) {
    final minLat = bounds['minLat']!;
    final maxLat = bounds['maxLat']!;
    final minLng = bounds['minLng']!;
    final maxLng = bounds['maxLng']!;

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    int zoom;
    if (maxSpan > 0.1) {
      zoom = 10;
    } else if (maxSpan > 0.05) {
      zoom = 12;
    } else if (maxSpan > 0.02) {
      zoom = 14;
    } else if (maxSpan > 0.01) {
      zoom = 15;
    } else {
      zoom = 16;
    }

    return {
      'centerLat': (minLat + maxLat) / 2,
      'centerLng': (minLng + maxLng) / 2,
      'zoom': zoom,
    };
  }

  String _encodePolyline(List<Map<String, double>> coordinates) {
    if (coordinates.isEmpty) return '';

    // Implement Google polyline encoding algorithm
    int lat = 0;
    int lng = 0;
    final result = StringBuffer();

    for (final coord in coordinates) {
      final newLat = (coord['lat']! * 1e5).round();
      final newLng = (coord['lng']! * 1e5).round();

      final deltaLat = newLat - lat;
      final deltaLng = newLng - lng;

      lat = newLat;
      lng = newLng;

      result.write(_encodeNumber(deltaLat));
      result.write(_encodeNumber(deltaLng));
    }

    return result.toString();
  }

  String _encodeNumber(int num) {
    // Left-shift the binary value one bit and apply bitwise XOR
    int sgn_num = num << 1;
    if (num < 0) {
      sgn_num = ~sgn_num;
    }

    final result = StringBuffer();
    while (sgn_num >= 0x20) {
      result.writeCharCode((0x20 | (sgn_num & 0x1f)) + 63);
      sgn_num >>= 5;
    }
    result.writeCharCode(sgn_num + 63);

    return result.toString();
  }

  Future<Uint8List?> _generateFallbackMap(List<Map<String, double>> coords) async {
    try {
      if (coords.isEmpty) return null;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, _mapSize.toDouble(), _mapSize.toDouble()),
      );

      final paint = ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          ui.Offset(0, _mapSize.toDouble()),
          const [
            _fallbackBackgroundTop,
            _fallbackBackgroundBottom,
          ],
        );
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, _mapSize.toDouble(), _mapSize.toDouble()),
        paint,
      );

      final bounds = _calculateBounds(coords);
      if (bounds == null) return null;

      final minLat = bounds['minLat']!;
      final maxLat = bounds['maxLat']!;
      final minLng = bounds['minLng']!;
      final maxLng = bounds['maxLng']!;

      final latSpan = (maxLat - minLat).abs().clamp(0.0001, double.infinity);
      final lngSpan = (maxLng - minLng).abs().clamp(0.0001, double.infinity);

      final path = ui.Path();
      for (var i = 0; i < coords.length; i++) {
        final point = coords[i];
        final dx = ((point['lng']! - minLng) / lngSpan) * (_mapSize * 0.8) + (_mapSize * 0.1);
        final dy = (_mapSize * 0.9) - ((point['lat']! - minLat) / latSpan) * (_mapSize * 0.8);
        if (i == 0) {
          path.moveTo(dx, dy);
        } else {
          path.lineTo(dx, dy);
        }
      }

      final routePaint = ui.Paint()
        ..color = _fallbackRouteColor
        ..strokeWidth = _routeStrokeWidth
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;

      canvas.drawPath(path, routePaint);

      final picture = recorder.endRecording();
      final image = await picture.toImage(_mapSize, _mapSize);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Fallback map generation failed: $e');
      return null;
    }
  }
}
