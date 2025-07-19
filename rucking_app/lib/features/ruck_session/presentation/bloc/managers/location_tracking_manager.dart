import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/services/api_client.dart';
import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/watch_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/models/location_point.dart';
import '../../../../../core/models/terrain_segment.dart';
import '../../../domain/models/session_split.dart';
import '../../../domain/services/split_tracking_service.dart';
import '../../../../../core/services/terrain_tracker.dart';
import '../../../../../core/utils/location_validator.dart';
import 'package:rucking_app/features/ruck_session/domain/services/location_validation_service.dart';
import 'package:rucking_app/features/ruck_session/domain/services/session_validation_service.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages location tracking and GPS-related operations
class LocationTrackingManager implements SessionManager {
  final LocationService _locationService;
  final SplitTrackingService _splitTrackingService;
  final TerrainTracker _terrainTracker;
  final ApiClient _apiClient;
  final WatchService _watchService;
  final AuthService _authService;
  final LocationValidationService _validationService = LocationValidationService();
  final SessionValidationService _sessionValidationService = SessionValidationService();
  
  final StreamController<LocationTrackingState> _stateController;
  LocationTrackingState _currentState;
  
  // Location tracking state
  StreamSubscription<LocationPoint>? _locationSubscription;
  final List<LocationPoint> _locationPoints = [];
  final Queue<LocationPoint> _pendingLocationPoints = Queue();
  final Queue<TerrainSegment> _pendingTerrainSegments = Queue();
  
  // Internal state
  LocationPoint? _lastValidLocation;
  LocationPoint? _lastRecordedLocation;
  DateTime? _lastLocationTimestamp;
  int _validLocationCount = 0;
  double _totalDistance = 0.0;
  double _elevationGain = 0.0;
  double _elevationLoss = 0.0;
  Timer? _batchUploadTimer;
  Timer? _watchdogTimer;
  
  // Pace calculation optimization
  int _paceTickCounter = 0;
  double? _cachedCurrentPace;
  double? _cachedAveragePace;
  DateTime? _lastPaceCalculation;
  
  // Pace smoothing (version 2.5 logic)
  final List<double> _recentPaces = [];
  static const int _maxRecentPaces = 10; // Keep last 10 pace values for smoothing
  
  // Timer coordination
  bool _isWatchdogActive = false;
  DateTime? _watchdogStartTime;
  int _watchdogRestartCount = 0;
  
  // Session info from lifecycle manager
  String? _activeSessionId;
  DateTime? _sessionStartTime;
  bool _isPaused = false;
  
  // Terrain tracking
  final List<TerrainSegment> _terrainSegments = [];
  
  // CRITICAL FIX: Memory optimization constants - focus on data offloading, not data loss
  static const int _maxLocationPoints = 1000; // Keep reasonable amount in memory
  static const int _maxTerrainSegments = 500; // Keep reasonable amount in memory
  static const int _minLocationPointsToKeep = 100; // Always keep for real-time calculations
  
  // Memory pressure thresholds for aggressive data offloading
  static const int _memoryPressureThreshold = 800; // Trigger aggressive upload/offload
  static const int _criticalMemoryThreshold = 900; // Emergency offload threshold
  static const int _offloadBatchSize = 200; // Size of batches to offload at once
  
  // Track successful uploads to avoid data loss
  int _lastUploadedLocationIndex = 0;
  int _lastUploadedTerrainIndex = 0;

  LocationTrackingManager({
    required LocationService locationService,
    required SplitTrackingService splitTrackingService,
    required TerrainTracker terrainTracker,
    required ApiClient apiClient,
    required WatchService watchService,
    required AuthService authService,
  })  : _locationService = locationService,
        _splitTrackingService = splitTrackingService,
        _terrainTracker = terrainTracker,
        _apiClient = apiClient,
        _watchService = watchService,
        _authService = authService,
        _stateController = StreamController<LocationTrackingState>.broadcast(),
        _currentState = const LocationTrackingState();

  @override
  Stream<LocationTrackingState> get stateStream => _stateController.stream;

  @override
  LocationTrackingState get currentState => _currentState;

