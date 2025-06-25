import 'dart:math' show cos, sqrt, asin, pi, sin, atan2;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color;
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
  static const double _minDistanceFilter = 3.0; // Reduced from 5m for better tracking
  static const int _batchInterval = 10; // Reduced from 15s for more frequent updates
  static const int _locationTimeoutSeconds = 30; // Location timeout detection
  static const int _stalenessCheckSeconds = 45; // Check for stale location updates
  
  final List<LocationPoint> _locationBatch = [];
  Timer? _batchTimer;
  Timer? _locationTimeoutTimer;
  Timer? _stalenessCheckTimer;
  final StreamController<LocationPoint> _batchedLocationController = StreamController<LocationPoint>.broadcast();
  StreamSubscription<Position>? _rawLocationSubscription;
  DateTime? _lastLocationUpdate;
  LocationPoint? _lastValidLocation;
  bool _isTracking = false;
  
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
      
      // Check current permission status first
      final currentPermission = await Geolocator.checkPermission();
      if (currentPermission == LocationPermission.always || 
          currentPermission == LocationPermission.whileInUse) {
        AppLogger.info('Location permission already granted: $currentPermission');
        return true;
      }
      
      // Request basic location permission using Geolocator (single dialog)
      final permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.always || 
          permission == LocationPermission.whileInUse) {
        AppLogger.info('Location permission granted: $permission');
        
        // Only on Android, also request battery optimization exemption
        // Do this separately to avoid dialog conflicts
        if (Platform.isAndroid) {
          // Small delay to avoid dialog conflicts
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (await Permission.ignoreBatteryOptimizations.isDenied) {
            AppLogger.info('Requesting ignore battery optimizations...');
            final batteryStatus = await Permission.ignoreBatteryOptimizations.request();
            AppLogger.info('Battery optimization exemption: $batteryStatus');
          }
        }
        
        return true;
      }
      
      AppLogger.info('Location permission denied: $permission');
      return false;
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
    AppLogger.info('Starting location tracking with enhanced Android protection...');
    _isTracking = true;
    _lastLocationUpdate = DateTime.now();
    
    // Configure location settings based on platform
    late LocationSettings locationSettings;
    
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation, // Upgraded from 'best' for fitness tracking
        distanceFilter: _minDistanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 5), // Force frequent updates
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Ruck in Progress',
          notificationText: 'Tracking your ruck session - tap to return to app',
          enableWakeLock: true, // Prevent CPU sleep
          enableWifiLock: true, // Prevent WiFi sleep
          notificationChannelName: 'Ruck Session Tracking',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          setOngoing: true, // Prevents dismissal during active sessions
          color: Color.fromARGB(255, 255, 165, 0), // Orange color for high visibility
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation, // Critical for elevation
        distanceFilter: _minDistanceFilter.toInt(),
        pauseLocationUpdatesAutomatically: false, // Critical: Keep GPS active in background
        activityType: ActivityType.fitness, // Optimize for fitness tracking
        showBackgroundLocationIndicator: true, // Required for background location
        allowBackgroundLocationUpdates: true, // Enable background updates
      );
    } else {
      // Fallback for other platforms
      locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _minDistanceFilter.toInt(),
      );
    }
    
    // Raw position stream with platform-specific settings
    final positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
    
    // Subscribe to raw positions and convert to LocationPoint objects
    _rawLocationSubscription = positionStream.listen(
      (Position position) {
        if (!_isTracking) return; // Ignore updates if not tracking
        
        final locationPoint = LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          elevation: position.altitude,
          accuracy: position.accuracy,
          timestamp: DateTime.now(),
        );
        
        // Log elevation data for debugging iOS vs Android differences
        AppLogger.debug('Location point created - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, Elevation: ${position.altitude}m, Accuracy: ${position.accuracy}m, AltAccuracy: ${position.altitudeAccuracy}m');
        
        // Validate location quality
        if (position.accuracy > 50) {
          AppLogger.warning('Poor GPS accuracy: ${position.accuracy}m - using fallback');
          // Continue tracking but log the issue
        }
        
        // Add to batch only - don't stream individual points immediately
        _locationBatch.add(locationPoint);
        // _batchedLocationController.add(locationPoint); // Removed: Individual streaming
        
        // Update last location update timestamp
        _lastLocationUpdate = DateTime.now();
        _lastValidLocation = locationPoint;
        
        AppLogger.debug('Location update: ${position.latitude}, ${position.longitude} (±${position.accuracy}m) - added to batch (${_locationBatch.length} total)');
      },
      onError: (error) {
        AppLogger.error('Location service error', exception: error);
        _batchedLocationController.addError(error);
        
        // Attempt to restart location tracking after error
        if (_isTracking) {
          AppLogger.info('Attempting to restart location tracking after error...');
          Timer(const Duration(seconds: 5), () {
            if (_isTracking) {
              _restartLocationTracking();
            }
          });
        }
      },
    );
    
    // Integrate with background location service
    BackgroundLocationService.startBackgroundTracking().catchError((error) {
      AppLogger.error('Failed to start background service', exception: error);
    });
    
    // Start location staleness monitoring
    _startLocationMonitoring();
    
    // Start batch timer
    _batchTimer = Timer.periodic(Duration(seconds: _batchInterval), (timer) {
      _sendBatchUpdate();
    });
    
    return _batchedLocationController.stream;
  }
  
  /// Start monitoring for stale location updates and restart if needed
  void _startLocationMonitoring() {
    _locationTimeoutTimer?.cancel();
    _stalenessCheckTimer?.cancel();
    
    // Check for complete location timeout (no updates at all)
    _locationTimeoutTimer = Timer.periodic(Duration(seconds: _locationTimeoutSeconds), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      
      if (_lastLocationUpdate == null || 
          DateTime.now().difference(_lastLocationUpdate!).inSeconds > _locationTimeoutSeconds) {
        AppLogger.warning('Location timeout detected - attempting restart');
        _restartLocationTracking();
      }
    });
    
    // Check for stale location updates (same location for too long)
    _stalenessCheckTimer = Timer.periodic(Duration(seconds: _stalenessCheckSeconds), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      
      if (_lastValidLocation != null) {
        final timeDiff = DateTime.now().difference(_lastValidLocation!.timestamp).inSeconds;
        if (timeDiff > _stalenessCheckSeconds) {
          AppLogger.warning('Stale location detected (${timeDiff}s old) - requesting fresh location');
          _requestFreshLocation();
        }
      }
    });
  }
  
  /// Restart location tracking when issues are detected
  void _restartLocationTracking() async {
    if (!_isTracking) return;
    
    AppLogger.info('Restarting location tracking...');
    
    // Cancel existing subscription
    await _rawLocationSubscription?.cancel();
    
    // Wait a moment before restarting
    await Future.delayed(const Duration(seconds: 2));
    
    if (!_isTracking) return; // Check if still tracking after delay
    
    // Restart the position stream
    try {
      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _minDistanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Ruck in Progress',
          notificationText: 'GPS reconnected - tracking resumed',
          enableWakeLock: true,
          enableWifiLock: true,
          notificationChannelName: 'Ruck Session Tracking',
          notificationIcon: AndroidResource(name: 'ic_launcher'),
          setOngoing: true,
        ),
      );
      
      final positionStream = Geolocator.getPositionStream(locationSettings: locationSettings);
      
      _rawLocationSubscription = positionStream.listen(
        (Position position) {
          if (!_isTracking) return;
          
          final locationPoint = LocationPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            elevation: position.altitude,
            accuracy: position.accuracy,
            timestamp: DateTime.now(),
          );
          
          // Log elevation data for debugging iOS vs Android differences
          AppLogger.debug('Location point created - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, Elevation: ${position.altitude}m, Accuracy: ${position.accuracy}m, AltAccuracy: ${position.altitudeAccuracy}m');
          
          _locationBatch.add(locationPoint);
          _batchedLocationController.add(locationPoint);
          _lastLocationUpdate = DateTime.now();
          _lastValidLocation = locationPoint;
          
          AppLogger.info('Location tracking resumed successfully');
        },
        onError: (error) {
          AppLogger.error('Location restart failed', exception: error);
        },
      );
    } catch (e) {
      AppLogger.error('Failed to restart location tracking', exception: e);
    }
  }
  
  /// Request a fresh location to break out of stale updates
  void _requestFreshLocation() async {
    try {
      AppLogger.info('Requesting fresh location...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      
      if (_isTracking) {
        final locationPoint = LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          elevation: position.altitude,
          accuracy: position.accuracy,
          timestamp: DateTime.now(),
        );
        
        // Log elevation data for debugging iOS vs Android differences
        AppLogger.debug('Location point created - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, Elevation: ${position.altitude}m, Accuracy: ${position.accuracy}m, AltAccuracy: ${position.altitudeAccuracy}m');
        
        _locationBatch.add(locationPoint);
        _batchedLocationController.add(locationPoint);
        _lastLocationUpdate = DateTime.now();
        _lastValidLocation = locationPoint;
        
        AppLogger.info('Fresh location obtained');
      }
    } catch (e) {
      AppLogger.error('Failed to get fresh location', exception: e);
    }
  }
  
  /// Send a batch of location updates to the API
  void _sendBatchUpdate() {
    AppLogger.info('🔄 Batch timer fired - checking for pending location points...');
    
    if (_locationBatch.isEmpty) {
      AppLogger.info('📭 No location points to batch - skipping');
      return;
    }
    
    AppLogger.info('📦 Preparing to send batch of ${_locationBatch.length} location points');
    
    // Broadcast batch update event for active session to handle
    final batchCopy = List<LocationPoint>.from(_locationBatch);
    _batchedLocationController.add(LocationPoint(
      latitude: 0, // Special marker for batch update
      longitude: 0,
      elevation: 0,
      accuracy: 0,
      timestamp: DateTime.now(),
      // Store batch data in a special way that can be detected
    ));
    
    // For now, store the batch in a static variable that can be accessed
    _pendingBatch = batchCopy;
    _locationBatch.clear();
    
    AppLogger.info('✅ Batch update signal sent - ${batchCopy.length} points queued for upload');
  }
  
  static List<LocationPoint>? _pendingBatch;
  
  /// Get and clear the pending batch of location points
  static List<LocationPoint>? getPendingBatch() {
    final batch = _pendingBatch;
    _pendingBatch = null;
    return batch;
  }
  
  @override
  Future<void> stopLocationTracking() async {
    AppLogger.info('Stopping location tracking...');
    _isTracking = false;
    
    await _rawLocationSubscription?.cancel();
    _batchTimer?.cancel();
    _locationTimeoutTimer?.cancel();
    _stalenessCheckTimer?.cancel();
    
    // Stop background location service
    await BackgroundLocationService.stopBackgroundTracking();
    
    // Clear tracking state
    _lastLocationUpdate = null;
    _lastValidLocation = null;
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
    _locationTimeoutTimer?.cancel();
    _stalenessCheckTimer?.cancel();
    _batchedLocationController.close();
  }
}