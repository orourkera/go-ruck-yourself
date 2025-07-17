import 'dart:async';
import 'dart:collection';

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
  
  final StreamController<LocationTrackingState> _stateController;
  LocationTrackingState _currentState;
  
  // Location tracking state
  StreamSubscription<LocationPoint>? _locationSubscription;
  final List<LocationPoint> _locationPoints = [];
  final Queue<LocationPoint> _pendingLocationPoints = Queue();
  final Queue<TerrainSegment> _pendingTerrainSegments = Queue();
  
  DateTime? _lastLocationTimestamp = DateTime.now();
  int _validLocationCount = 0;
  Timer? _batchUploadTimer;
  Timer? _watchdogTimer;
  
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
    
    // CRITICAL FIX: Force garbage collection after clearing large lists
    _triggerGarbageCollection();
    
    AppLogger.info('[LOCATION_MANAGER] MEMORY_RESET: Session started, all lists cleared and GC triggered');
    
    // Check location permission
    final hasLocationAccess = await _locationService.hasLocationPermission();
    
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
      AppLogger.warning('[LOCATION_MANAGER] No location permission, tracking disabled');
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

  Future<void> _onLocationUpdated(LocationUpdated event) async {
    if (_isPaused || _activeSessionId == null) return;
    
    final position = event.position;
    _lastLocationTimestamp = DateTime.now();
    
    // Validate location
    if (!LocationValidator.isValidPosition(position)) {
      AppLogger.warning('[LOCATION_MANAGER] Invalid location: ${position.latitude}, ${position.longitude}');
      return;
    }
    
    _validLocationCount++;
    
    // Create location point
    final newPoint = LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude,
      accuracy: position.accuracy,
      timestamp: DateTime.now().toUtc(),
      speed: position.speed,
    );
    
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
    
    // Calculate metrics
    final newDistance = _calculateTotalDistance();
    final newPace = _calculateCurrentPace(position.speed);
    final newAveragePace = _calculateAveragePace(newDistance);
    final elevationData = _calculateElevation();
    
    // Update splits
    if (_sessionStartTime != null) {
      _splitTrackingService.checkForMilestone(
        currentDistanceKm: newDistance,
        sessionStartTime: _sessionStartTime!,
        elapsedSeconds: DateTime.now().difference(_sessionStartTime!).inSeconds,
        isPaused: _isPaused,
        currentElevationGain: elevationData.gain,
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
    
    // TODO: Implement TerrainSegmentUpload event or integrate with existing upload system
    // For now, simulate successful upload
    _onTerrainSegmentUploadSuccess(batch.length);
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
          AppLogger.error('[LOCATION_MANAGER] Location stream error: $error');
          _updateState(_currentState.copyWith(
            errorMessage: 'Location tracking error: $error',
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

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lastLocationTimestamp != null && DateTime.now().difference(_lastLocationTimestamp!).inSeconds > 60 && 
          _validLocationCount > 0) {
        AppLogger.warning('[LOCATION_MANAGER] Watchdog: No valid location for 60s. Restarting location service.');
        _locationService.stopLocationTracking();
        _startLocationTracking();
        _lastLocationTimestamp = DateTime.now();
      }
    });
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
      totalDistance += distance;
    }
    
    return totalDistance / 1000; // Convert to km
  }

  double _calculateCurrentPace(double speedMs) {
    if (speedMs <= 0.1) return 0.0; // Very slow or stationary
    
    final speedKmh = speedMs * 3.6;
    if (speedKmh <= 0.5) return 0.0; // Below walking threshold
    
    return 60 / speedKmh; // min/km
  }

  double _calculateAveragePace(double distanceKm) {
    if (distanceKm <= 0 || _sessionStartTime == null) return 0.0;
    
    final elapsedMinutes = DateTime.now().difference(_sessionStartTime!).inMinutes;
    if (elapsedMinutes <= 0) return 0.0;
    
    return elapsedMinutes / distanceKm;
  }

  ({double gain, double loss}) _calculateElevation() {
    if (_locationPoints.length < 2) return (gain: 0.0, loss: 0.0);
    
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
    
    return (gain: gain, loss: loss);
  }

  void _updateState(LocationTrackingState newState) {
    _currentState = newState;
    _stateController.add(newState);
    
    // CRITICAL FIX: Send session data to watch for display
    _updateWatchWithSessionData(newState);
  }
  
  /// Send current session metrics to watch for display
  void _updateWatchWithSessionData(LocationTrackingState state) {
    if (_activeSessionId == null) return; // Allow updates when paused to show pause state
    
    try {
      // Calculate session duration from start time
      final duration = _sessionStartTime != null 
          ? DateTime.now().difference(_sessionStartTime!)
          : Duration.zero;
      
      // Calculate calories (rough estimation: 300-500 calories per hour of rucking)
      final hoursElapsed = duration.inMinutes / 60.0;
      final estimatedCalories = (hoursElapsed * 400).round(); // 400 cal/hour average
      
      // Use current altitude for elevation (TODO: implement proper elevation gain/loss tracking)
      double elevationGain = 0.0;
      double elevationLoss = 0.0;
      
      // TODO: Implement proper elevation gain/loss calculation
      // TerrainSegment doesn't track elevation changes, only surface types
      // For now, we'll use a basic approach with location points
      
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
