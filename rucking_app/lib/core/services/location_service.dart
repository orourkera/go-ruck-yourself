import 'dart:math' show cos, sqrt, asin, pi, sin, atan2;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/background_location_service.dart';

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
  static const double _minDistanceFilter = 5.0; // Balanced: 5m like FitoTrack for better battery
  static const int _batchInterval = 15; // Longer batching like FitoTrack for efficiency
  
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
    try {
      AppLogger.info('Requesting location permissions...');
      
      // First request basic location permission
      final whenInUseStatus = await Permission.locationWhenInUse.request();
      AppLogger.info('When-in-use permission: $whenInUseStatus');
      
      if (whenInUseStatus.isGranted) {
        // For long workout sessions, also request always permission for background tracking
        if (Platform.isIOS) {
          AppLogger.info('Requesting background location permission for iOS...');
          final alwaysStatus = await Permission.locationAlways.request();
          AppLogger.info('Always permission: $alwaysStatus');
          
          // iOS background location requires always permission
          return alwaysStatus.isGranted;
        } else {
          // Android can work with when-in-use + foreground service
          // Request exclusion from battery optimisations so the OS does not throttle
          // the foreground service while a workout is active. This is critical on
          // OEM builds such as Samsung OneUI or Xiaomi MIUI that are very
          // aggressive in killing background location.
          if (await Permission.ignoreBatteryOptimizations.isDenied) {
            AppLogger.info('Requesting ignore battery optimisations...');
            await Permission.ignoreBatteryOptimizations.request();
          }
          return true;
        }
      }
      
      // Fall back to Geolocator's permission request if needed
      AppLogger.info('Falling back to Geolocator permission request...');
      final permission = await Geolocator.requestPermission();
      AppLogger.info('Geolocator permission result: $permission');
      
      return permission == LocationPermission.always || 
             permission == LocationPermission.whileInUse;
    } catch (e) {
      AppLogger.error('Error requesting location permissions', exception: e);
      return false;
    }
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
    
    // Configure location settings for both platforms
    late LocationSettings locationSettings;
    
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _minDistanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 5), // FitoTrack: 5s interval for better battery
        // Critical: Configure foreground service for background tracking
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Ruck in Progress',
          notificationText: 'Tracking your ruck session - tap to return to app',
          enableWakeLock: true, // Prevent CPU sleep
          notificationChannelName: 'Ruck Session Tracking',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          setOngoing: true, // Prevents dismissal during active sessions
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _minDistanceFilter.toInt(), // Fix type error by converting double _minDistanceFilter to int
        pauseLocationUpdatesAutomatically: false, // Critical: Keep GPS active in background
        activityType: ActivityType.fitness, // Optimize for fitness tracking
        showBackgroundLocationIndicator: true, // Required for background location
        allowBackgroundLocationUpdates: true, // Enable background updates
      );
    } else {
      // Fallback for other platforms
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1, // Convert from _minDistanceFilter (1.0) to int
      );
    }
    
    // Raw position stream with platform-specific settings
    final positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
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
    
    // Integrate with background location service
    BackgroundLocationService.startBackgroundTracking().catchError((error) {
      AppLogger.error('Failed to start background service: $error');
    });
    
    return _batchedLocationController.stream;
  }
  
  @override
  Future<void> stopLocationTracking() async {
    await _rawLocationSubscription?.cancel();
    _batchTimer?.cancel();
    
    // Stop background location service
    await BackgroundLocationService.stopBackgroundTracking();
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