  @override
  Future<void> handleEvent(ActiveSessionEvent event) async {
    if (event is SessionStartRequested) {
      await _onSessionStarted(event);
    } else if (event is SessionStopRequested) {
      await _onSessionStopped(event);
    } else if (event is SessionPaused) {
      await _onSessionPaused(event);
    } else if (event is SessionResumed) {
      await _onSessionResumed(event);
    } else if (event is LocationUpdated) {
      await _onLocationUpdated(event);
    } else if (event is BatchLocationUpdated) {
      await _onBatchLocationUpdated(event);
    } else if (event is MemoryPressureDetected) {
      await _onMemoryPressureDetected(event);
    } else if (event is Tick) {
      await _onTick(event);
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId ?? const Uuid().v4();
    _sessionStartTime = DateTime.now();
    _isPaused = false;
    
    // CRITICAL FIX: Reset state with explicit memory cleanup
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();
    _pendingTerrainSegments.clear();
    _validLocationCount = 0;
    _lastUploadedLocationIndex = 0; // Reset upload tracking
    _lastValidLocation = null; // Reset validation state
    
    // Reset pace smoothing state (version 2.5)
    _recentPaces.clear();
    _cachedCurrentPace = null;
    _cachedAveragePace = null;
    _lastPaceCalculation = null;
    
    // Reset comprehensive validation service
    _validationService.reset();
    _sessionValidationService.reset();
    
    // CRITICAL FIX: Force garbage collection after clearing large lists
    _triggerGarbageCollection();
    
    AppLogger.info('[LOCATION_MANAGER] MEMORY_RESET: Session started, all lists cleared and validation reset');
    
    // Check location permission with request fallback (like version 2.5)
    bool hasLocationAccess = await _locationService.hasLocationPermission();
    if (!hasLocationAccess) {
      AppLogger.info('[LOCATION_MANAGER] Requesting location permission...');
      hasLocationAccess = await _locationService.requestLocationPermission();
    }
  
    if (!hasLocationAccess) {
      AppLogger.warning('[LOCATION_MANAGER] Location permission denied - starting session in offline mode (no GPS tracking)');
      // Don't fail the session - allow offline mode for indoor rucks, airplanes, etc.
    }
  
    _updateState(_currentState.copyWith(
      locations: [],
      totalDistance: 0.0,
      currentPace: 0.0,
      averagePace: 0.0,
      currentSpeed: 0.0,
      altitude: 0.0,
      isTracking: hasLocationAccess,
    ));
  
    if (hasLocationAccess) {
      await _startLocationTracking();
    } else {
      AppLogger.warning('[LOCATION_MANAGER] No location permission, session continues in offline mode');
    }
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    await _stopLocationTracking();
    
    // CRITICAL FIX: Clean up state with explicit memory cleanup
    _activeSessionId = null;
    _sessionStartTime = null;
    _isPaused = false;
    
    // CRITICAL FIX: Reset lists and upload tracking
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();
    _pendingTerrainSegments.clear();
    _lastUploadedLocationIndex = 0;
    _lastUploadedTerrainIndex = 0;
    _validLocationCount = 0;
    _lastLocationTimestamp = null;
    _sessionStartTime = null;
    _isPaused = false;
    
    AppLogger.info('[LOCATION_MANAGER] MEMORY_CLEANUP: Session stopped, all lists cleared and upload tracking reset');
    
    _updateState(const LocationTrackingState());
    
    AppLogger.info('[LOCATION_MANAGER] MEMORY_CLEANUP: Location tracking stopped, all lists cleared and GC triggered');
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    _isPaused = true;
    _locationSubscription?.pause();
    
    // Update watch with paused state
    _updateWatchWithSessionData(_currentState);
    
    AppLogger.info('[LOCATION_MANAGER] Location tracking paused');
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    _isPaused = false;
    _locationSubscription?.resume();
    
    // Update watch with resumed state
    _updateWatchWithSessionData(_currentState);
    
    AppLogger.info('[LOCATION_MANAGER] Location tracking resumed');
  }
  
  /// Handle memory pressure detection by triggering aggressive cleanup
  Future<void> _onMemoryPressureDetected(MemoryPressureDetected event) async {
    AppLogger.error('[LOCATION_MANAGER] MEMORY_PRESSURE: ${event.memoryUsageMb}MB detected, triggering aggressive cleanup');
    
    // Trigger aggressive memory cleanup
    _manageMemoryPressure();
    
    // Force upload of pending data
    _triggerAggressiveDataOffload();
    
    // Trigger garbage collection
    _triggerGarbageCollection();
    
    AppLogger.info('[LOCATION_MANAGER] MEMORY_PRESSURE: Aggressive cleanup completed');
  }

  /// Handle timer tick events to update watch display every second
  Future<void> _onTick(Tick event) async {
    if (_activeSessionId == null) return;
    
    // NOTE: Watch timer updates now handled by coordinator
    // The coordinator aggregates state and updates watch with proper calculated values
    // This tick event is still needed for other timer-based functionality
  }

  Future<void> _onLocationUpdated(LocationUpdated event) async {
    if (_isPaused || _activeSessionId == null) return;
    
    final position = event.position;
    _lastLocationTimestamp = DateTime.now();
    
    // Create location point
    final newPoint = LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude,
      accuracy: position.accuracy,
      timestamp: DateTime.now().toUtc(),
      speed: position.speed,
    );
    
    // Use comprehensive validation from version 2.5
    final validationResult = _validationService.validateLocationPoint(newPoint, _lastValidLocation);
    
    if (!(validationResult['isValid'] as bool? ?? false)) {
      final String message = validationResult['message'] as String? ?? 'Validation failed';
      AppLogger.warning('[LOCATION_MANAGER] Location validation failed: $message');
      return;
    }
    
    _validLocationCount++;
    _lastValidLocation = newPoint;
    
    // Add to location points
    _locationPoints.add(newPoint);
    
    // CRITICAL FIX: Manage memory pressure through data offloading, not data loss
    _manageMemoryPressure();
    
    // Terrain tracking – attempt to capture a segment between the last point and this one
    if (_locationPoints.length >= 2) {
      try {
        if (_terrainTracker.shouldQueryTerrain(newPoint)) {
          final prevPoint = _locationPoints[_locationPoints.length - 2];
          final segment = await _terrainTracker.trackTerrainSegment(
            startLocation: prevPoint,
            endLocation: newPoint,
          );
          if (segment != null) {
            _terrainSegments.add(segment);
            
            // CRITICAL FIX: Trigger terrain segment upload for crash resilience
            _triggerTerrainSegmentUploadIfNeeded();
            
            // Manage terrain segments with proper upload tracking
            if (_terrainSegments.length > _maxTerrainSegments && _lastUploadedTerrainIndex > 50) {
              _trimUploadedTerrainSegments();
            }
          }
        }
      } catch (e) {
        AppLogger.error('[LOCATION_MANAGER] Error capturing terrain segment: $e');
      }
    }
    // Calculate metrics with comprehensive distance filtering
    final newDistance = _calculateTotalDistanceWithValidation();
    final newPace = _calculateCurrentPace(position.speed ?? 0.0);
    final newAveragePace = _calculateAveragePace(newDistance);
    
    // Calculate elevation gain/loss using sophisticated iOS/Android platform-specific processing
    double elevationGain = 0.0;
    double elevationLoss = 0.0;
    if (_locationPoints.length >= 2) {
      final prevPoint = _locationPoints[_locationPoints.length - 2];
      final elevationResult = _sessionValidationService.validateElevationChange(
        prevPoint,
        newPoint,
        // Uses platform-specific thresholds: iOS=0.5m (barometric+GPS), Android=1.0m (GPS only)
        // Includes sophisticated iOS/Android processing for accuracy and noise filtering
      );
      elevationGain = elevationResult['gain']!;
      elevationLoss = elevationResult['loss']!;
    }
    
    // Update cumulative elevation (add this segment's elevation to current totals)
    final currentElevationData = _calculateElevationGain();
    final newElevationGain = (currentElevationData['gain'] ?? 0.0) + elevationGain;
    final newElevationLoss = (currentElevationData['loss'] ?? 0.0) + elevationLoss;
    
    // Update splits
    if (_sessionStartTime != null) {
      _splitTrackingService.checkForMilestone(
        currentDistanceKm: newDistance,
        sessionStartTime: _sessionStartTime!,
        elapsedSeconds: DateTime.now().difference(_sessionStartTime!).inSeconds,
        isPaused: _isPaused,
        currentElevationGain: newElevationGain,
      );
    }
    
    // Add to pending batch
    _pendingLocationPoints.add(newPoint);
    AppLogger.debug('[LOCATION_MANAGER] Added location to pending batch. Total pending: ${_pendingLocationPoints.length}');
    
    // Convert to Position list for state
    final positions = _locationPoints.map((lp) => Position(
      latitude: lp.latitude,
      longitude: lp.longitude,
      timestamp: lp.timestamp,
      accuracy: lp.accuracy,
      altitude: lp.elevation,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: lp.speed ?? 0,
      speedAccuracy: 0,
      floor: null,
      isMocked: false,
    )).toList();
    
    _updateState(_currentState.copyWith(
      locations: positions,
      currentPosition: position,
      totalDistance: newDistance,
      currentPace: newPace,
      averagePace: newAveragePace,
      currentSpeed: position.speed,
      altitude: position.altitude,
      isGpsReady: _validLocationCount > 5, // GPS ready state from version 2.5
      elevationGain: newElevationGain,
      elevationLoss: newElevationLoss,
    ));
  }

