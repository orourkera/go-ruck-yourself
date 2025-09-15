import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/domain/models/ruck_session.dart';

/// Service for generating route map images for social sharing
class RouteMapService {
  static const String _stadiaStaticUrl =
      'https://tiles.stadiamaps.com/static_cacheable/stamen_terrain';
  static const int _mapSize = 1024; // High resolution for Instagram
  static const double _routeStrokeWidth = 8.0;
  static const String _routeColor = '#FF6B35'; // Ruck orange color
  static const ui.Color _fallbackBackgroundTop = ui.Color(0xFF1B5E20);
  static const ui.Color _fallbackBackgroundBottom = ui.Color(0xFF43A047);
  static const ui.Color _fallbackRouteColor = ui.Color(0xFFFF6B35);

  /// Generate a route map image for Instagram sharing
  /// Returns the image as bytes, or null if generation fails
  Future<Uint8List?> generateInstagramRouteMap({
    required RuckSession session,
    bool preferMetric = true,
  }) async {
    List<LocationPoint> locationPoints = [];
    try {
      AppLogger.info('[ROUTE_MAP] Generating Instagram route map for session ${session.id}');

      if (session.locationPoints?.isEmpty ?? true) {
        AppLogger.warning('[ROUTE_MAP] No location points available for session ${session.id}');
        return null;
      }

      locationPoints = _convertToLocationPoints(session.locationPoints!);
      if (locationPoints.isEmpty) {
        AppLogger.warning('[ROUTE_MAP] Could not convert location points for session ${session.id}');
        return null;
      }

      final mapImageBytes = await _fetchStadiaMapImage(locationPoints);
      if (mapImageBytes != null) {
        AppLogger.info('[ROUTE_MAP] Successfully generated route map image');
        return mapImageBytes;
      }

      AppLogger.warning('[ROUTE_MAP] Stadia map unavailable, falling back to local renderer');
      return await _generateFallbackMap(locationPoints);
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error generating route map: $e');
      return await _generateFallbackMap(locationPoints);
    }
  }

  Future<Uint8List?> _fetchStadiaMapImage(List<LocationPoint> locationPoints) async {
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

      final bounds = _calculateBounds(locationPoints);
      if (bounds == null) {
        AppLogger.error('[ROUTE_MAP] Could not calculate route bounds');
        return null;
      }

      final simplifiedPoints = _simplifyRoute(locationPoints, 100);
      if (simplifiedPoints.isEmpty) {
        AppLogger.warning('[ROUTE_MAP] Simplified route had no points');
        return null;
      }

      final centerZoom = _calculateCenterZoom(bounds);
      final encodedPolyline = _encodePolylineFromPoints(simplifiedPoints);

      final requestBody = {
        'center': '${centerZoom['centerLat']},${centerZoom['centerLng']}',
        'zoom': centerZoom['zoom'],
        'size': '${_mapSize}x${_mapSize}',
        'style': 'stamen_terrain',
        'lines': [
          {
            'shape': encodedPolyline,
            'color': _routeColor.replaceAll('#', ''),
            'width': (_routeStrokeWidth / 2).round(),
            'cap': 'round',
            'join': 'round'
          }
        ],
      };

      AppLogger.info('[ROUTE_MAP] Requesting Stadia static cacheable map');

      final response = await http
          .post(
            Uri.parse('$_stadiaStaticUrl?api_key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        AppLogger.info('[ROUTE_MAP] Successfully fetched static map from Stadia');
        return response.bodyBytes;
      }

      AppLogger.error('[ROUTE_MAP] Stadia static API error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      AppLogger.error('[ROUTE_MAP] Error fetching map from Stadia Maps: $e');
      return null;
    }
  }

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

    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    return {
      'minLat': minLat - latPadding,
      'maxLat': maxLat + latPadding,
      'minLng': minLng - lngPadding,
      'maxLng': maxLng + lngPadding,
    };
  }

  List<LocationPoint> _simplifyRoute(List<LocationPoint> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final simplified = <LocationPoint>[];
    final step = points.length / maxPoints;
    for (var i = 0; i < points.length; i += step.floor()) {
      simplified.add(points[i]);
    }
    if (simplified.last != points.last) {
      simplified.add(points.last);
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

  String _encodePolylineFromPoints(List<LocationPoint> points) {
    if (points.isEmpty) return '';

    int lastLat = 0;
    int lastLng = 0;
    final buffer = StringBuffer();

    for (final point in points) {
      final lat = (point.latitude * 1e5).round();
      final lng = (point.longitude * 1e5).round();

      final deltaLat = lat - lastLat;
      final deltaLng = lng - lastLng;

      _encodePolylineValue(deltaLat, buffer);
      _encodePolylineValue(deltaLng, buffer);

      lastLat = lat;
      lastLng = lng;
    }

    return buffer.toString();
  }

  void _encodePolylineValue(int value, StringBuffer buffer) {
    var v = value << 1;
    if (value < 0) {
      v = ~v;
    }
    while (v >= 0x20) {
      buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    buffer.writeCharCode(v + 63);
  }

  List<LocationPoint> _convertToLocationPoints(List<dynamic> dynamicPoints) {
    final locationPoints = <LocationPoint>[];

    for (final point in dynamicPoints) {
      try {
        if (point is Map<String, dynamic>) {
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
          locationPoints.add(point);
        }
      } catch (e) {
        AppLogger.warning('[ROUTE_MAP] Error converting location point: $e');
      }
    }

    return locationPoints;
  }

  Future<Uint8List?> _generateFallbackMap(List<LocationPoint> points) async {
    try {
      if (points.isEmpty) return null;

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

      final bounds = _calculateBounds(points);
      if (bounds == null) return null;

      final minLat = bounds['minLat']!;
      final maxLat = bounds['maxLat']!;
      final minLng = bounds['minLng']!;
      final maxLng = bounds['maxLng']!;

      final latSpan = (maxLat - minLat).abs().clamp(0.0001, double.infinity);
      final lngSpan = (maxLng - minLng).abs().clamp(0.0001, double.infinity);

      final path = ui.Path();
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        final dx = ((point.longitude - minLng) / lngSpan) * (_mapSize * 0.8) + (_mapSize * 0.1);
        final dy = (_mapSize * 0.9) - ((point.latitude - minLat) / latSpan) * (_mapSize * 0.8);
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
