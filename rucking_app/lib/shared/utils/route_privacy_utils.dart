import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class RoutePrivacySegments {
  final List<LatLng> privateStartSegment;
  final List<LatLng> visibleMiddleSegment;
  final List<LatLng> privateEndSegment;

  RoutePrivacySegments({
    required this.privateStartSegment,
    required this.visibleMiddleSegment,
    required this.privateEndSegment,
  });
}

class RoutePrivacyUtils {
  /// Calculate the great circle distance between two points in meters
  static double haversineDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final double lat1Rad = point1.latitude * (math.pi / 180);
    final double lat2Rad = point2.latitude * (math.pi / 180);
    final double deltaLatRad =
        (point2.latitude - point1.latitude) * (math.pi / 180);
    final double deltaLonRad =
        (point2.longitude - point1.longitude) * (math.pi / 180);

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Splits a route into privacy segments: start (private), middle (visible), end (private)
  ///
  /// [routePoints] - The complete route points
  /// [preferMetric] - User's unit preference for consistent distance calculation
  ///
  /// Returns [RoutePrivacySegments] with the three segments
  static RoutePrivacySegments splitRouteForPrivacy(
    List<LatLng> routePoints, {
    bool preferMetric = true,
  }) {
    // Privacy clipping distance (200m metric, ~1/8 mile imperial)
    final double privacyDistanceMeters =
        getClipDistance(preferMetric: preferMetric);

    // If route is too short (few points), do NOT expose any visible middle
    if (routePoints.length < 3) {
      return RoutePrivacySegments(
        privateStartSegment: routePoints,
        visibleMiddleSegment: const [],
        privateEndSegment: const [],
      );
    }

    // Compute total route distance up-front to guard short/borderline routes
    double totalDistanceMeters = 0.0;
    for (int i = 1; i < routePoints.length; i++) {
      totalDistanceMeters +=
          haversineDistance(routePoints[i - 1], routePoints[i]);
    }

    // If total < 2x clip distance, showing any middle risks exposing endpoints
    if (totalDistanceMeters < (2 * privacyDistanceMeters)) {
      return RoutePrivacySegments(
        privateStartSegment: routePoints,
        visibleMiddleSegment: const [],
        privateEndSegment: const [],
      );
    }

    // Find start clipping index
    int startIndex = 0;
    double cumulativeDistance = 0;
    for (int i = 1; i < routePoints.length; i++) {
      final distance = haversineDistance(routePoints[i - 1], routePoints[i]);
      cumulativeDistance += distance;

      if (cumulativeDistance >= privacyDistanceMeters) {
        startIndex = i;
        break;
      }
    }

    // Find end clipping index (working backwards)
    int endIndex = routePoints.length - 1;
    cumulativeDistance = 0;
    for (int i = routePoints.length - 2; i >= 0; i--) {
      final distance = haversineDistance(routePoints[i], routePoints[i + 1]);
      cumulativeDistance += distance;

      if (cumulativeDistance >= privacyDistanceMeters) {
        endIndex = i;
        break;
      }
    }

    // If indices cross or fail to bound a middle, do NOT expose any middle
    if (startIndex >= endIndex) {
      return RoutePrivacySegments(
        privateStartSegment: routePoints,
        visibleMiddleSegment: const [],
        privateEndSegment: const [],
      );
    }

    // One-sided clipping guard: if only one side reached clip threshold, hide middle entirely
    if (startIndex == 0 || endIndex == routePoints.length - 1) {
      return RoutePrivacySegments(
        privateStartSegment: routePoints,
        visibleMiddleSegment: const [],
        privateEndSegment: const [],
      );
    }

    // Create the three segments with overlapping points for continuity
    final List<LatLng> privateStart =
        startIndex > 0 ? routePoints.sublist(0, startIndex + 1) : [];

    final List<LatLng> visibleMiddle =
        routePoints.sublist(startIndex, endIndex + 1);

    final List<LatLng> privateEnd =
        endIndex < routePoints.length - 1 ? routePoints.sublist(endIndex) : [];

    return RoutePrivacySegments(
      privateStartSegment: privateStart,
      visibleMiddleSegment: visibleMiddle,
      privateEndSegment: privateEnd,
    );
  }

  /// Helper method to check if user prefers metric units
  /// This should be called with the actual user preference from AuthBloc
  static double getClipDistance({required bool preferMetric}) {
    return preferMetric ? 500.0 : 500.0; // 500m for both to standardize
  }
}
