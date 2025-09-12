import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Utility to convert loosely-typed coordinate structures coming from the
/// backend into a list of [LatLng] accepted by Flutter Map.
///
/// It supports:
///   • `{lat,lng}` and `{latitude,longitude}` maps
///   • `{lat,lon}` maps (legacy)
///   • `[lat,lng]` arrays
///   • Numeric or String values for each coordinate
List<LatLng> parseRoutePoints(dynamic rawRoute) {
  print(
      '[ROUTE_PARSER] Starting parseRoutePoints with rawRoute type: ${rawRoute.runtimeType}');
  if (rawRoute == null) {
    print('[ROUTE_PARSER] rawRoute is null, returning empty list');
    return const [];
  }

  final points = <LatLng>[];
  print(
      '[ROUTE_PARSER] rawRoute is List: ${rawRoute is List}, length: ${rawRoute is List ? rawRoute.length : 'N/A'}');

  double? _parse(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  if (rawRoute is List) {
    for (final p in rawRoute) {
      double? lat;
      double? lng;

      if (p is Map) {
        lat = _parse(p['latitude']) ?? _parse(p['lat']);
        lng = _parse(p['longitude']) ?? _parse(p['lng']) ?? _parse(p['lon']);
      } else if (p is List && p.length >= 2) {
        lat = _parse(p[0]);
        lng = _parse(p[1]);
      }

      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
  }

  // If we end up with <2 points FlutterMap will not draw the polyline, so the
  // caller can decide whether to inject a fallback. We simply return what we
  // gathered.
  return points;
}
