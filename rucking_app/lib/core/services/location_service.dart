import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/core/models/location_point.dart';

/// Interface for location services
abstract class LocationService {
  /// Check if location permissions are granted
  Future<bool> hasLocationPermission();
  
  /// Request location permissions
  Future<bool> requestLocationPermission();
  
  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled();
  
  /// Open location settings
  Future<bool> openLocationSettings();
  
  /// Get current location
  Future<LocationPoint> getCurrentLocation();
  
  /// Start tracking location
  Stream<LocationPoint> startLocationTracking({int intervalMs = 1000});
  
  /// Stop tracking location
  Future<void> stopLocationTracking();
  
  /// Calculate distance between two points in kilometers
  double calculateDistance(LocationPoint point1, LocationPoint point2);
}

/// Implementation of LocationService using Geolocator
class LocationServiceImpl implements LocationService {
  StreamSubscription<Position>? _positionStreamSubscription;
  final _locationController = StreamController<LocationPoint>.broadcast();
  
  @override
  Future<bool> hasLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  @override
  Future<bool> requestLocationPermission() async {
    // First try the permission_handler for a more user-friendly dialog
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) return true;
    
    // Fall back to Geolocator's permission request if needed
    LocationPermission permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  @override
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
  
  @override
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
  
  @override
  Future<LocationPoint> getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    
    return LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude,
      timestamp: DateTime.now(),
      accuracy: position.accuracy,
    );
  }
  
  @override
  Stream<LocationPoint> startLocationTracking({int intervalMs = 1000}) {
    debugPrint('Starting location tracking with interval: $intervalMs ms');
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // minimum distance to travel before updates
      // timeLimit REMOVED to allow indefinite waiting for a fix
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .map((position) => LocationPoint(
              latitude: position.latitude,
              longitude: position.longitude,
              elevation: position.altitude,
              timestamp: DateTime.now(),
              accuracy: position.accuracy,
            ))
        .handleError((error) {
          debugPrint('Location tracking error (continuing stream): $error');
          // Do nothing on error to keep the stream alive; next update will retry
        });
  }
  
  @override
  Future<void> stopLocationTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }
  
  @override
  double calculateDistance(LocationPoint point1, LocationPoint point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    ) / 1000; // Convert meters to kilometers
  }
  
  /// Dispose of resources
  void dispose() {
    stopLocationTracking();
    _locationController.close();
  }
} 