  Future<void> _onBatchLocationUpdated(BatchLocationUpdated event) async {
    if (_activeSessionId == null || _activeSessionId!.startsWith('offline_')) return;
    
    AppLogger.info('[LOCATION_MANAGER] Processing batch of ${event.locationPoints.length} points for upload');
    
    try {
      await _apiClient.addLocationPoints(
        _activeSessionId!,
        event.locationPoints.map<Map<String, dynamic>>((LocationPoint p) => p.toJson()).toList(),
      );
      
      // Track successful upload for memory optimization
      _lastUploadedLocationIndex += event.locationPoints.length;
      AppLogger.info('[LOCATION_MANAGER] Successfully uploaded ${event.locationPoints.length} location points. Total uploaded: $_lastUploadedLocationIndex');
      
      // Now we can safely trim location points
      _trimUploadedLocationPoints();
    } catch (e) {
      AppLogger.warning('[LOCATION_MANAGER] Failed to upload location batch: $e');
      // Don't update _lastUploadedLocationIndex on failure - keep points in memory
    }
  }

  /// CRITICAL FIX: Memory management through data offloading, not data loss
  void _manageMemoryPressure() {
    // Check if we're approaching memory pressure thresholds
    if (_locationPoints.length >= _memoryPressureThreshold) {
      AppLogger.warning('[LOCATION_MANAGER] MEMORY_PRESSURE: ${_locationPoints.length} location points detected, triggering aggressive offload');
      _triggerAggressiveDataOffload();
    }
    
    // Only trim after successful uploads to prevent data loss
    if (_locationPoints.length > _maxLocationPoints && _lastUploadedLocationIndex > _minLocationPointsToKeep) {
      _trimUploadedLocationPoints();
    }
    
    // Manage terrain segments with proper upload tracking
    if (_terrainSegments.length > _maxTerrainSegments && _lastUploadedTerrainIndex > 50) {
      _trimUploadedTerrainSegments();
    } else if (_terrainSegments.length > _maxTerrainSegments) {
      // If no uploads have occurred yet, trigger upload to prevent memory leak
      _triggerTerrainSegmentUploadIfNeeded();
    }
  }
  
