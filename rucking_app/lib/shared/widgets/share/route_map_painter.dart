import 'package:flutter/material.dart';
import 'package:rucking_app/core/models/location_point.dart';

/// Custom painter that creates a simple route visualization from GPS points
class RouteMapPainter extends CustomPainter {
  final List<LocationPoint> locationPoints;
  final Color routeColor;
  final double strokeWidth;

  RouteMapPainter({
    required this.locationPoints,
    this.routeColor = Colors.white,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('🎨 RouteMapPainter.paint called - Size: $size, Points: ${locationPoints.length}');
    
    if (locationPoints.isEmpty) {
      print('🎨 No location points to paint');
      return;
    }

    // Create paint for the route
    final paint = Paint()
      ..color = routeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Find the bounds of the route
    double minLat = locationPoints.first.latitude;
    double maxLat = locationPoints.first.latitude;
    double minLng = locationPoints.first.longitude;
    double maxLng = locationPoints.first.longitude;

    for (final point in locationPoints) {
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

    for (final point in locationPoints) {
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
