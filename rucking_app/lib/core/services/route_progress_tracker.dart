import 'dart:math' as math;
import 'dart:async';
import 'package:rucking_app/core/models/route.dart';
import 'package:rucking_app/core/models/route_elevation_point.dart';
import 'package:rucking_app/core/models/location_point.dart';

/// 🎯 **Route Progress Tracker**
/// 
/// Advanced real-time tracking of progress along planned routes
/// with milestone detection, deviation alerts, and progress metrics.
class RouteProgressTracker {
  static const double _onRouteThreshold = 50.0; // meters
  static const double _offRouteWarningThreshold = 100.0; // meters
  static const double _offRouteCriticalThreshold = 200.0; // meters
  static const double _milestoneProximityThreshold = 25.0; // meters
  
  final Route _route;
  final StreamController<RouteProgressUpdate> _progressController;
  
  // Current progress state
  int _currentSegmentIndex = 0;
  double _totalDistanceTraveled = 0.0;
  double _routeDistanceTraveled = 0.0;
  List<LocationPoint> _actualPath = [];
  Set<int> _passedMilestones = {};
  
  // Progress metrics
  double _averageSpeed = 0.0;
  double _currentSpeed = 0.0;
  Duration _timeOnRoute = Duration.zero;
  DateTime? _lastUpdateTime;
  bool _isOnRoute = true;
  
  RouteProgressTracker(this._route) 
      : _progressController = StreamController<RouteProgressUpdate>.broadcast();
  
  /// 📡 **Progress Updates Stream**
  Stream<RouteProgressUpdate> get progressUpdates => _progressController.stream;
  
  /// 📍 **Update Current Location**
  /// 
  /// Process new GPS location and calculate progress metrics
  void updateLocation(double latitude, double longitude, {
    double? accuracy,
    double? speed,
    double? bearing,
  }) {
    final currentTime = DateTime.now();
    final currentLocation = LocationPoint(
      latitude: latitude,
      longitude: longitude,
      elevation: 0.0, // Default elevation
      timestamp: currentTime,
      accuracy: 0.0, // Default accuracy
    );
    
    // Add to actual path
    _actualPath.add(currentLocation);
    
    // Calculate time delta
    Duration timeDelta = Duration.zero;
    if (_lastUpdateTime != null) {
      timeDelta = currentTime.difference(_lastUpdateTime!);
      _timeOnRoute = _timeOnRoute + timeDelta;
    }
    _lastUpdateTime = currentTime;
    
    // Find closest point on route
    final closestPointResult = _findClosestPointOnRoute(latitude, longitude);
    final distanceToRoute = closestPointResult['distance'] as double;
    final closestIndex = closestPointResult['index'] as int;
    
    // Update route adherence
    final wasOnRoute = _isOnRoute;
    _isOnRoute = distanceToRoute <= _onRouteThreshold;
    
    // Calculate distances
    if (_actualPath.length > 1) {
      final previousLocation = _actualPath[_actualPath.length - 2];
      final segmentDistance = _calculateHaversineDistance(
        previousLocation.latitude, previousLocation.longitude,
        latitude, longitude,
      );
      _totalDistanceTraveled += segmentDistance;
      
      // Only add to route distance if we're on route
      if (_isOnRoute) {
        _routeDistanceTraveled += segmentDistance;
      }
      
      // Calculate current speed
      if (timeDelta.inSeconds > 0) {
        _currentSpeed = segmentDistance / timeDelta.inSeconds;
      } else if (speed != null) {
        _currentSpeed = speed;
      }
      
      // Update average speed
      if (_timeOnRoute.inSeconds > 0) {
        _averageSpeed = _totalDistanceTraveled / _timeOnRoute.inSeconds;
      }
    }
    
    // Update current segment index
    _currentSegmentIndex = closestIndex;
    
    // Check for milestones
    final newMilestones = _checkForMilestones(latitude, longitude);
    
    // Create progress update
    final progressUpdate = RouteProgressUpdate(
      currentLocation: currentLocation,
      distanceToRoute: distanceToRoute,
      isOnRoute: _isOnRoute,
      wasOnRoute: wasOnRoute,
      currentSegmentIndex: _currentSegmentIndex,
      progressPercentage: _calculateProgressPercentage(),
      totalDistanceTraveled: _totalDistanceTraveled,
      routeDistanceTraveled: _routeDistanceTraveled,
      remainingDistance: _calculateRemainingDistance(closestIndex),
      currentSpeed: _currentSpeed,
      averageSpeed: _averageSpeed,
      timeOnRoute: _timeOnRoute,
      newMilestones: newMilestones,
      routeDeviation: _calculateRouteDeviation(),
      elevationAtCurrentPosition: _getElevationAtPosition(closestIndex),
      nextWaypoint: _getNextWaypoint(closestIndex),
      distanceToNextWaypoint: _getDistanceToNextWaypoint(latitude, longitude, closestIndex),
    );
    
    // Emit progress update
    _progressController.add(progressUpdate);
  }
  