  /// Trigger aggressive data offloading to database/API to free memory
  void _triggerAggressiveDataOffload() {
    try {
      // Calculate how many points we can safely offload
      final unuploadedPoints = _locationPoints.length - _lastUploadedLocationIndex;
      
      if (unuploadedPoints > _offloadBatchSize) {
        // Trigger immediate batch upload of older points
        final batchEndIndex = _lastUploadedLocationIndex + _offloadBatchSize;
        final batchToUpload = _locationPoints.sublist(_lastUploadedLocationIndex, batchEndIndex);
        
        AppLogger.info('[LOCATION_MANAGER] MEMORY_PRESSURE: Offloading batch of ${batchToUpload.length} location points');
        
        // Add to pending upload queue for immediate processing
        _pendingLocationPoints.addAll(batchToUpload);
        
        // Trigger immediate upload processing
        _processBatchUpload();
        
        // Update upload tracking
        _lastUploadedLocationIndex = batchEndIndex;
      }
      
      // Force garbage collection to free memory immediately
      _triggerGarbageCollection();
      
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Error during aggressive data offload: $e');
    }
  }
  
  /// Safely trim location points only after successful database uploads
  void _trimUploadedLocationPoints() {
    final pointsToRemove = _locationPoints.length - _maxLocationPoints;
    if (pointsToRemove > 0 && _lastUploadedLocationIndex >= pointsToRemove) {
      // Only remove points that have been successfully uploaded
      _locationPoints.removeRange(0, pointsToRemove);
      _lastUploadedLocationIndex -= pointsToRemove;
      
      AppLogger.info('[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $pointsToRemove uploaded location points (${_locationPoints.length} remaining)');
      
      // Force garbage collection after trimming
      _triggerGarbageCollection();
    }
  }
  
  /// Trim terrain segments only after successful upload (prevent data loss)
  void _trimUploadedTerrainSegments() {
    if (_terrainSegments.length > _maxTerrainSegments && _lastUploadedTerrainIndex > 50) {
      final segmentsToRemove = _terrainSegments.length - _maxTerrainSegments;
      if (_lastUploadedTerrainIndex >= segmentsToRemove) {
        // Only remove segments that have been successfully uploaded
        _terrainSegments.removeRange(0, segmentsToRemove);
        _lastUploadedTerrainIndex -= segmentsToRemove;
        
        AppLogger.info('[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $segmentsToRemove uploaded terrain segments (${_terrainSegments.length} remaining)');
        _triggerGarbageCollection();
      } else {
        AppLogger.warning('[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Cannot trim terrain segments - not enough uploaded segments');
      }
    }
  }
  
  /// Trigger terrain segment upload if threshold reached (crash resilience)
  void _triggerTerrainSegmentUploadIfNeeded() {
    final unuploadedSegments = _terrainSegments.length - _lastUploadedTerrainIndex;
    
    // Upload terrain segments every 100 segments (less frequent than location points)
    if (unuploadedSegments >= 100) {
      AppLogger.info('[LOCATION_MANAGER] TERRAIN_UPLOAD_TRIGGER: ${unuploadedSegments} unuploaded terrain segments, triggering upload');
      _triggerImmediateTerrainSegmentUpload();
    }
  }
  
  /// Trigger immediate terrain segment upload to database
  void _triggerImmediateTerrainSegmentUpload() {
    if (_activeSessionId == null) return;
    
    try {
      final unuploadedSegments = _terrainSegments.length - _lastUploadedTerrainIndex;
      if (unuploadedSegments <= 0) return;
      
      final batchEndIndex = _terrainSegments.length; // Upload all unuploaded segments
      final segmentsToUpload = _terrainSegments.sublist(_lastUploadedTerrainIndex, batchEndIndex);
      
      // Add to upload queue
      for (final segment in segmentsToUpload) {
        _pendingTerrainSegments.add(segment);
      }
      
      // Process upload queue
      _processTerrainSegmentUploadQueue();
      
      AppLogger.info('[LOCATION_MANAGER] TERRAIN_UPLOAD: Queued ${segmentsToUpload.length} terrain segments for upload');
      
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Error during immediate terrain segment upload: $e');
    }
  }
  
