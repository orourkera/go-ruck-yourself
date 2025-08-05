import 'dart:math' show cos, sqrt, asin, pi, sin, atan2;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color, BuildContext;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:rucking_app/core/models/location_point.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/services/background_location_service.dart';
import 'package:rucking_app/shared/widgets/location_disclosure_dialog.dart';

/// Location tracking modes for adaptive optimization
enum LocationTrackingMode {
  /// High accuracy mode - best for normal conditions
  high,
  /// Balanced mode - reduces battery usage
  balanced,
  /// Power save mode - minimal GPS usage during memory pressure
  powerSave,
  /// Emergency mode - bare minimum for data preservation
  emergency,
}

/// Configuration for location tracking
class LocationTrackingConfig {
  final double distanceFilter;
  final int batchInterval;
  final LocationAccuracy accuracy;
  final LocationTrackingMode mode;
  
  const LocationTrackingConfig({
    required this.distanceFilter,
    required this.batchInterval,
    required this.accuracy,
    required this.mode,
  });
  
  /// High accuracy configuration
  static const LocationTrackingConfig high = LocationTrackingConfig(
    distanceFilter: 3.0,
    batchInterval: 10,
    accuracy: LocationAccuracy.bestForNavigation,
    mode: LocationTrackingMode.high,
  );
  
  /// Balanced configuration
  static const LocationTrackingConfig balanced = LocationTrackingConfig(
    distanceFilter: 5.0,
    batchInterval: 15,
    accuracy: LocationAccuracy.best,
    mode: LocationTrackingMode.balanced,
  );
  
  /// Power save configuration
  static const LocationTrackingConfig powerSave = LocationTrackingConfig(
    distanceFilter: 10.0,
    batchInterval: 30,
    accuracy: LocationAccuracy.high,
    mode: LocationTrackingMode.powerSave,
  );
  
  /// Emergency configuration
  static const LocationTrackingConfig emergency = LocationTrackingConfig(
    distanceFilter: 15.0,
    batchInterval: 60,
    accuracy: LocationAccuracy.medium,
    mode: LocationTrackingMode.emergency,
  );
}

/// Interface for location services
abstract class LocationService {
  /// Check if the app has location permission 
  Future<bool> hasLocationPermission();
  
  /// Request location permission from the user
  /// For Android: Shows prominent disclosure dialog first (Google Play compliance)
  /// For iOS: Direct permission request
  Future<bool> requestLocationPermission({BuildContext? context});
  
  /// Get the current location once
  Future<LocationPoint?> getCurrentLocation();
  
  /// Start tracking location updates continuously
  Stream<LocationPoint> startLocationTracking();
  
  /// Stream of batched location points for API upload
  Stream<List<LocationPoint>> get batchedLocationUpdates;
  
  /// Stop tracking location updates
  Future<void> stopLocationTracking();
  
  /// Calculate distance between two points in kilometers
  double calculateDistance(LocationPoint point1, LocationPoint point2);
  
  /// Adjust location tracking frequency based on memory pressure
  void adjustTrackingFrequency(LocationTrackingMode mode);
  
  /// Get current tracking configuration
  LocationTrackingConfig get currentTrackingConfig;
}

/// Implementation of location service using Geolocator
class LocationServiceImpl implements LocationService {
  // Whether we have permission to start Android foreground location service
  bool _canStartForegroundService = false;
  static const int _locationTimeoutSeconds = 30; // Location timeout detection
  static const int _stalenessCheckSeconds = 45; // Check for stale location updates
  
  // Dynamic configuration for adaptive tracking
  LocationTrackingConfig _currentConfig = LocationTrackingConfig.high;
  
  final List<LocationPoint> _locationBatch = [];
  Timer? _batchTimer;
  Timer? _locationTimeoutTimer;
  Timer? _stalenessCheckTimer;
  final StreamController<LocationPoint> _locationController = StreamController<LocationPoint>.broadcast();
  final StreamController<List<LocationPoint>> _batchController = StreamController<List<LocationPoint>>.broadcast();
  StreamSubscription<Position>? _rawLocationSubscription;
  DateTime? _lastLocationUpdate;
  LocationPoint? _lastValidLocation;
  bool _isTracking = false;
  
  @override
  Stream<List<LocationPoint>> get batchedLocationUpdates => _batchController.stream;
  
  @override
  LocationTrackingConfig get currentTrackingConfig => _currentConfig;
  
