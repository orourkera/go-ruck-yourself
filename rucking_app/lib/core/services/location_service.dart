import 'dart:async';
import 'dart:math' show cos, sqrt, asin, pi, sin, atan2;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Interface for location services
abstract class LocationService {
  /// Check if the app has location permission 
  Future<bool> hasLocationPermission();
  
  /// Request location permission from the user
  Future<bool> requestLocationPermission();
  
  /// Get the current location once
  Future<LocationPoint?> getCurrentLocation();
  
  /// Start tracking location updates continuously
  Stream<LocationPoint> startLocationTracking();
  
  /// Stop tracking location updates
  Future<void> stopLocationTracking();
  
  /// Calculate distance between two points in kilometers
  double calculateDistance(LocationPoint point1, LocationPoint point2);
}

/// Implementation of location service using Geolocator
class LocationServiceImpl implements LocationService {
  static const double _minDistanceFilter = 1.0; // Reduced from 5.0 to 1.0 meters for better accuracy
  static const int _batchInterval = 5; // Send batch updates every 5 seconds
  
  final List<LocationPoint> _locationBatch = [];
  Timer? _batchTimer;
  final StreamController<LocationPoint> _batchedLocationController = StreamController<LocationPoint>.broadcast();
  StreamSubscription<Position>? _rawLocationSubscription;
  
  @override
  Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  @override
  Future<bool> requestLocationPermission() async {
    // First try the permission_handler for a more user-friendly dialog
    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) return true;
    
    // Fall back to Geolocator's permission request if needed
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  @override
  Future<LocationPoint?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      return LocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        elevation: position.altitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error('Failed to get current location: $e');
      return null;
    }
  }
  
  @override
  Stream<LocationPoint> startLocationTracking() {
    // Cancel any existing subscriptions
    _rawLocationSubscription?.cancel();
    
    // Start a timer for batched updates
    _batchTimer = Timer.periodic(Duration(seconds: _batchInterval), (_) {
      _sendBatchUpdate();
    });
    
    // Raw position stream with distance filter
    final positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best, // Changed from high to best for maximum accuracy
        distanceFilter: _minDistanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 1), // Update every second for better tracking
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Rucking in Progress',
          notificationText: 'Tracking your ruck session',
          enableWakeLock: true,
        ),
      ),
    );
    
    // Subscribe to raw positions and convert to LocationPoint objects
    _rawLocationSubscription = positionStream.listen(
      (Position position) {
        final locationPoint = LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          elevation: position.altitude,
          accuracy: position.accuracy,
          timestamp: DateTime.now(),
        );
        
        // Add to batch and immediately send to local stream
        _locationBatch.add(locationPoint);
        _batchedLocationController.add(locationPoint);
      },
      onError: (error) {
        AppLogger.error('Location service error: $error');
        _batchedLocationController.addError(error);
      },
    );
    
    return _batchedLocationController.stream;
  }
  
  @override
  Future<void> stopLocationTracking() async {
    await _rawLocationSubscription?.cancel();
    _batchTimer?.cancel();
  }
  
  /// Send a batch of location updates to the API
  void _sendBatchUpdate() {
    if (_locationBatch.isEmpty) return;
    
    // For now, we're just clearing the batch
    // In a real implementation, you would send the batch to your API
    AppLogger.info('Sending batch of ${_locationBatch.length} location points');
    _locationBatch.clear();
  }
  
  @override
  double calculateDistance(LocationPoint point1, LocationPoint point2) {
    // Standard Haversine formula for calculating distance between two lat/lng points
    const double earthRadius = 6371.0; // Earth's radius in kilometers
    
    final double lat1Rad = point1.latitude * (pi / 180);
    final double lat2Rad = point2.latitude * (pi / 180);
    final double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    final double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);
    
    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) * 
        sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a)); // CORRECT: sqrt(1 - a)
    
    return earthRadius * c; // Return distance in kilometers
  }
  
  /// Dispose of resources
  void dispose() {
    _rawLocationSubscription?.cancel();
    _batchTimer?.cancel();
    _batchedLocationController.close();
  }
}