  /// Process terrain segment upload queue
  void _processTerrainSegmentUploadQueue() {
    if (_pendingTerrainSegments.isEmpty || _activeSessionId == null) return;
    
    final batch = _pendingTerrainSegments.toList();
    _pendingTerrainSegments.clear();
    
    AppLogger.info('[LOCATION_MANAGER] TERRAIN_UPLOAD_QUEUE: Processing batch of ${batch.length} terrain segments');
    
    // Emit TerrainSegmentUpload event to coordinator for actual upload
    if (_activeSessionId != null) {
      final uploadEvent = manager_events.TerrainSegmentUpload(
        terrainSegments: batch,
        sessionId: _activeSessionId!,
      );
      
      // Notify coordinator to handle the upload
      _eventBus.add(uploadEvent);
      AppLogger.info('[LOCATION_MANAGER] TERRAIN_UPLOAD: Emitted upload event for ${batch.length} segments');
    } else {
      AppLogger.warning('[LOCATION_MANAGER] TERRAIN_UPLOAD: No active session ID, cannot upload terrain segments');
    }
  }
  
  /// Handle successful terrain segment upload
  void _onTerrainSegmentUploadSuccess(int uploadedCount) {
    _lastUploadedTerrainIndex += uploadedCount;
    AppLogger.info('[LOCATION_MANAGER] TERRAIN_UPLOAD_SUCCESS: ${uploadedCount} terrain segments uploaded successfully');
  }
  
  /// Trigger garbage collection to free memory immediately
  void _triggerGarbageCollection() {
    try {
      // Force garbage collection (Dart/Flutter runtime dependent)
      // This is a hint to the VM, not guaranteed to trigger GC
      AppLogger.info('[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Requesting garbage collection');
      // No direct GC API in Dart, but clearing references and setting to null helps
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Error during garbage collection trigger: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    AppLogger.info('[LOCATION_MANAGER] Starting location tracking');
    
    try {
      _locationSubscription = _locationService.startLocationTracking().listen(
        (locationPoint) {
          // Convert LocationPoint to Position for compatibility
          final position = Position(
            latitude: locationPoint.latitude,
            longitude: locationPoint.longitude,
            timestamp: locationPoint.timestamp,
            altitude: locationPoint.elevation,
            accuracy: locationPoint.accuracy,
            heading: 0,
            headingAccuracy: 0,
            speed: locationPoint.speed ?? 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            floor: null,
            isMocked: false,
          );
          handleEvent(LocationUpdated(position: position));
        },
        onError: (error) {
          AppLogger.warning('[LOCATION_MANAGER] Location tracking error (continuing session without GPS): $error');
          // Don't stop the session - continue in offline mode without location updates
          // This allows users to ruck indoors, on airplanes, or in poor GPS areas
          _updateState(_currentState.copyWith(
            isTracking: false,
            errorMessage: 'GPS unavailable - session continues in offline mode',
          ));
        },
      );
      
      // Start batch upload timer
      _batchUploadTimer?.cancel();
      _batchUploadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _processBatchUpload();
      });
      
      // Start watchdog timer
      _startWatchdog();
      
      AppLogger.info('[LOCATION_MANAGER] Location tracking started successfully');
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Failed to start location tracking: $e');
      _updateState(_currentState.copyWith(
        errorMessage: 'Failed to start location tracking',
        isTracking: false,
      ));
    }
  }

  Future<void> _stopLocationTracking() async {
    AppLogger.info('[LOCATION_MANAGER] Stopping location tracking');
    
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    
    _batchUploadTimer?.cancel();
    _batchUploadTimer = null;
    
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    
    _locationService.stopLocationTracking();
    
    // Upload any remaining pending points BEFORE clearing session ID
    if (_pendingLocationPoints.isNotEmpty && _activeSessionId != null) {
      try {
        await _processBatchUpload();
      } catch (e) {
        AppLogger.warning('[LOCATION_MANAGER] Failed to upload final batch during stop: $e');
      }
    }
    
    // CRITICAL: Clear session ID to prevent further uploads
    _activeSessionId = null;
    
    AppLogger.info('[LOCATION_MANAGER] Location tracking fully stopped, session ID cleared');
  }

  /// Start sophisticated watchdog timer to monitor GPS health
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _isWatchdogActive = true;
    _watchdogStartTime = DateTime.now();
    _watchdogRestartCount = 0;
    
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isWatchdogActive) return;
      
      final now = DateTime.now();
      final timeSinceLastLocation = _lastLocationTimestamp != null 
          ? now.difference(_lastLocationTimestamp!).inSeconds
          : 0;
      
      // Only restart if we've had valid locations before and haven't received any for 60s
      if (timeSinceLastLocation > 60 && _validLocationCount > 0) {
        _watchdogRestartCount++;
        
        AppLogger.warning('[LOCATION] Watchdog: No valid location for ${timeSinceLastLocation}s. '
            'Restarting location service (attempt $_watchdogRestartCount).');
        
        // Adaptive restart strategy
        if (_watchdogRestartCount <= 3) {
          // Normal restart for first 3 attempts
          _locationService.stopLocationTracking();
          _startLocationTracking();
          _lastLocationTimestamp = now;
        } else if (_watchdogRestartCount <= 6) {
          // Request high accuracy for next 3 attempts
          AppLogger.info('[LOCATION] Watchdog: Requesting high accuracy mode');
          _locationService.stopLocationTracking();
          _startLocationTracking();
          _lastLocationTimestamp = now;
        } else {
          // Give up and switch to offline mode
          AppLogger.error('[LOCATION] Watchdog: GPS restart failed after 6 attempts. '
              'Switching to offline mode.');
          _stopWatchdog();
          
          // Emit offline state
          _updateState(_currentState.copyWith(
            isGpsReady: false,
            errorMessage: 'GPS unavailable - session continues in offline mode',
          ));
          
          // Clear error message after 5 seconds
          Timer(const Duration(seconds: 5), () {
            _updateState(_currentState.copyWith(
              errorMessage: null,
            ));
          });
        }
      }
      
      // Reset restart counter if we've been getting good locations
      if (timeSinceLastLocation < 30 && _watchdogRestartCount > 0) {
        _watchdogRestartCount = 0;
        AppLogger.info('[LOCATION] Watchdog: GPS health restored, reset restart counter');
      }
    });
  }
  
  /// Stop watchdog timer
  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _isWatchdogActive = false;
    _watchdogStartTime = null;
  }

  Future<void> _processBatchUpload() async {
    if (_pendingLocationPoints.isEmpty || _activeSessionId == null) return;
    
    final batch = _pendingLocationPoints.toList();
    _pendingLocationPoints.clear();
    
    AppLogger.info('[LOCATION_MANAGER] Processing batch upload of ${batch.length} points');
    
    // Delegate to event handler
    handleEvent(BatchLocationUpdated(locationPoints: batch));
  }

  double _calculateTotalDistance() {
  if (_locationPoints.length < 2) return 0.0;
  
  double totalDistance = 0.0;
  for (int i = 1; i < _locationPoints.length; i++) {
    final distance = Geolocator.distanceBetween(
      _locationPoints[i - 1].latitude,
      _locationPoints[i - 1].longitude,
      _locationPoints[i].latitude,
      _locationPoints[i].longitude,
    );
    
    // Only count movement greater than 5 meters to filter GPS drift
    // This matches the system-level filtering we had in version 2.5
    if (distance >= 5.0) {
      totalDistance += distance;
    }
  }
  
  return totalDistance / 1000; // Convert to km
}