  /// 🎯 **Find Closest Point on Route**
  Map<String, dynamic> _findClosestPointOnRoute(double latitude, double longitude) {
    if (_route.elevationPoints.isEmpty) {
      return {'distance': double.infinity, 'index': 0};
    }
    
    double minDistance = double.infinity;
    int closestIndex = 0;
    
    for (int i = 0; i < _route.elevationPoints.length; i++) {
      final point = _route.elevationPoints[i];
      if (point.latitude == null || point.longitude == null) continue;
      final distance = _calculateHaversineDistance(
        latitude, longitude, point.latitude!, point.longitude!
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return {'distance': minDistance, 'index': closestIndex};
  }
  
  /// 📊 **Calculate Progress Percentage**
  double _calculateProgressPercentage() {
    if (_route.elevationPoints.isEmpty) return 0.0;
    
    final totalRoutePoints = _route.elevationPoints.length;
    return (_currentSegmentIndex / (totalRoutePoints - 1)).clamp(0.0, 1.0);
  }
  
  /// 📏 **Calculate Remaining Distance**
  double _calculateRemainingDistance(int currentIndex) {
    if (_route.elevationPoints.isEmpty || currentIndex >= _route.elevationPoints.length - 1) {
      return 0.0;
    }
    
    double remainingDistance = 0.0;
    for (int i = currentIndex; i < _route.elevationPoints.length - 1; i++) {
      final current = _route.elevationPoints[i];
      final next = _route.elevationPoints[i + 1];
      if (current.latitude == null || current.longitude == null ||
          next.latitude == null || next.longitude == null) continue;
      remainingDistance += _calculateHaversineDistance(
        current.latitude!, current.longitude!, next.latitude!, next.longitude!
      );
    }
    
    return remainingDistance;
  }
  
  /// 🏃‍♂️ **Check for Milestones**
  List<RouteMilestone> _checkForMilestones(double latitude, double longitude) {
    final newMilestones = <RouteMilestone>[];
    
    // Check POI milestones
    for (int i = 0; i < _route.pointsOfInterest.length; i++) {
      if (_passedMilestones.contains(i)) continue;
      
      final poi = _route.pointsOfInterest[i];
      final distance = _calculateHaversineDistance(
        latitude, longitude, poi.latitude, poi.longitude
      );
      
      if (distance <= _milestoneProximityThreshold) {
        _passedMilestones.add(i);
        newMilestones.add(RouteMilestone(
          type: MilestoneType.pointOfInterest,
          name: poi.name,
          description: poi.description ?? 'Point of Interest',
          location: LocationPoint(
            latitude: poi.latitude,
            longitude: poi.longitude,
            elevation: 0.0,
            timestamp: DateTime.now(),
            accuracy: 0.0,
          ),
          distanceFromStart: _routeDistanceTraveled,
        ));
      }
    }
    
    // Check distance milestones (every km)
    final kmMarks = (_routeDistanceTraveled / 1000).floor();
    final lastKmMark = ((_routeDistanceTraveled - 100) / 1000).floor(); // Previous update
    
    if (kmMarks > lastKmMark && kmMarks > 0) {
      newMilestones.add(RouteMilestone(
        type: MilestoneType.distance,
        name: '${kmMarks}km Mark',
        description: 'Distance milestone reached',
        location: LocationPoint(
          latitude: latitude,
          longitude: longitude,
          elevation: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
        ),
        distanceFromStart: _routeDistanceTraveled,
      ));
    }
    
    // Check elevation milestones (significant elevation changes)
    if (_route.elevationPoints.isNotEmpty) {
      final currentElevation = _getElevationAtPosition(_currentSegmentIndex);
      if (currentElevation != null) {
        // Check for peak/valley milestones
        final elevationMilestone = _checkElevationMilestone(currentElevation, latitude, longitude);
        if (elevationMilestone != null) {
          newMilestones.add(elevationMilestone);
        }
      }
    }
    
    return newMilestones;
  }
  
  /// ⛰️ **Check Elevation Milestone**
  RouteMilestone? _checkElevationMilestone(double currentElevation, double latitude, double longitude) {
    // This would implement peak/valley detection logic
    // For now, return null - can be enhanced later
    return null;
  }
  
  /// 📈 **Calculate Route Deviation**
  RouteDeviation _calculateRouteDeviation() {
    if (_actualPath.length < 2) {
      return RouteDeviation(
        averageDeviation: 0.0,
        maxDeviation: 0.0,
        deviationPoints: [],
        timeOffRoute: Duration.zero,
      );
    }
    
    double totalDeviation = 0.0;
    double maxDeviation = 0.0;
    int offRouteCount = 0;
    final deviationPoints = <DeviationPoint>[];
    
    for (final point in _actualPath) {
      final closestResult = _findClosestPointOnRoute(point.latitude, point.longitude);
      final deviation = closestResult['distance'] as double;
      
      totalDeviation += deviation;
      maxDeviation = math.max(maxDeviation, deviation);
      
      if (deviation > _onRouteThreshold) {
        offRouteCount++;
        deviationPoints.add(DeviationPoint(
          location: point,
          deviationDistance: deviation,
          timestamp: DateTime.now(), // Approximate
        ));
      }
    }
    
    final averageDeviation = _actualPath.isNotEmpty ? totalDeviation / _actualPath.length : 0.0;
    final timeOffRoute = Duration(seconds: offRouteCount * 5); // Approximate 5 seconds per point
    
    return RouteDeviation(
      averageDeviation: averageDeviation,
      maxDeviation: maxDeviation,
      deviationPoints: deviationPoints,
      timeOffRoute: timeOffRoute,
    );
  }
  
  /// 🎯 **Get Elevation at Position**
  double? _getElevationAtPosition(int segmentIndex) {
    if (_route.elevationPoints.isEmpty || segmentIndex >= _route.elevationPoints.length) {
      return null;
    }
    return _route.elevationPoints[segmentIndex].elevationM;
  }
  
  /// 📍 **Get Next Waypoint**
  RouteWaypoint? _getNextWaypoint(int currentIndex) {
    // Look for next POI after current position
    for (final poi in _route.pointsOfInterest) {
      // This would need route index mapping for POIs
      // For now, return a simple next waypoint
    }
    
    // Return finish line if near end
    if (currentIndex >= _route.elevationPoints.length - 10) {
      final finishPoint = _route.elevationPoints.last;
      if (finishPoint.latitude != null && finishPoint.longitude != null) {
        return RouteWaypoint(
          name: 'Finish',
          type: 'finish',
          location: LocationPoint(
            latitude: finishPoint.latitude!,
            longitude: finishPoint.longitude!,
            elevation: finishPoint.elevationM,
            timestamp: DateTime.now(),
            accuracy: 0.0,
          ),
          description: 'Route finish point',
        );
      }
    }
    
    // Return a point 500m ahead
    final lookAheadDistance = 500.0; // meters
    double accumulatedDistance = 0.0;
    
    for (int i = currentIndex; i < _route.elevationPoints.length - 1; i++) {
      final current = _route.elevationPoints[i];
      final next = _route.elevationPoints[i + 1];
      if (current.latitude == null || current.longitude == null ||
          next.latitude == null || next.longitude == null) continue;
      final segmentDistance = _calculateHaversineDistance(
        current.latitude!, current.longitude!, next.latitude!, next.longitude!
      );
      
      accumulatedDistance += segmentDistance;
      if (accumulatedDistance >= lookAheadDistance) {
        return RouteWaypoint(
          name: 'Next Point',
          type: 'navigation',
          location: LocationPoint(
            latitude: next.latitude!,
            longitude: next.longitude!,
            elevation: next.elevationM,
            timestamp: DateTime.now(),
            accuracy: 0.0,
          ),
          description: 'Continue straight',
        );
      }
    }
    
    return null;
  }
  
  /// 📏 **Get Distance to Next Waypoint**
  double? _getDistanceToNextWaypoint(double latitude, double longitude, int currentIndex) {
    final nextWaypoint = _getNextWaypoint(currentIndex);
    if (nextWaypoint == null) return null;
    
    return _calculateHaversineDistance(
      latitude, longitude, 
      nextWaypoint.location.latitude, nextWaypoint.location.longitude
    );
  }
  
  /// 📐 **Calculate Haversine Distance**
  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
  
  /// 🔄 **Reset Tracker**
  void reset() {
    _currentSegmentIndex = 0;
    _totalDistanceTraveled = 0.0;
    _routeDistanceTraveled = 0.0;
    _actualPath.clear();
    _passedMilestones.clear();
    _averageSpeed = 0.0;
    _currentSpeed = 0.0;
    _timeOnRoute = Duration.zero;
    _lastUpdateTime = null;
    _isOnRoute = true;
  }
  
  /// 🗑️ **Dispose Resources**
  void dispose() {
    _progressController.close();
  }
  
  /// 📊 **Get Current Progress Summary**
  RouteProgressSummary getCurrentSummary() {
    return RouteProgressSummary(
      progressPercentage: _calculateProgressPercentage(),
      totalDistanceTraveled: _totalDistanceTraveled,
      routeDistanceTraveled: _routeDistanceTraveled,
      remainingDistance: _calculateRemainingDistance(_currentSegmentIndex),
      averageSpeed: _averageSpeed,
      currentSpeed: _currentSpeed,
      timeOnRoute: _timeOnRoute,
      isOnRoute: _isOnRoute,
      milestonesReached: _passedMilestones.length,
    );
  }
}

/// 📈 **Route Progress Update**
class RouteProgressUpdate {
  final LocationPoint currentLocation;
  final double distanceToRoute;
  final bool isOnRoute;
  final bool wasOnRoute;
  final int currentSegmentIndex;
  final double progressPercentage;
  final double totalDistanceTraveled;
  final double routeDistanceTraveled;
  final double remainingDistance;
  final double currentSpeed;
  final double averageSpeed;
  final Duration timeOnRoute;
  final List<RouteMilestone> newMilestones;
  final RouteDeviation routeDeviation;
  final double? elevationAtCurrentPosition;
  final RouteWaypoint? nextWaypoint;
  final double? distanceToNextWaypoint;
  
  const RouteProgressUpdate({
    required this.currentLocation,
    required this.distanceToRoute,
    required this.isOnRoute,
    required this.wasOnRoute,
    required this.currentSegmentIndex,
    required this.progressPercentage,
    required this.totalDistanceTraveled,
    required this.routeDistanceTraveled,
    required this.remainingDistance,
    required this.currentSpeed,
    required this.averageSpeed,
    required this.timeOnRoute,
    required this.newMilestones,
    required this.routeDeviation,
    this.elevationAtCurrentPosition,
    this.nextWaypoint,
    this.distanceToNextWaypoint,
  });
}

/// 🏆 **Route Milestone**
class RouteMilestone {
  final MilestoneType type;
  final String name;
  final String description;
  final LocationPoint location;
  final double distanceFromStart;
  
  const RouteMilestone({
    required this.type,
    required this.name,
    required this.description,
    required this.location,
    required this.distanceFromStart,
  });
}

/// 📊 **Route Deviation Data**
class RouteDeviation {
  final double averageDeviation;
  final double maxDeviation;
  final List<DeviationPoint> deviationPoints;
  final Duration timeOffRoute;
  
  const RouteDeviation({
    required this.averageDeviation,
    required this.maxDeviation,
    required this.deviationPoints,
    required this.timeOffRoute,
  });
}

/// 📍 **Deviation Point**
class DeviationPoint {
  final LocationPoint location;
  final double deviationDistance;
  final DateTime timestamp;
  
  const DeviationPoint({
    required this.location,
    required this.deviationDistance,
    required this.timestamp,
  });
}

/// 🎯 **Route Waypoint**
class RouteWaypoint {
  final String name;
  final String type;
  final LocationPoint location;
  final String description;
  
  const RouteWaypoint({
    required this.name,
    required this.type,
    required this.location,
    required this.description,
  });
}

/// 📊 **Route Progress Summary**
class RouteProgressSummary {
  final double progressPercentage;
  final double totalDistanceTraveled;
  final double routeDistanceTraveled;
  final double remainingDistance;
  final double averageSpeed;
  final double currentSpeed;
  final Duration timeOnRoute;
  final bool isOnRoute;
  final int milestonesReached;
  
  const RouteProgressSummary({
    required this.progressPercentage,
    required this.totalDistanceTraveled,
    required this.routeDistanceTraveled,
    required this.remainingDistance,
    required this.averageSpeed,
    required this.currentSpeed,
    required this.timeOnRoute,
    required this.isOnRoute,
    required this.milestonesReached,
  });
}

/// 🏆 **Milestone Types**
enum MilestoneType {
  pointOfInterest,
  distance,
  elevation,
  time,
  waypoint,
}
