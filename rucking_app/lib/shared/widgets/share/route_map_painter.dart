import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'dart:math' show sqrt, pow;

/// Custom painter that creates a simple route visualization from GPS points
class RouteMapPainter extends CustomPainter {
  final List<LocationPoint> locationPoints;
  final Color routeColor;
  final double strokeWidth;
  final bool simplifyRoute;
  final double epsilon;
  
  /// Creates a route map painter
  /// 
  /// [locationPoints] - The GPS points to draw
  /// [routeColor] - The color of the route line
  /// [strokeWidth] - The width of the route line
  /// [simplifyRoute] - Whether to simplify the route (reduces points)
  /// [epsilon] - Simplification tolerance (higher = fewer points)
  RouteMapPainter({
    required this.locationPoints,
    this.routeColor = Colors.white,
    this.strokeWidth = 3.0,
    this.simplifyRoute = true,
    this.epsilon = 0.00005, // Default simplification tolerance
  });
  
  /// Simplifies a list of location points using the Ramer-Douglas-Peucker algorithm
  /// Returns a reduced list of points while maintaining the shape of the route
  List<LocationPoint> _simplifyRoute(List<LocationPoint> points, double epsilon) {
    // If we have 2 or fewer points, simplification is not possible
    if (points.length <= 2) return List.from(points);
    
    double _perpendicularDistance(LocationPoint p, LocationPoint start, LocationPoint end) {
      // Convert to simple x,y coordinates for simplicity
      double x = p.longitude;
      double y = p.latitude;
      double x1 = start.longitude;
      double y1 = start.latitude;
      double x2 = end.longitude;
      double y2 = end.latitude;
      
      // Line length
      double dx = x2 - x1;
      double dy = y2 - y1;
      double lineLengthSquared = dx * dx + dy * dy;
      
      // If start and end are the same point
      if (lineLengthSquared == 0) {
        return sqrt(pow(x - x1, 2) + pow(y - y1, 2));
      }
      
      // Calculate perpendicular distance
      double t = ((x - x1) * dx + (y - y1) * dy) / lineLengthSquared;
      
      if (t < 0) {
        // Point is beyond start of line
        return sqrt(pow(x - x1, 2) + pow(y - y1, 2));
      }
      if (t > 1) {
        // Point is beyond end of line
        return sqrt(pow(x - x2, 2) + pow(y - y2, 2));
      }
      
      // Perpendicular distance formula
      double px = x1 + t * dx;
      double py = y1 + t * dy;
      return sqrt(pow(x - px, 2) + pow(y - py, 2));
    }
    
    // Find the point with the maximum distance
    double dmax = 0;
    int index = 0;
    int end = points.length - 1;
    
    for (int i = 1; i < end; i++) {
      double d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > dmax) {
        index = i;
        dmax = d;
      }
    }
    
    // If max distance is greater than epsilon, recursively simplify
    List<LocationPoint> resultPoints = [];
    if (dmax > epsilon) {
      // Recursive call
      List<LocationPoint> firstSegment = _simplifyRoute(points.sublist(0, index + 1), epsilon);
      List<LocationPoint> secondSegment = _simplifyRoute(points.sublist(index), epsilon);
      
      // Build the result list
      resultPoints = firstSegment.sublist(0, firstSegment.length - 1);
      resultPoints.addAll(secondSegment);
    } else {
      // Just return the endpoints
      resultPoints = [points[0], points[end]];
    }
    
    return resultPoints;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (locationPoints.isEmpty) {
      return;
    }

    List<LocationPoint> pointsToUse;
    if (simplifyRoute && locationPoints.length > 50) {
      pointsToUse = _simplifyRoute(locationPoints, epsilon);
    } else {
      pointsToUse = locationPoints;
    }

    // Create paint for the route
    final paint = Paint()
      ..color = routeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Find the bounds of the route
    double minLat = pointsToUse.first.latitude;
    double maxLat = pointsToUse.first.latitude;
    double minLng = pointsToUse.first.longitude;
    double maxLng = pointsToUse.first.longitude;

    for (final point in pointsToUse) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    // Add padding around the route
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    final padding = 0.1; // 10% padding
    
    minLat -= latRange * padding;
    maxLat += latRange * padding;
    minLng -= lngRange * padding;
    maxLng += lngRange * padding;

    // Create the path
    final path = Path();
    bool isFirst = true;

    for (final point in pointsToUse) {
      // Convert lat/lng to canvas coordinates
      final x = ((point.longitude - minLng) / (maxLng - minLng)) * size.width;
      final y = size.height - (((point.latitude - minLat) / (maxLat - minLat)) * size.height);

      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw the route
    canvas.drawPath(path, paint);

    // Start and end markers removed for cleaner share card appearance
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }
}
