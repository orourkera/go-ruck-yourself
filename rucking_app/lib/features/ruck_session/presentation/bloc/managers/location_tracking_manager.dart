import 'dart:async';
import 'dart:collection';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/api_client.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/utils/location_validator.dart';
import '../../../../../core/models/location_point.dart';
import '../../../domain/services/split_tracking_service.dart';
import '../../../../../core/services/terrain_tracker.dart';
import '../../../../../core/models/terrain_segment.dart';
import '../events/session_events.dart';
import '../models/manager_states.dart';
import 'session_manager.dart';

/// Manages location tracking and GPS-related operations
class LocationTrackingManager implements SessionManager {
  final LocationService _locationService;
  final SplitTrackingService _splitTrackingService;
  final TerrainTracker _terrainTracker;
  final ApiClient _apiClient;
  
  final StreamController<LocationTrackingState> _stateController;
  LocationTrackingState _currentState;
  
  // Location tracking state
  StreamSubscription<LocationPoint>? _locationSubscription;
  final List<LocationPoint> _locationPoints = [];
  final Queue<LocationPoint> _pendingLocationPoints = Queue();
  
  DateTime _lastLocationTimestamp = DateTime.now();
  int _validLocationCount = 0;
  Timer? _batchUploadTimer;
  Timer? _watchdogTimer;
  
  // Session info from lifecycle manager
  String? _activeSessionId;
  DateTime? _sessionStartTime;
  bool _isPaused = false;
  
  // List of captured terrain segments for current session
  final List<TerrainSegment> _terrainSegments = [];

  LocationTrackingManager({
    required LocationService locationService,
    required SplitTrackingService splitTrackingService,
    required TerrainTracker terrainTracker,
    required ApiClient apiClient,
  })  : _locationService = locationService,
        _splitTrackingService = splitTrackingService,
        _terrainTracker = terrainTracker,
        _apiClient = apiClient,
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
    }
  }

  Future<void> _onSessionStarted(SessionStartRequested event) async {
    _activeSessionId = event.sessionId ?? const Uuid().v4();
    _sessionStartTime = DateTime.now();
    _isPaused = false;
    
    // Reset state
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();
    _validLocationCount = 0;
    
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
    
    _activeSessionId = null;
    _sessionStartTime = null;
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();
    
    _updateState(const LocationTrackingState());
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    _isPaused = true;
    _locationSubscription?.pause();
    
    AppLogger.info('[LOCATION_MANAGER] Location tracking paused');
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    _isPaused = false;
    _locationSubscription?.resume();
    
    AppLogger.info('[LOCATION_MANAGER] Location tracking resumed');
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
    
    _locationPoints.add(newPoint);

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
          AppLogger.debug('[LOCATION_MANAGER] Captured terrain segment ${segment.surfaceType} for ${(segment.distanceKm * 1000).toStringAsFixed(1)}m');
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
      AppLogger.info('[LOCATION_MANAGER] Successfully uploaded ${event.locationPoints.length} location points');
    } catch (e) {
      AppLogger.warning('[LOCATION_MANAGER] Failed to upload location batch: $e');
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
    
    // Upload any remaining pending points
    if (_pendingLocationPoints.isNotEmpty && _activeSessionId != null) {
      await _processBatchUpload();
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (DateTime.now().difference(_lastLocationTimestamp).inSeconds > 60 && 
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
}