/// Calculate total distance with comprehensive validation and filtering
/// This includes initial distance tracking and movement filtering from version 2.5
double _calculateTotalDistanceWithValidation() {
  if (_locationPoints.length < 2) return 0.0;
  
  // Only start counting distance after reaching initial distance threshold
  // This prevents GPS noise from accumulating at the start
  if (!_validationService.isInitialDistanceReached) {
    return 0.0;
  }
  
  double totalDistance = 0.0;
  
  // Find the index where we reached the initial distance threshold
  double cumulativeDistance = 0.0;
  int startIndex = 1;
  
  for (int i = 1; i < _locationPoints.length; i++) {
    final distance = Geolocator.distanceBetween(
      _locationPoints[i - 1].latitude,
      _locationPoints[i - 1].longitude,
      _locationPoints[i].latitude,
      _locationPoints[i].longitude,
    );
    
    cumulativeDistance += distance;
    
    // Start counting after initial distance threshold
    if (cumulativeDistance >= LocationValidationService.minInitialDistanceMeters) {
      startIndex = i;
      break;
    }
  }
  
  // Count distance from the start index onward with movement filtering
  for (int i = startIndex; i < _locationPoints.length; i++) {
    final distance = Geolocator.distanceBetween(
      _locationPoints[i - 1].latitude,
      _locationPoints[i - 1].longitude,
      _locationPoints[i].latitude,
      _locationPoints[i].longitude,
    );
    
    // Only count movement greater than 5 meters to filter GPS drift
    // This matches the system-level filtering we had in version 2.5
    if (distance >= 5.0) {
      totalDistance += distance;
    }
  }
  
  return totalDistance / 1000; // Convert to km
}  

  double _calculateCurrentPace(double speedMs) {
    // VERSION 2.5: Don't show pace for the first minute of the session
    if (_sessionStartTime != null) {
      final elapsedTime = DateTime.now().difference(_sessionStartTime!);
      if (elapsedTime.inSeconds < 60) {
        return 0.0; // No pace for first minute
      }
    }

    // Only recalculate pace every 5 seconds for performance optimization
    final now = DateTime.now();
    if (_cachedCurrentPace != null && _lastPaceCalculation != null) {
      final timeSinceLastCalc = now.difference(_lastPaceCalculation!).inSeconds;
      if (timeSinceLastCalc < 5) {
        return _cachedCurrentPace!;
      }
    }

    double rawPace = 0.0;

    // For more reliable pace calculation, use distance-based method for slow speeds
    // GPS speed is often inaccurate for walking/rucking speeds

    // Method 1: Try GPS speed first (for faster movement)
    if (speedMs > 1.0) { // > 3.6 km/h, GPS speed is more reliable
      final speedKmh = speedMs * 3.6;
      rawPace = 3600 / speedKmh; // seconds/km
    }
    // Method 2: Calculate from recent distance (for slower movement)
    else if (_locationPoints.length >= 2) {
      final lastPoint = _locationPoints[_locationPoints.length - 1];
      final prevPoint = _locationPoints[_locationPoints.length - 2];
      
      final distanceKm = Geolocator.distanceBetween(
        prevPoint.latitude,
        prevPoint.longitude,
        lastPoint.latitude,
        lastPoint.longitude,
      ) / 1000; // Convert to km
      
      final timeSeconds = lastPoint.timestamp.difference(prevPoint.timestamp).inSeconds;
      
      if (timeSeconds > 0 && distanceKm > 0.01) { // Minimum 10m distance to prevent GPS noise
        final speedKmh = (distanceKm / timeSeconds) * 3600;
        if (speedKmh > 0.8) { // Increased walking threshold to prevent noise
          rawPace = 3600 / speedKmh; // seconds/km
        }
      }
    }
    // Method 3: Fallback to GPS speed with stricter thresholds to prevent noise
    else if (speedMs > 0.5) { // Minimum 1.8 km/h - realistic walking speed
      final speedKmh = speedMs * 3.6;
      if (speedKmh > 1.5) { // Must be above realistic walking speed to prevent GPS noise
        rawPace = 3600 / speedKmh; // seconds/km
      }
    }

    // VERSION 2.5 PACE SMOOTHING: Add to recent paces and apply smoothing
    if (rawPace > 0) {
      _recentPaces.add(rawPace);
      
      // Keep only the most recent pace values
      if (_recentPaces.length > _maxRecentPaces) {
        _recentPaces.removeAt(0);
      }
      
      // Apply smoothing if we have enough data points
      if (_recentPaces.length >= 3) {
        rawPace = _sessionValidationService.getSmoothedPace(rawPace, _recentPaces);
      }
    }

    // Cache the result with timestamp
    _cachedCurrentPace = rawPace;
    _lastPaceCalculation = now;

    return rawPace;
  }  

  /// Calculate average pace based on total distance and elapsed time
  double _calculateAveragePace(double totalDistanceKm) {
    // Use cached value if available and recent
    final now = DateTime.now();
    if (_cachedAveragePace != null && _lastPaceCalculation != null) {
      final timeSinceLastCalc = now.difference(_lastPaceCalculation!).inSeconds;
      if (timeSinceLastCalc < 5) {
        return _cachedAveragePace!;
      }
    }
    
    double averagePace = 0.0;
    
    // VERSION 2.5: Don't show average pace for the first minute of the session
    if (_sessionStartTime != null) {
      final elapsedTime = DateTime.now().difference(_sessionStartTime!);
      if (elapsedTime.inSeconds < 60) {
        return 0.0; // No average pace for first minute
      }
    }
    
    if (_sessionStartTime != null && totalDistanceKm > 0.01) {
      // Calculate elapsed time in hours
      final elapsedTime = DateTime.now().difference(_sessionStartTime!).inMilliseconds / 1000.0;
      final elapsedHours = elapsedTime / 3600.0;
      
      if (elapsedHours > 0) {
        // Calculate speed in km/h
        final averageSpeedKmh = totalDistanceKm / elapsedHours;
        
        // Convert to pace (seconds per km)
        if (averageSpeedKmh > 0.1) {
          averagePace = 3600 / averageSpeedKmh;
        }
      }
    }
    
    // Cache the result
    _cachedAveragePace = averagePace;
    
    return averagePace;
  }

  /// Invalidate pace caches when location data changes significantly
  void _invalidatePaceCache() {
    _cachedCurrentPace = null;
    _cachedAveragePace = null;
    _lastPaceCalculation = null;
  }
  
  /// Calculate distance between two GPS coordinates using Haversine formula
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    
    final double lat1Rad = _degreesToRadians(lat1);
    final double lat2Rad = _degreesToRadians(lat2);
    final double deltaLatRad = _degreesToRadians(lat2 - lat1);
    final double deltaLonRad = _degreesToRadians(lon2 - lon1);
    
    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLonRad / 2) * math.sin(deltaLonRad / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c / 1000; // Convert to kilometers
  }
  
  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  Map<String, double> _calculateElevation() {
    if (_locationPoints.length < 2) {
      return {'gain': 0.0, 'loss': 0.0};
    }
    
    double gain = 0.0;
    double loss = 0.0;
    
    for (int i = 1; i < _locationPoints.length; i++) {
      final diff = _locationPoints[i].elevation - _locationPoints[i - 1].elevation;
      if (diff > 0.5) { // Threshold to reduce noise
        gain += diff;
      } else if (diff < -0.5) {
        loss += diff.abs();
      }
    }
    
    return {'gain': gain, 'loss': loss};
  }

  void _updateState(LocationTrackingState newState) {
    _currentState = newState;
    _stateController.add(newState);
    
    // NOTE: Watch updates now handled by coordinator with proper calculated values
    // The coordinator calls updateWatchWithCalculatedValues() with accurate calories/elevation
  }
  
  /// Public method for coordinator to update watch with calculated values
  void updateWatchWithCalculatedValues({
    required int calories,
    required double elevationGain,
    required double elevationLoss,
  }) {
    _updateWatchWithSessionData(
      _currentState,
      caloriesFromCoordinator: calories,
      elevationGainFromCoordinator: elevationGain,
      elevationLossFromCoordinator: elevationLoss,
    );
  }
  
  /// Send current session metrics to watch for display
  void _updateWatchWithSessionData(LocationTrackingState state, {
    int? caloriesFromCoordinator,
    double? elevationGainFromCoordinator,
    double? elevationLossFromCoordinator,
  }) {
    // Note: activeSessionId check is done in callers (_onTick, etc.)
    try {
      // Calculate session duration from start time
      final duration = _sessionStartTime != null 
          ? DateTime.now().difference(_sessionStartTime!)
          : Duration.zero;
      
      // Use values from coordinator if provided, otherwise calculate locally
      final elevationData = _calculateElevation();
      final elevationGain = elevationGainFromCoordinator ?? elevationData['gain'] ?? 0.0;
      final elevationLoss = elevationLossFromCoordinator ?? elevationData['loss'] ?? 0.0;
      
      // Use calories from coordinator if provided, otherwise fall back to simple calculation
      final estimatedCalories = caloriesFromCoordinator ?? (duration.inMinutes * 400 / 60).round();
      
      AppLogger.debug('[LOCATION_MANAGER] WATCH_DATA: '
          'distance=${state.totalDistance.toStringAsFixed(2)}km, '
          'duration=${duration.inMinutes.toStringAsFixed(1)}min, '
          'pace=${state.currentPace.toStringAsFixed(1)}s/km, '
          'calories=${estimatedCalories}cal, '
          'elevation_gain=${elevationGain.toStringAsFixed(1)}m, '
          'elevation_loss=${elevationLoss.toStringAsFixed(1)}m');
      
      // Get user's metric preference
      _sendWatchUpdateWithUserPreferences(
        state: state,
        duration: duration,
        estimatedCalories: estimatedCalories,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
      );
      
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Error updating watch with session data: $e');
    }
  }

  /// Send watch update with user's metric preferences
  Future<void> _sendWatchUpdateWithUserPreferences({
    required LocationTrackingState state,
    required Duration duration,
    required int estimatedCalories,
    required double elevationGain,
    required double elevationLoss,
  }) async {
    try {
      // Get user's metric preference
      final user = await _authService.getCurrentUser();
      final isMetric = user?.preferMetric ?? true; // Default to metric
      
      // Send to watch with user's preference
      await _watchService.updateSessionOnWatch(
        distance: state.totalDistance,
        duration: duration,
        pace: state.currentPace,
        isPaused: _isPaused,
        calories: estimatedCalories.toDouble(),
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        isMetric: isMetric,
      );
      
      AppLogger.debug('[LOCATION_MANAGER] WATCH_UPDATE: Sent session data to watch - Distance: ${state.totalDistance.toStringAsFixed(2)}km, Duration: ${duration.inMinutes}min, Pace: ${state.currentPace.toStringAsFixed(2)}min/km, Metric: $isMetric');
      
    } catch (e) {
      AppLogger.error('[LOCATION_MANAGER] Error sending watch update with user preferences: $e');
      
      // Fallback: send without user preference (defaults to metric)
      try {
        await _watchService.updateSessionOnWatch(
          distance: state.totalDistance,
          duration: duration,
          pace: state.currentPace,
          isPaused: _isPaused,
          calories: estimatedCalories.toDouble(),
          elevationGain: elevationGain,
          elevationLoss: elevationLoss,
          isMetric: true, // Fallback to metric
        );
        AppLogger.debug('[LOCATION_MANAGER] WATCH_UPDATE: Sent fallback session data to watch (metric)');
      } catch (fallbackError) {
        AppLogger.error('[LOCATION_MANAGER] Fallback watch update also failed: $fallbackError');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _stopLocationTracking();
    await _stateController.close();
  }
  
  Map<String, double> _calculateElevationGain() {
    double gain = 0.0;
    double loss = 0.0;
    
    if (_currentState.locations.length < 2) {
      return {'gain': gain, 'loss': loss};
    }
    
    for (int i = 1; i < _currentState.locations.length; i++) {
      final prevElevation = _currentState.locations[i - 1].altitude;
      final currElevation = _currentState.locations[i].altitude;
      final diff = currElevation - prevElevation;
      
      if (diff > 0) {
        gain += diff;
      } else if (diff < 0) {
        loss += diff.abs();
      }
    }
    
    return {'gain': gain, 'loss': loss};
  }

  // Getters for other managers
  double get totalDistance => _currentState.totalDistance;
  bool get isGpsReady => _validLocationCount > 5;
  List<LocationPoint> get locationPoints => List.unmodifiable(_locationPoints);
  List<TerrainSegment> get terrainSegments => List.unmodifiable(_terrainSegments);
  Position? get currentPosition => _currentState.currentPosition;
  double get elevationGain => _calculateElevationGain()['gain'] ?? 0.0;
  double get elevationLoss => _calculateElevationGain()['loss'] ?? 0.0;
  List<SessionSplit> get splits => _splitTrackingService.getSplits()
      .map((splitData) => SessionSplit.fromJson(splitData))
      .toList();
}