  @override
  Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always || 
           permission == LocationPermission.whileInUse;
  }
  
  @override
  Future<bool> requestLocationPermission({BuildContext? context}) async {
    try {
      AppLogger.info('Requesting location permissions...');
      
      // Check current permission status first
      final currentPermission = await Geolocator.checkPermission();
      if (currentPermission == LocationPermission.always || 
          currentPermission == LocationPermission.whileInUse) {
        AppLogger.info('Location permission already granted: $currentPermission');

         if (Platform.isAndroid) {
           _canStartForegroundService = true;
         }
         return true;
      }
      
      // Show prominent disclosure dialog first (required for Google Play compliance)
      // Only show on Android - iOS has its own system permission flow
      if (context != null && Platform.isAndroid) {
        AppLogger.info('[REQUIRED] Showing location disclosure dialog...');
        final userConsent = await LocationDisclosureDialog.show(context);
        
        if (!userConsent) {
          AppLogger.info('User declined location disclosure');
          return false;
        }
        
        AppLogger.info('User accepted location disclosure, proceeding with system permission...');
      } else if (context == null && Platform.isAndroid) {
        AppLogger.warning('No context provided for disclosure dialog, proceeding directly to system permission');
      }
      
      // Request basic location permission using Geolocator (single dialog)
      final permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.always || 
          permission == LocationPermission.whileInUse) {
        AppLogger.info('Location permission granted: $permission');

         if (Platform.isAndroid) {
           _canStartForegroundService = true;
         }
        
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
      // Monitor location permission failures (critical for fitness tracking) - wrapped to prevent secondary errors
      try {
        await AppErrorHandler.handleCriticalError(
          'location_permission_request',
          e,
          context: {
            'has_context': context != null,
            'platform': Platform.isAndroid ? 'android' : 'ios',
          },
        );
      } catch (errorHandlerException) {
        AppLogger.error('Error reporting failed during location permission request: $errorHandlerException');
      }
      AppLogger.error('Error requesting location permissions', exception: e);
      return false;
    }
  }
  
  @override
  Future<LocationPoint?> getCurrentLocation() async {
    try {
      AppLogger.info('📍 Requesting current location with timeout...');
      
      // Check permissions first to prevent kCLErrorDomain error 1
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        AppLogger.warning('Location permission not granted - cannot get current location');
        throw PositionUpdateException(
          'Location permission required. Please enable location services in Settings.'
        );
      }
      
      // 🔥 FIX: Add timeout to prevent app hangs
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10), // Prevent infinite wait
      ).timeout(
        const Duration(seconds: 15), // Double timeout protection
        onTimeout: () {
          AppLogger.warning('⏰ Location request timed out after 15 seconds');
          throw TimeoutException('Location request timed out', const Duration(seconds: 15));
        },
      );
      
      return LocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        elevation: position.altitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      );
    } catch (e) {
      // Handle specific iOS location permission errors more gracefully
      if (e is PositionUpdateException && e.toString().contains('kCLErrorDomain error 1')) {
        AppLogger.warning('iOS location permission denied - user needs to enable location services');
        // Don't report permission denials as critical errors
        return null;
      }
      
      // Monitor location retrieval failures (critical for fitness tracking) - wrapped to prevent secondary errors
      try {
        await AppErrorHandler.handleError(
          'location_current_position',
          e,
          context: {
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'error_type': e.runtimeType.toString(),
          },
        );
      } catch (errorHandlerException) {
        AppLogger.error('Error reporting failed during location retrieval: $errorHandlerException');
      }
      AppLogger.error('Failed to get current location: $e');
      return null;
    }
  }
  
  @override
  Stream<LocationPoint> startLocationTracking() {
    
    AppLogger.info('Starting location tracking with enhanced Android protection...');
    
    // Check permissions before starting tracking to prevent kCLErrorDomain error 1
    _checkPermissionsAndStartTracking();
    
    return _locationController.stream;
  }
  
  /// Checks permissions and starts tracking, handling permission errors gracefully
  Future<void> _checkPermissionsAndStartTracking() async {
    try {
      // Check if we have location permissions
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        AppLogger.warning('Location permission not granted - cannot start tracking');
        
        // Emit a user-friendly error to the stream
        _locationController.addError(
          PositionUpdateException(
            'Location permission required. Please enable location services in Settings.'
          )
        );
        return;
      }
      
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.warning('Location services disabled - cannot start tracking');
        
        // Emit a user-friendly error to the stream
        _locationController.addError(
          PositionUpdateException(
            'Location services are disabled. Please enable location services in Settings.'
          )
        );
        return;
      }
      
      AppLogger.info('Location permissions verified - starting position stream');
      _startLocationStream();
    } catch (e) {
      AppLogger.error('Error checking permissions before starting location tracking', exception: e);
      _locationController.addError(e);
    }
  }
  
  /// Starts the actual location stream after permissions are verified
  void _startLocationStream() {
    _isTracking = true;
    _lastLocationUpdate = DateTime.now();
    
    // Configure location settings based on platform
    late LocationSettings locationSettings;
    
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: _currentConfig.accuracy,
        distanceFilter: _currentConfig.distanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 5), // Force frequent updates
        foregroundNotificationConfig: _canStartForegroundService ? const ForegroundNotificationConfig(
          notificationTitle: 'Ruck in Progress',
          notificationText: 'Tracking your ruck session - tap to return to app',
          enableWakeLock: true, // Prevent CPU sleep
          enableWifiLock: true, // Prevent WiFi sleep
          notificationChannelName: 'Ruck Session Tracking',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          setOngoing: true, // Prevents dismissal during active sessions
          color: Color.fromARGB(255, 255, 165, 0), // Orange color for high visibility
        ) : null,
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: _currentConfig.accuracy,
        distanceFilter: _currentConfig.distanceFilter.toInt(),
        pauseLocationUpdatesAutomatically: false, // Critical: Keep GPS active in background
        activityType: ActivityType.fitness, // Optimize for fitness tracking
        showBackgroundLocationIndicator: true, // Required for background location
        allowBackgroundLocationUpdates: true, // Enable background updates
      );
    } else {
      // Fallback for other platforms
      locationSettings = LocationSettings(
        accuracy: _currentConfig.accuracy,
        distanceFilter: _currentConfig.distanceFilter.toInt(),
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
          timestamp: position.timestamp,
        );
        
        // Log elevation data for debugging iOS vs Android differences
        AppLogger.debug('Location point created - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, Elevation: ${position.altitude}m, Accuracy: ${position.accuracy}m, AltAccuracy: ${position.altitudeAccuracy}m');
        
        // Cross-platform location tracking diagnostics (sends to Crashlytics)
        final platform = Platform.isIOS ? 'iOS' : 'Android';
        final timeSinceLastUpdate = _lastLocationUpdate != null 
            ? DateTime.now().difference(_lastLocationUpdate!).inSeconds 
            : 0;
        
        // Critical: Log significant gaps to Crashlytics for production debugging
        if (timeSinceLastUpdate > 60) {
          final issueType = Platform.isIOS ? 'iOS background throttling' : 'Android Doze Mode or battery optimization';
          AppLogger.critical('$platform Location Gap: ${timeSinceLastUpdate}s gap detected - possible $issueType', 
            exception: '${platform}_LOCATION_GAP_${timeSinceLastUpdate}s');
        }
        
        // Log GPS accuracy degradation to Crashlytics (non-critical)
        if (position.accuracy > 30) {
          // Use warning level instead of critical for moderate accuracy issues
          AppLogger.warning('$platform GPS Accuracy Reduced: ${position.accuracy}m accuracy');
        }
        
        // For severe accuracy issues, log with more details
        if (position.accuracy > 100) {
          AppLogger.critical('$platform Very Poor GPS Accuracy: ${position.accuracy}m', 
            exception: 'platform=$platform, accuracy=${position.accuracy}m, lat=${position.latitude.toStringAsFixed(6)}, lng=${position.longitude.toStringAsFixed(6)}');
        }
        
        // Log location gaps (separate from accuracy issues)
        if (timeSinceLastUpdate > 120) {
          AppLogger.warning('$platform Location Update Gap: ${timeSinceLastUpdate}s since last update');
        }
        
        // Add to batch for API calls AND stream for UI updates
        _locationBatch.add(locationPoint);
        _locationController.add(locationPoint); // For UI updates (distance, elevation, map)
        
        // Update last location update timestamp
        _lastLocationUpdate = DateTime.now();
        _lastValidLocation = locationPoint;
        
        AppLogger.debug('Location update: ${position.latitude}, ${position.longitude} (±${position.accuracy}m) - added to batch (${_locationBatch.length} total)');
      },
      onError: (error) async {
        // kCLErrorDomain code 1 (iOS) == permission denied. Treat differently so we don't spam Crashlytics.
        final errorString = error.toString();
        final isPermissionDenied = errorString.contains('kCLErrorDomain error 1') ||
            errorString.contains('PERMISSION_DENIED') ||
            error is PermissionDeniedException;

        if (isPermissionDenied) {
          AppLogger.warning('Location permission denied while tracking – pausing GPS updates');

          // Stop tracking to avoid endless error spam
          await stopLocationTracking();

          // Optionally, you could show a UI prompt or schedule a silent retry later.
          // Here we retry once after 30 s in case the user re-enabled Location Services.
          Timer(const Duration(seconds: 30), () async {
            if (!_isTracking) {
              final hasPermission = await hasLocationPermission();
              final serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (hasPermission && serviceEnabled) {
                AppLogger.info('Permission restored – resuming location tracking');
                _checkPermissionsAndStartTracking();
              } else {
                AppLogger.info('Permission/service still not available after retry');
              }
            }
          });

          // Still report to Crashlytics, but as warning not error - wrapped to prevent secondary errors
          try {
            await AppErrorHandler.handleError(
              'location_permission_denied',
              error,
              context: {
                'is_tracking': _isTracking,
                'platform': Platform.isAndroid ? 'android' : 'ios',
              },
              severity: ErrorSeverity.warning,
            );
          } catch (errorHandlerException) {
            AppLogger.error('Error reporting failed during location permission denial: $errorHandlerException');
          }
          return; // Skip the generic critical-error flow below
        }

        // Other errors – keep existing critical flow - wrapped to prevent secondary errors
        try {
          await AppErrorHandler.handleError(
            'location_tracking_stream',
            error,
            context: {
              'is_tracking': _isTracking,
              'batch_size': _locationBatch.length,
              'last_update': _lastLocationUpdate?.toIso8601String(),
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          );
        } catch (errorHandlerException) {
          AppLogger.error('Error reporting failed during location tracking stream error: $errorHandlerException');
        }
        AppLogger.error('Location service error', exception: error);
        _locationController.addError(error);

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
    BackgroundLocationService.startBackgroundTracking().catchError((error) async {
      // Monitor background location service failures (critical for session tracking) - wrapped to prevent secondary errors
      try {
        await AppErrorHandler.handleCriticalError(
          'location_background_service',
          error,
          context: {
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'is_tracking': _isTracking,
          },
        );
      } catch (errorHandlerException) {
        AppLogger.error('Error reporting failed during background location service error: $errorHandlerException');
      }
      AppLogger.error('Failed to start background service', exception: error);
    });
    
    // Start location staleness monitoring
    _startLocationMonitoring();
    
    // Start batch timer
    _batchTimer = Timer.periodic(Duration(seconds: _currentConfig.batchInterval), (timer) {
      _sendBatchUpdate();
    });
  }
  
  /// Start monitoring for stale location updates and restart if needed
  void _startLocationMonitoring() {
    // Safely cancel existing timers
    try {
      _locationTimeoutTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - monitoring location timeout timer cancellation: $e');
    }
    
    try {
      _stalenessCheckTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - monitoring staleness check timer cancellation: $e');
    }
    
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
    
    // Safely cancel existing subscription
    try {
      await _rawLocationSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - restart location subscription cancellation: $e');
    }
    
    // Wait a moment before restarting
    await Future.delayed(const Duration(seconds: 2));
    
    if (!_isTracking) return; // Check if still tracking after delay
    
    // Restart the position stream
    try {
      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: _currentConfig.distanceFilter.toInt(),
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: _canStartForegroundService ? const ForegroundNotificationConfig(
          notificationTitle: 'Ruck in Progress',
          notificationText: 'GPS reconnected - tracking resumed',
          enableWakeLock: true,
          enableWifiLock: true,
          notificationChannelName: 'Ruck Session Tracking',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          setOngoing: true,
        ) : null,
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
            timestamp: position.timestamp,
          );
          
          _locationBatch.add(locationPoint);
          _locationController.add(locationPoint); // For UI updates (distance, elevation, map)
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
          timestamp: position.timestamp,
        );
        
        // Log elevation data for debugging iOS vs Android differences
        AppLogger.debug('Location point created - Platform: ${Platform.isIOS ? 'iOS' : 'Android'}, Elevation: ${position.altitude}m, Accuracy: ${position.accuracy}m, AltAccuracy: ${position.altitudeAccuracy}m');
        
        _locationBatch.add(locationPoint);
        _locationController.add(locationPoint); // For UI updates (distance, elevation, map)
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
    
    final batchCount = _locationBatch.length;
    AppLogger.info('📦 Preparing to send batch of $batchCount location points');
    
    // Broadcast batch update event for active session to handle
    _batchController.add(List<LocationPoint>.from(_locationBatch));
    
    // Clear batch  
    _locationBatch.clear();
    
    AppLogger.info('✅ Batch update signal sent - $batchCount points queued for upload');
  }
  
  @override
  Future<void> stopLocationTracking() async {
    AppLogger.info('Stopping location tracking...');
    _isTracking = false;
    
    // Safely cancel all subscriptions and timers
    try {
      await _rawLocationSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - location subscription cancellation: $e');
    }
    
    try {
      _batchTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - batch timer cancellation: $e');
    }
    
    try {
      _locationTimeoutTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - location timeout timer cancellation: $e');
    }
    
    try {
      _stalenessCheckTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - staleness check timer cancellation: $e');
    }
    
    // Stop background location service with error handling
    try {
      await BackgroundLocationService.stopBackgroundTracking();
    } catch (e) {
      // Log but don't crash - background service stop failures are common
      AppLogger.warning('Background service stop failed (safe to ignore): $e');
    }
    
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
  
  @override
  void adjustTrackingFrequency(LocationTrackingMode mode) {
    AppLogger.info('📡 Adjusting location tracking frequency to: $mode');
    
    // Get new configuration based on mode
    LocationTrackingConfig newConfig;
    switch (mode) {
      case LocationTrackingMode.high:
        newConfig = LocationTrackingConfig.high;
        break;
      case LocationTrackingMode.balanced:
        newConfig = LocationTrackingConfig.balanced;
        break;
      case LocationTrackingMode.powerSave:
        newConfig = LocationTrackingConfig.powerSave;
        break;
      case LocationTrackingMode.emergency:
        newConfig = LocationTrackingConfig.emergency;
        break;
    }
    
    // Only restart if configuration actually changed
    if (_currentConfig.mode != newConfig.mode) {
      _currentConfig = newConfig;
      
      // If currently tracking, restart with new configuration
      if (_isTracking) {
        AppLogger.info('♻️ Restarting location tracking with new configuration');
        _restartLocationTrackingWithNewConfig();
      }
      
      AppLogger.info('✅ Location tracking frequency adjusted: ${newConfig.mode} (${newConfig.distanceFilter}m, ${newConfig.batchInterval}s)');
    } else {
      AppLogger.info('ℹ️ Location tracking already at requested frequency: $mode');
    }
  }
  
  /// Restart location tracking with new configuration
  void _restartLocationTrackingWithNewConfig() async {
    try {
      // Safely cancel current tracking
      try {
        await _rawLocationSubscription?.cancel();
      } catch (e) {
        AppLogger.debug('Safe to ignore - config restart location subscription cancellation: $e');
      }
      
      try {
        _batchTimer?.cancel();
      } catch (e) {
        AppLogger.debug('Safe to ignore - config restart batch timer cancellation: $e');
      }
      
      // Start tracking with new configuration
      final locationSettings = LocationSettings(
        accuracy: _currentConfig.accuracy,
        distanceFilter: _currentConfig.distanceFilter.toInt(),
      );
      
      _rawLocationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (_isTracking) {
            final locationPoint = LocationPoint(
              latitude: position.latitude,
              longitude: position.longitude,
              elevation: position.altitude,
              accuracy: position.accuracy,
              timestamp: position.timestamp,
            );
            
            _locationBatch.add(locationPoint);
            _locationController.add(locationPoint);
            _lastLocationUpdate = DateTime.now();
            _lastValidLocation = locationPoint;
          }
        },
        onError: (error) {
          AppLogger.error('Location stream error after config restart', exception: error);
        },
      );
      
      // Restart batch timer with new interval
      _batchTimer = Timer.periodic(
        Duration(seconds: _currentConfig.batchInterval),
        (_) => _sendBatchUpdate(),
      );
      
      AppLogger.info('🔄 Location tracking restarted with new configuration');
      
    } catch (e) {
      AppLogger.error('Failed to restart location tracking with new config', exception: e);
    }
  }
  
  /// Dispose of resources
  
  void dispose() {
    // Safely dispose of all resources
    try {
      _rawLocationSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose location subscription cancellation: $e');
    }
    
    try {
      _batchTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose batch timer cancellation: $e');
    }
    
    try {
      _locationTimeoutTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose location timeout timer cancellation: $e');
    }
    
    try {
      _stalenessCheckTimer?.cancel();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose staleness check timer cancellation: $e');
    }
    
    try {
      _locationController.close();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose location controller close: $e');
    }
    
    try {
      _batchController.close();
    } catch (e) {
      AppLogger.debug('Safe to ignore - dispose batch controller close: $e');
    }
  }
}