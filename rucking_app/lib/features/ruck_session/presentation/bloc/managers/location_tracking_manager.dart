import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:get_it/get_it.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../../core/services/api_client.dart';
import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/watch_service.dart';
import '../../../../../core/services/barometer_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/models/location_point.dart';
import '../../../../../core/models/terrain_segment.dart';
import '../../../../../core/services/app_lifecycle_service.dart';
import '../../../../../core/services/firebase_messaging_service.dart';
import '../../../../../core/services/app_error_handler.dart';
import '../../../domain/models/session_split.dart';
import '../../../domain/services/split_tracking_service.dart';
import '../../../../../core/services/terrain_tracker.dart';
import '../../../../../core/services/storage_service.dart';
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
  final BarometerService _barometerService = BarometerService();
  final LocationValidationService _validationService =
      LocationValidationService();
  final SessionValidationService _sessionValidationService =
      SessionValidationService();

  final StreamController<LocationTrackingState> _stateController;
  LocationTrackingState _currentState;

  // Location tracking state
  StreamSubscription<LocationPoint>? _locationSubscription;
  Stream<LocationPoint>?
      _rawLocationStream; // Resilient reference to the source stream
  final List<LocationPoint> _locationPoints = [];
  final Queue<LocationPoint> _pendingLocationPoints = Queue();

  // Internal state
  LocationPoint? _lastValidLocation;
  LocationPoint? _lastRecordedLocation;
  DateTime? _lastLocationTimestamp;
  DateTime? _lastRawLocationTimestamp;
  int _validLocationCount = 0;
  double _totalDistance = 0.0;
  double _elevationGain = 0.0;
  double _elevationLoss = 0.0;
  Timer? _batchUploadTimer;
  Timer? _watchdogTimer;
  Timer? _journalTimer;
  int _journalLastIndex = 0;

  // Prevent concurrent batch upload processing
  bool _isUploadingBatch = false;

  // Pace calculation optimization
  int _paceTickCounter = 0;
  double? _cachedCurrentPace;
  double? _cachedAveragePace;
  DateTime? _lastPaceCalculation;

  // Pace smoothing (version 2.5 logic)
  final List<double> _recentPaces = [];
  static const int _maxRecentPaces =
      10; // Keep last 10 pace values for smoothing

  // Timer coordination
  bool _isWatchdogActive = false;
  DateTime? _watchdogStartTime;
  int _watchdogRestartCount = 0;

  // Session info from lifecycle manager
  String? _activeSessionId;
  DateTime? _sessionStartTime;
  bool _isPaused = false;
  DateTime? _pausedAt;

  // Cache user preference to avoid repeated API calls
  bool? _cachedIsMetric;

  // Terrain tracking
  final List<TerrainSegment> _terrainSegments = [];

  // CRITICAL FIX: Memory optimization constants - focus on data offloading, not data loss
  static const int _maxLocationPoints =
      10000; // Support 12+ hour sessions (10000 * 5sec = ~14 hours)
  static const int _maxTerrainSegments =
      500; // Keep reasonable amount in memory
  static const int _minLocationPointsToKeep =
      100; // Always keep for real-time calculations

  // Memory pressure thresholds for aggressive data offloading
  static const int _memoryPressureThreshold =
      8000; // Trigger aggressive upload/offload (80% of max)
  static const int _criticalMemoryThreshold =
      9000; // Emergency offload threshold (90% of max)
  static const int _offloadBatchSize =
      200; // Size of batches to offload at once
  // Upload chunk size to keep payloads reasonable
  static const int _uploadChunkSize = 100; // Max points per API upload

  // Track successful uploads to avoid data loss
  int _lastUploadedLocationIndex = 0;
  int _lastUploadedTerrainIndex = 0;

  // CRITICAL FIX: Track cumulative distance to prevent loss during memory management
  double _lastKnownTotalDistance = 0.0;
  int _lastProcessedLocationIndex = 0;

  // Inactivity detection moved to SessionCompletionDetectionService
  // Thresholds
  // Inactivity detection moved to SessionCompletionDetectionService
  // Movement thresholds kept for distance tracking but not for idle detection
  static const double _movementDistanceMetersThreshold = 12.0; // 10–15m
  static const double _movementSpeedThreshold =
      0.1; // m/s (lowered from 0.3 to reduce false idle detection)

  // Distance stall detection and recovery
  DateTime? _lastDistanceIncreaseTime;
  double _lastDistanceValueForStall = 0.0;
  DateTime? _lastStallReportTime;
  DateTime? _lastDistanceRecalcAttempt;
  int _stallRecoveryAttempts = 0;
  static const int _maxStallRecoveryAttempts = 3;

  // Validation rejection analytics and adaptive recovery
  final Map<String, int> _validationRejectCounts = {};
  DateTime? _validationRejectWindowStart;
  DateTime? _lowAccuracyBypassUntil;
  DateTime? _lowAccuracyBypassStarted;

  // Sensor fusion estimation state
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  LocationPoint? _lastEstimatedPosition;
  DateTime? _estimationStartTime;
  double _estimatedDistance = 0.0;
  double _estimatedDirection = 0.0; // in degrees

  // Elevation smoothing and gating with barometric fusion
  double? _filteredAltitude; // EMA-smoothed altitude for gain/loss computation
  DateTime? _lastAltitudeTs;
  static const double _emaAlpha = 0.3; // Smoothing factor for altitude EMA
  static const double _maxVerticalSpeedMs =
      5.0; // Reject spikes faster than 5 m/s
  static const double _verticalAccuracyGateM =
      15.0; // Ignore altitude updates with worse accuracy

  // Barometric altitude fusion state
  StreamSubscription<BarometricReading>? _barometerSubscription;
  double? _lastBarometricAltitude;
  double? _lastBarometricPressure;
  DateTime? _lastBarometricTimestamp;
  bool _isBarometerCalibrated = false;
  int _gpsCalibrationCount = 0;
  static const int _gpsCalibrationSamples =
      3; // Calibrate after 3 good GPS readings
  static const double _fusionWeight =
      0.7; // Weight for GPS vs barometric (0.7 = 70% GPS, 30% barometric)

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
    _pausedAt = null;

    // Reset split tracking so distance milestones start fresh for this session.
    // Without this, the singleton keeps the previous session's last split distance
    // which prevents new 1km/1mi milestones from triggering.
    _splitTrackingService.reset();

    // CRITICAL FIX: Reset state with explicit memory cleanup
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();

    _validLocationCount = 0;
    _lastUploadedLocationIndex = 0; // Reset upload tracking
    _lastValidLocation = null; // Reset validation state
    _lastKnownTotalDistance = 0.0; // Reset cumulative distance
    _lastProcessedLocationIndex =
        -1; // Reset to unprocessed state (CRITICAL FIX)
    // Inactivity detection moved to SessionCompletionDetectionService

    // Cache user metric preference at session start to avoid repeated API calls
    try {
      final user = await _authService.getCurrentUser();
      _cachedIsMetric = user?.preferMetric;
      AppLogger.info(
          '[LOCATION_MANAGER] Cached user metric preference: $_cachedIsMetric (user: ${user?.username})');

      // If user preference is null, don't default - let UI handle it
      if (_cachedIsMetric == null) {
        AppLogger.warning(
            '[LOCATION_MANAGER] User metric preference is null - UI will use system default');
      }
    } catch (e) {
      AppLogger.error(
          '[LOCATION_MANAGER] Failed to cache user preference, will use system default: $e');
      _cachedIsMetric = null; // Don't default to metric - let system handle it
    }

    // Reset pace smoothing state (version 2.5)
    _recentPaces.clear();
    _cachedCurrentPace = null;
    _cachedAveragePace = null;
    _lastPaceCalculation = null;

    // Reset elevation smoothing state
    _filteredAltitude = null;
    _lastAltitudeTs = null;

    // Reset barometric fusion state
    _lastBarometricAltitude = null;
    _lastBarometricTimestamp = null;
    _isBarometerCalibrated = false;
    _gpsCalibrationCount = 0;

    // Reset distance stall detection
    _lastDistanceIncreaseTime = DateTime.now();
    _lastDistanceValueForStall = 0.0;
    _lastStallReportTime = null;

    // Reset comprehensive validation service
    _validationService.reset();
    _sessionValidationService.reset();

    // Memory cleanup completed - Dart's GC will handle memory reclamation automatically

    AppLogger.info(
        '[LOCATION_MANAGER] MEMORY_RESET: Session started, all lists cleared and validation reset');

    // Check location permission - DON'T request if already granted
    bool hasLocationAccess = await _locationService.hasLocationPermission();
    AppLogger.info(
        '[LOCATION_MANAGER] Location permission check: $hasLocationAccess');

    if (!hasLocationAccess) {
      AppLogger.info(
          '[LOCATION_MANAGER] Location permission not granted - session will run in offline mode');
      // Don't request permissions during session start - user should grant them in onboarding/settings
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

      // Start barometric pressure streaming asynchronously to avoid blocking countdown
      _startBarometricStreamingAsync();
    } else {
      AppLogger.info(
          '[LOCATION_MANAGER] No location permission, session continues in offline mode');
    }
  }

  Future<void> _onSessionStopped(SessionStopRequested event) async {
    await _stopLocationTracking();

    // Stop barometric streaming
    await _barometerSubscription?.cancel();
    _barometerSubscription = null;
    await _barometerService.stopStreaming();

    // CRITICAL FIX: Clean up state with explicit memory cleanup
    _activeSessionId = null;
    _sessionStartTime = null;
    _isPaused = false;
    _pausedAt = null;

    // CRITICAL FIX: Reset lists and upload tracking
    _locationPoints.clear();
    _terrainSegments.clear();
    _pendingLocationPoints.clear();

    _lastUploadedLocationIndex = 0;
    _lastUploadedTerrainIndex = 0;
    _validLocationCount = 0;
    _lastLocationTimestamp = null;
    _sessionStartTime = null;
    _isPaused = false;
    // Inactivity detection moved to SessionCompletionDetectionService

    // Clear cached user preference
    _cachedIsMetric = null;

    AppLogger.info(
        '[LOCATION_MANAGER] MEMORY_CLEANUP: Session stopped, all lists cleared and upload tracking reset');

    _updateState(const LocationTrackingState());

    // Clear split tracking after session completion/upload to avoid leaking
    // state into the next session should the user restart quickly.
    _splitTrackingService.reset();

    AppLogger.info(
        '[LOCATION_MANAGER] MEMORY_CLEANUP: Location tracking stopped, all lists cleared and GC triggered');
  }

  Future<void> _onSessionPaused(SessionPaused event) async {
    _isPaused = true;
    _pausedAt = DateTime.now(); // Track when paused for duration calculation
    _locationSubscription?.pause();

    // CRITICAL FIX: Keep watchdog running during pause to detect dead streams
    // Don't stop watchdog completely - just modify its behavior for paused state
    AppLogger.info(
        '[LOCATION_MANAGER] Location tracking paused at ${_pausedAt!.toIso8601String()} - watchdog continues monitoring');

    // Update watch with paused state - duration will now freeze at pause time
    _updateWatchWithSessionData(_currentState);
  }

  Future<void> _onSessionResumed(SessionResumed event) async {
    _isPaused = false;
    _pausedAt = null; // Clear pause timestamp when resuming

    // CRITICAL FIX: Don't just resume subscription - restart location tracking completely
    // If the GPS stream completed while paused, resuming a dead subscription won't work
    if (_locationSubscription != null) {
      AppLogger.info(
          '[LOCATION_MANAGER] Restarting location tracking after resume (potential dead stream)');
      await _stopLocationTracking();
      await _startLocationTracking();
    } else {
      AppLogger.info(
          '[LOCATION_MANAGER] Starting fresh location tracking on resume');
      await _startLocationTracking();
    }

    // Update watch with resumed state - duration will continue incrementing
    _updateWatchWithSessionData(_currentState);

    AppLogger.info(
        '[LOCATION_MANAGER] Location tracking fully restarted after resume');
  }

  /// Handle memory pressure detection by triggering aggressive cleanup
  Future<void> _onMemoryPressureDetected(MemoryPressureDetected event) async {
    AppLogger.error(
        '[LOCATION_MANAGER] MEMORY_PRESSURE: ${event.memoryUsageMb}MB detected, triggering aggressive cleanup');

    // Trigger aggressive memory cleanup
    _manageMemoryPressure();

    // Force upload of pending data
    _triggerAggressiveDataOffload();

    // Memory cleanup completed

    AppLogger.info(
        '[LOCATION_MANAGER] MEMORY_PRESSURE: Aggressive cleanup completed');
  }

  /// Handle timer tick events to update watch display every second
  Future<void> _onTick(Tick event) async {
    if (_activeSessionId == null) return;

    // NOTE: Watch timer updates now handled by coordinator
    // The coordinator aggregates state and updates watch with proper calculated values
    // This tick event is still needed for other timer-based functionality
  }

  Future<void> _onLocationUpdated(LocationUpdated event) async {
    AppLogger.info(
        '[LOCATION_MANAGER] 🎯 PROCESSING location update: sessionId=${_activeSessionId}, paused=$_isPaused');

    if (_isPaused) {
      AppLogger.debug(
          '[LOCATION_MANAGER] ⏸️ SKIPPING location update: session is paused');
      return;
    }
    if (_activeSessionId == null) {
      AppLogger.critical(
          '[LOCATION_MANAGER] ❌ WARNING: No active session ID but received location update');
      AppLogger.critical(
          '[LOCATION_MANAGER] 🔄 Attempting to recover session from coordinator...');
      // CRITICAL FIX: Don't drop the location! Try to recover
      // The session might exist but ID was cleared due to upload error
      return; // For now return, but TODO: implement session recovery
    }

    final position = event.position;
    final now = DateTime.now();

    // CRITICAL: Gap detection for phone death/recovery scenarios
    // If there's been a large time gap since last location, don't calculate distance
    if (_lastLocationTimestamp != null) {
      final timeSinceLastLocation = now.difference(_lastLocationTimestamp!);

      // If more than 5 minutes have passed, this is likely a recovery scenario
      if (timeSinceLastLocation.inMinutes >= 5) {
        AppLogger.warning(
          '[LOCATION_MANAGER] ⚠️ LARGE TIME GAP DETECTED: ${timeSinceLastLocation.inMinutes} minutes since last location. '
          'Likely phone recovery scenario - checking for invalid distance jump.'
        );

        // Check if the distance jump would be unrealistic
        if (_locationPoints.isNotEmpty) {
          final lastPoint = _locationPoints.last;
          final distance = Geolocator.distanceBetween(
            lastPoint.latitude,
            lastPoint.longitude,
            position.latitude,
            position.longitude,
          );

          // Calculate implied speed (m/s)
          final impliedSpeed = distance / timeSinceLastLocation.inSeconds;

          // If implied speed > 50 km/h (13.9 m/s) for running, it's definitely invalid
          // Also check for very large distance jumps (> 1km per minute of gap)
          final minutesGap = timeSinceLastLocation.inMinutes;
          final maxReasonableDistance = minutesGap * 1000.0; // 1km per minute max

          if (impliedSpeed > 13.9 || distance > maxReasonableDistance) {
            AppLogger.error(
              '[LOCATION_MANAGER] 🚨 INVALID RECOVERY DETECTED: Implied speed ${(impliedSpeed * 3.6).toStringAsFixed(1)} km/h '
              'over ${timeSinceLastLocation.inMinutes} minutes. Distance jump: ${(distance / 1000).toStringAsFixed(2)} km. '
              'REJECTING this location update to prevent data corruption.'
            );

            // Update timestamps but don't add the location point
            _lastRawLocationTimestamp = now;

            // Clear the error message after a few seconds
            _updateState(_currentState.copyWith(
              errorMessage: 'Session recovered - GPS reconnecting...',
            ));

            // Schedule clearing the error message
            Future.delayed(const Duration(seconds: 5), () {
              if (_currentState.errorMessage == 'Session recovered - GPS reconnecting...') {
                _updateState(_currentState.copyWith(errorMessage: null));
              }
            });

            return; // Skip this location update entirely
          }

          AppLogger.info(
            '[LOCATION_MANAGER] Gap detected but distance reasonable: ${(distance / 1000).toStringAsFixed(2)} km '
            'at ${(impliedSpeed * 3.6).toStringAsFixed(1)} km/h - accepting location.'
          );
        }
      }
    }

    // Track raw update time separately from valid accepted locations
    _lastRawLocationTimestamp = now;

    AppLogger.debug(
        '[LOCATION_MANAGER] 🎯 Location coordinates: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');

    // Filter altitude with EMA + vertical accuracy + vertical speed gating
    final DateTime nowUtc = DateTime.now().toUtc();
    final double filteredAlt = _filterAltitude(
      rawAltitude: position.altitude,
      altitudeAccuracy: position.altitudeAccuracy,
      timestamp: nowUtc,
    );

    // Create location point using filtered altitude to stabilize elevation gain/loss
    final newPoint = LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: filteredAlt,
      accuracy: position.accuracy,
      timestamp: nowUtc,
      speed: position.speed,
    );

    // Apply LENIENT backend validation before database storage
    if (_shouldAcceptForDatabase(newPoint)) {
      _pendingLocationPoints.add(newPoint);
      AppLogger.info(
          '[LOCATION_MANAGER] ✅ ADDED to database queue: accuracy=${newPoint.accuracy.toStringAsFixed(1)}m, total_pending=${_pendingLocationPoints.length}');
    } else {
      AppLogger.error(
          '[LOCATION_MANAGER] ❌ REJECTED from database queue: extreme GPS error detected');
    }

    // Use comprehensive validation from version 2.5
    final validationResult =
        _validationService.validateLocationPoint(newPoint, _lastValidLocation);

    if (!(validationResult['isValid'] as bool? ?? false)) {
      final String message =
          validationResult['message'] as String? ?? 'Validation failed';
      AppLogger.warning(
          '[LOCATION_MANAGER] Location validation failed: $message');

      // Track rejection analytics in a 5-minute rolling window
      final now = DateTime.now();
      _validationRejectWindowStart ??= now;
      if (now.difference(_validationRejectWindowStart!).inMinutes >= 5) {
        _validationRejectCounts.clear();
        _validationRejectWindowStart = now;
      }
      _validationRejectCounts[message] =
          (_validationRejectCounts[message] ?? 0) + 1;

      // If rejections are due to prolonged low GPS accuracy while we appear to be getting raw updates,
      // enable a short-lived bypass to avoid distance freeze.
      final bool isLowAccuracy =
          message.toLowerCase().contains('low gps accuracy');
      final int timeSinceLastRaw = _lastRawLocationTimestamp != null
          ? now.difference(_lastRawLocationTimestamp!).inSeconds
          : 9999;
      final int timeSinceLastValid = _lastLocationTimestamp != null
          ? now.difference(_lastLocationTimestamp!).inSeconds
          : 9999;
      final bool gpsHealthy = _validLocationCount > 5 && timeSinceLastRaw < 60;
      final bool distanceStalled = _lastDistanceIncreaseTime != null &&
          now.difference(_lastDistanceIncreaseTime!).inSeconds >= 120;
      final bool bypassActive = _lowAccuracyBypassUntil != null &&
          now.isBefore(_lowAccuracyBypassUntil!);

      // Auto-extend bypass window while stall persists, but enforce 10-minute maximum
      if (isLowAccuracy && gpsHealthy && distanceStalled) {
        // Track when bypass first started
        if (_lowAccuracyBypassStarted == null) {
          _lowAccuracyBypassStarted = now;
        }

        // Only extend if we haven't exceeded 10-minute maximum
        final bypassDuration = now.difference(_lowAccuracyBypassStarted!);
        if (bypassDuration.inMinutes < 10) {
          _lowAccuracyBypassUntil = now.add(const Duration(minutes: 2));
          await AppErrorHandler.handleError(
            'low_accuracy_bypass_enabled',
            'Temporarily bypassing low accuracy validation to prevent distance stall',
            context: {
              'session_id': _activeSessionId ?? 'unknown',
              'rejects_in_window': _validationRejectCounts[message] ?? 1,
              'time_since_last_raw_s': timeSinceLastRaw,
              'time_since_last_valid_s': timeSinceLastValid,
              'total_distance_km': _lastKnownTotalDistance.toStringAsFixed(3),
              'bypass_duration_minutes': bypassDuration.inMinutes,
            },
            severity: ErrorSeverity.warning,
          );
          AppLogger.warning(
              '[LOCATION_MANAGER] LOW_ACCURACY_BYPASS extended for 2 minutes (${bypassDuration.inMinutes}min total)');
        } else {
          AppLogger.warning(
              '[LOCATION_MANAGER] LOW_ACCURACY_BYPASS maximum duration (10min) reached, stopping bypass');
          _lowAccuracyBypassUntil = null;
          _lowAccuracyBypassStarted = null;
        }
      }

      // If bypass is active and this is a low-accuracy rejection, accept the point to keep distance monotonic
      if (isLowAccuracy &&
          (_lowAccuracyBypassUntil != null) &&
          now.isBefore(_lowAccuracyBypassUntil!)) {
        AppLogger.info(
            '[LOCATION_MANAGER] Accepting low-accuracy point due to temporary bypass');
      } else {
        // ENHANCED fallback for older phones - more aggressive acceptance to prevent distance stalls
        bool acceptedFallback = false;
        try {
          if (_lastValidLocation != null) {
            final double dt = now
                .difference(_lastValidLocation!.timestamp)
                .inSeconds
                .toDouble();
            final double dMeters = _haversineDistance(
                  _lastValidLocation!.latitude,
                  _lastValidLocation!.longitude,
                  newPoint.latitude,
                  newPoint.longitude,
                ) *
                1000.0;
            final double speedMs = dt > 0 ? dMeters / dt : 0.0;

            // More generous fallback criteria for distance continuity
            final bool timeOk = dt >= 1.0 && dt <= 60.0; // 1-60 seconds apart
            final bool distanceOk =
                dMeters <= 50.0; // Up to 50m movement (increased from 30m)
            final bool speedOk =
                speedMs <= 6.0; // Up to 6 m/s (~13 mph) for brief spurts
            final bool emergencyAcceptance = dt >= 10.0 &&
                dMeters <= 100.0 &&
                speedMs <= 10.0; // Emergency for very delayed points

            if ((timeOk && distanceOk && speedOk) || emergencyAcceptance) {
              AppLogger.info(
                  '[LOCATION_MANAGER] Fallback-accepting point for continuity (dt=${dt.toStringAsFixed(1)}s, d=${dMeters.toStringAsFixed(1)}m, v=${speedMs.toStringAsFixed(2)}m/s)${emergencyAcceptance ? ' [EMERGENCY]' : ''}');
              acceptedFallback = true;
            }
          }
        } catch (_) {}

        if (!acceptedFallback) {
          // CRITICAL: Even if we reject the point for distance calculation,
          // we should still check for distance stall recovery every 30 seconds
          final now = DateTime.now();
          final timeSinceLastDistance = _lastDistanceIncreaseTime != null
              ? now.difference(_lastDistanceIncreaseTime!)
              : Duration.zero;

          if (timeSinceLastDistance.inSeconds >= 30 &&
              _locationPoints.isNotEmpty) {
            // Try to recalculate distance from existing points to detect if we're stuck
            try {
              final recalcDistance = _calculateTotalDistance();
              if (recalcDistance != _currentState.totalDistance) {
                AppLogger.info(
                    '[LOCATION_MANAGER] VALIDATION_BYPASS: Distance recalc shows ${recalcDistance.toStringAsFixed(3)}km vs displayed ${_currentState.totalDistance.toStringAsFixed(3)}km - updating UI');
                _updateState(
                    _currentState.copyWith(totalDistance: recalcDistance));
              }
            } catch (e) {
              AppLogger.debug(
                  '[LOCATION_MANAGER] VALIDATION_BYPASS: Distance recalc failed: $e');
            }
          }

          // CRITICAL FIX: Don't return early - still add point for distance tracking
          // Log the rejection but continue processing for distance calculation
          AppLogger.warning(
              '[LOCATION_MANAGER] Point validation failed: ${validationResult['message']} - ${position.accuracy.toStringAsFixed(1)}m accuracy - keeping for distance tracking');

          // Still add to location points for distance calculation even if validation failed
          // This ensures distance continues to accumulate
          _locationPoints.add(newPoint);
          _lastLocationTimestamp = DateTime.now();

          // Note: We don't update _lastValidLocation or _validLocationCount for failed points
          // This preserves validation integrity while still tracking distance
        }
      }
    } else {
      // Validation passed - update valid location tracking
      _validLocationCount++;
      _lastValidLocation = newPoint;

      // Add to location points
      _locationPoints.add(newPoint);
      // Update last valid location timestamp only after accepting the point
      _lastLocationTimestamp = DateTime.now();
    }

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

            // Terrain segments stored locally (upload functionality removed)

            // Manage terrain segments with proper upload tracking
            if (_terrainSegments.length > _maxTerrainSegments &&
                _lastUploadedTerrainIndex > 50) {
              _trimUploadedTerrainSegments();
            }
          }
        }
      } catch (e) {
        AppLogger.error(
            '[LOCATION_MANAGER] Error capturing terrain segment: $e');
      }
    }
    // Calculate metrics with comprehensive distance filtering
    final newDistance = _calculateTotalDistance();
    final newPace = _calculateCurrentPace(position.speed ?? 0.0);
    final newAveragePace = _calculateAveragePace(newDistance);

    AppLogger.info(
        '[LOCATION_MANAGER] 📏 DISTANCE UPDATE: ${newDistance.toStringAsFixed(3)}km (was ${_currentState.totalDistance.toStringAsFixed(3)}km), points=${_locationPoints.length}');
    // Movement detection moved to SessionCompletionDetectionService
    // This eliminates duplicate notifications and improves accuracy

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

    // CRITICAL FIX: Calculate elevation from location points directly, don't double-accumulate
    final elevationData = _calculateElevation();
    final newElevationGain = elevationData['gain'] ?? 0.0;
    final newElevationLoss = elevationData['loss'] ?? 0.0;

    // Update the private elevation tracking variables
    _elevationGain = newElevationGain;
    _elevationLoss = newElevationLoss;

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

    // Note: Already added to pending batch before validation above

    // Convert to Position list for state
    final positions = _locationPoints
        .map((lp) => Position(
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
            ))
        .toList();

    // Keep last-known total distance in sync for inactivity checks
    _lastKnownTotalDistance = newDistance;

    _updateState(_currentState.copyWith(
      locations: positions,
      currentPosition: position,
      totalDistance: newDistance,
      currentPace: newPace,
      averagePace: newAveragePace,
      currentSpeed: position.speed,
      altitude: filteredAlt,
      isGpsReady: _validLocationCount > 5, // GPS ready state from version 2.5
      elevationGain: newElevationGain,
      elevationLoss: newElevationLoss,
    ));

    // Detect distance stall while GPS appears healthy and user is moving
    try {
      final now = DateTime.now();
      final timeSinceLastRaw = _lastRawLocationTimestamp != null
          ? now.difference(_lastRawLocationTimestamp!).inSeconds
          : 9999;
      final timeSinceLastValid = _lastLocationTimestamp != null
          ? now.difference(_lastLocationTimestamp!).inSeconds
          : 9999;
      final bool gpsHealthy = _validLocationCount > 5 &&
          timeSinceLastRaw < 60 &&
          timeSinceLastValid < 60;
      final bool appearsMoving =
          (position.speed ?? 0.0) >= _movementSpeedThreshold;

      // CRITICAL FIX: Make distance increase detection more sensitive to prevent false stall detection
      // During recovery from stationary periods, even 1 meter of movement should count
      if (newDistance > _lastDistanceValueForStall + 0.001) {
        // >1 meter (was 5 meters)
        _lastDistanceIncreaseTime = now;
        _lastDistanceValueForStall = newDistance;
        _stallRecoveryAttempts =
            0; // Reset recovery attempts on successful distance increase
      } else if (gpsHealthy &&
          appearsMoving &&
          _lastDistanceIncreaseTime != null) {
        final stallMins = now.difference(_lastDistanceIncreaseTime!).inMinutes;
        final recentlyReported = _lastStallReportTime != null &&
            now.difference(_lastStallReportTime!).inMinutes < 10;

        // Try emergency recovery after 2 minutes of stall
        if (stallMins >= 2 &&
            _stallRecoveryAttempts < _maxStallRecoveryAttempts) {
          _stallRecoveryAttempts++;
          AppLogger.warning(
              '[LOCATION_MANAGER] DISTANCE_STALL_RECOVERY: Attempting recovery #$_stallRecoveryAttempts after ${stallMins}m stall');

          try {
            // Force full distance recalculation from all points
            _lastProcessedLocationIndex = -1; // Reset to recalculate all
            final recoveredDistance = _calculateTotalDistance();

            if (recoveredDistance > _lastDistanceValueForStall + 0.01) {
              AppLogger.info(
                  '[LOCATION_MANAGER] DISTANCE_STALL_RECOVERY: Successfully recovered distance from ${_lastDistanceValueForStall.toStringAsFixed(3)}km to ${recoveredDistance.toStringAsFixed(3)}km');
              _lastDistanceIncreaseTime = now;
              _lastDistanceValueForStall = recoveredDistance;
              _stallRecoveryAttempts = 0;

              // Update state with recovered distance
              _updateState(
                  _currentState.copyWith(totalDistance: recoveredDistance));
              return; // Exit early, recovery successful
            }
          } catch (e) {
            AppLogger.error(
                '[LOCATION_MANAGER] DISTANCE_STALL_RECOVERY: Recovery attempt failed: $e');
          }
        }

        if (stallMins >= 3 && !recentlyReported) {
          _lastStallReportTime = now;
          // Non-fatal telemetry to Crashlytics/Sentry
          await AppErrorHandler.handleError(
            'distance_stall_detected',
            'No distance increase for ${stallMins}m while GPS healthy (recovery attempts: $_stallRecoveryAttempts)',
            context: {
              'session_id': _activeSessionId ?? 'unknown',
              'total_distance_km': newDistance.toStringAsFixed(3),
              'valid_points': _validLocationCount,
              'points_buffer': _locationPoints.length,
              'time_since_last_raw_s': timeSinceLastRaw,
              'time_since_last_valid_s': timeSinceLastValid,
              'speed_ms': position.speed ?? 0.0,
              'accuracy_m': position.accuracy,
              'recovery_attempts': _stallRecoveryAttempts,
            },
            severity: ErrorSeverity.warning,
          );
          AppLogger.warning(
              '[LOCATION_MANAGER] DISTANCE_STALL: ${stallMins}m without increase while GPS healthy (recovery attempts: $_stallRecoveryAttempts)');
        }
      }
    } catch (e) {
      AppLogger.debug('[LOCATION_MANAGER] Distance stall detection error: $e');
    }
  }

  Future<void> _onBatchLocationUpdated(BatchLocationUpdated event) async {
    if (_activeSessionId == null || _activeSessionId!.startsWith('offline_'))
      return;

    AppLogger.info(
        '[LOCATION_MANAGER] Processing batch of ${event.locationPoints.length} points for upload');

    try {
      await _apiClient.addLocationPoints(
        _activeSessionId!,
        event.locationPoints
            .map<Map<String, dynamic>>((LocationPoint p) => p.toJson())
            .toList(),
      );

      // Track successful upload for memory optimization
      _lastUploadedLocationIndex += event.locationPoints.length;
      AppLogger.info(
          '[LOCATION_MANAGER] Successfully uploaded ${event.locationPoints.length} location points. Total uploaded: $_lastUploadedLocationIndex');

      // Now we can safely trim location points
      _trimUploadedLocationPoints();
      // Prune journal after successful upload
      await _pruneLocationJournal();
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();

      // Check if this is a 404 error indicating orphaned session
      if (errorMessage.contains('404') || errorMessage.contains('not found')) {
        AppLogger.error(
            '[LOCATION_MANAGER] 🚨 ORPHANED SESSION DETECTED: Session $_activeSessionId missing on server');
        AppLogger.error(
            '[LOCATION_MANAGER] Switching to OFFLINE MODE – continuing to record and journal points locally');

        // Continue tracking locally: queue will retry later; journal ensures durability
        _updateState(_currentState.copyWith(
          // Keep isTracking true; surface a non-blocking warning
          errorMessage: 'Server sync issue – tracking offline, will retry',
        ));
        // Also journal immediately to ensure durability during desync
        try {
          await _journalNewPoints(forceAllPending: true);
        } catch (_) {}
        return; // Do not rethrow; avoid stopping tracking
      }

      AppLogger.warning(
          '[LOCATION_MANAGER] Failed to upload location batch: $e');
      // Don't update _lastUploadedLocationIndex on failure - keep points in memory
      // Propagate error so caller can requeue remaining chunks
      rethrow;
    }
  }

  /// CRITICAL FIX: Memory management through data offloading, not data loss
  void _manageMemoryPressure() {
    // Log current state for debugging distance loss
    AppLogger.debug(
        '[LOCATION_MANAGER] MEMORY_CHECK: ${_locationPoints.length} points, uploaded: $_lastUploadedLocationIndex, processed: $_lastProcessedLocationIndex, distance: ${_lastKnownTotalDistance.toStringAsFixed(3)}km');

    // Check if we're approaching memory pressure thresholds
    if (_locationPoints.length >= _memoryPressureThreshold) {
      AppLogger.warning(
          '[LOCATION_MANAGER] MEMORY_PRESSURE: ${_locationPoints.length} location points detected, triggering aggressive offload');
      _triggerAggressiveDataOffload();
    }

    // Only trim after successful uploads to prevent data loss
    if (_locationPoints.length > _maxLocationPoints &&
        _lastUploadedLocationIndex > _minLocationPointsToKeep) {
      AppLogger.info(
          '[LOCATION_MANAGER] MEMORY_PRESSURE: Attempting to trim ${_locationPoints.length} points (uploaded: $_lastUploadedLocationIndex)');
      _trimUploadedLocationPoints();
    }

    // Manage terrain segments with proper upload tracking
    if (_terrainSegments.length > _maxTerrainSegments &&
        _lastUploadedTerrainIndex > 50) {
      _trimUploadedTerrainSegments();
    } else if (_terrainSegments.length > _maxTerrainSegments) {
      // If no uploads have occurred yet, trim segments to prevent memory leak
      _trimUploadedTerrainSegments();
    }
  }

  /// Trigger aggressive data offloading to database/API to free memory
  void _triggerAggressiveDataOffload() {
    try {
      // Calculate how many points we can safely offload
      final unuploadedPoints =
          _locationPoints.length - _lastUploadedLocationIndex;

      if (unuploadedPoints > _offloadBatchSize) {
        // Trigger immediate batch upload of older points
        final batchEndIndex = _lastUploadedLocationIndex + _offloadBatchSize;
        final batchToUpload =
            _locationPoints.sublist(_lastUploadedLocationIndex, batchEndIndex);

        AppLogger.info(
            '[LOCATION_MANAGER] MEMORY_PRESSURE: Offloading batch of ${batchToUpload.length} location points');

        // Add to pending upload queue for immediate processing
        _pendingLocationPoints.addAll(batchToUpload);

        // Trigger immediate upload processing
        _processBatchUpload();

        // CRITICAL FIX: Don't mark as uploaded until actual success
        // _lastUploadedLocationIndex will be updated in _onBatchLocationUpdated after successful upload
        AppLogger.debug(
            '[LOCATION_MANAGER] MEMORY_PRESSURE: Queued ${batchToUpload.length} points for upload, not marking as uploaded until success');
      }

      // Memory cleanup completed - pending upload will free memory on success
    } catch (e) {
      AppLogger.error(
          '[LOCATION_MANAGER] Error during aggressive data offload: $e');
    }
  }

  /// Safely trim location points only after successful database uploads
  void _trimUploadedLocationPoints() {
    final pointsToRemove = _locationPoints.length - _maxLocationPoints;
    if (pointsToRemove > 0 && _lastUploadedLocationIndex >= pointsToRemove) {
      // Only remove points that have been successfully uploaded
      _locationPoints.removeRange(0, pointsToRemove);
      _lastUploadedLocationIndex -= pointsToRemove;

      // SOPHISTICATED INDEX MANAGEMENT: Robust adjustment after trimming
      final oldProcessedIndex = _lastProcessedLocationIndex;

      // Adjust the processed index based on how many points were removed
      _lastProcessedLocationIndex =
          math.max(-1, _lastProcessedLocationIndex - pointsToRemove);

      // BOUNDARY VALIDATION: Ensure index is within valid range after trimming
      if (_locationPoints.isNotEmpty) {
        if (_lastProcessedLocationIndex >= _locationPoints.length) {
          // Index beyond array bounds - set to last valid index
          _lastProcessedLocationIndex = _locationPoints.length - 1;
          AppLogger.warning(
              '[LOCATION_MANAGER] TRIMMING: Index beyond bounds, adjusted to last valid index: $_lastProcessedLocationIndex');
        } else if (_lastProcessedLocationIndex < -1) {
          // Index too low - reset to unprocessed state
          _lastProcessedLocationIndex = -1;
          AppLogger.warning(
              '[LOCATION_MANAGER] TRIMMING: Index too low, reset to unprocessed state');
        }
      } else {
        // No points remaining - reset index but PRESERVE accumulated distance
        _lastProcessedLocationIndex = -1;
        // DO NOT reset _lastKnownTotalDistance - this must persist across trimming operations
        AppLogger.info(
            '[LOCATION_MANAGER] TRIMMING: No points remaining, reset index but preserved distance: ${_lastKnownTotalDistance.toStringAsFixed(3)}km');
      }

      AppLogger.info(
          '[LOCATION_MANAGER] TRIMMING: Index adjustment: $oldProcessedIndex -> $_lastProcessedLocationIndex (removed $pointsToRemove points)');

      AppLogger.info(
          '[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $pointsToRemove uploaded location points '
          '(${_locationPoints.length} remaining, processed index: $_lastProcessedLocationIndex, distance preserved: ${_lastKnownTotalDistance.toStringAsFixed(3)}km)');

      // Trimming completed
    }
  }

  /// Trim terrain segments only after successful upload (prevent data loss)
  void _trimUploadedTerrainSegments() {
    if (_terrainSegments.length > _maxTerrainSegments &&
        _lastUploadedTerrainIndex > 50) {
      final segmentsToRemove = _terrainSegments.length - _maxTerrainSegments;
      if (_lastUploadedTerrainIndex >= segmentsToRemove) {
        // Only remove segments that have been successfully uploaded
        _terrainSegments.removeRange(0, segmentsToRemove);
        _lastUploadedTerrainIndex -= segmentsToRemove;

        AppLogger.info(
            '[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Safely trimmed $segmentsToRemove uploaded terrain segments (${_terrainSegments.length} remaining)');
        // Trimming completed
      } else {
        AppLogger.warning(
            '[LOCATION_MANAGER] MEMORY_OPTIMIZATION: Cannot trim terrain segments - not enough uploaded segments');
      }
    }
  }

  // Move _attachLocationListener to class level so watchdog can call it
  void _attachLocationListener() {
    if (_rawLocationStream == null) {
      AppLogger.error(
          '[LOCATION_MANAGER] Cannot attach listener - no raw location stream');
      return;
    }

    // Cancel any prior listener before re-attaching
    try {
      _locationSubscription?.cancel();
    } catch (_) {}

    _locationSubscription = _rawLocationStream!.listen(
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
        AppLogger.info(
            '[LOCATION_MANAGER] 📍 GPS UPDATE: lat=${locationPoint.latitude.toStringAsFixed(6)}, lng=${locationPoint.longitude.toStringAsFixed(6)}, acc=${locationPoint.accuracy.toStringAsFixed(1)}m');
        handleEvent(LocationUpdated(position: position));
      },
      onError: (error) {
        AppLogger.warning(
            '[LOCATION_MANAGER] Location stream error – will resubscribe: $error');
        // Keep UI alive in offline mode while we resubscribe
        _updateState(_currentState.copyWith(
          isTracking: false,
          errorMessage: 'GPS unavailable - attempting recovery',
        ));
        // Aggressive backoff and resubscribe to the same broadcast stream
        if (_activeSessionId != null && !_isPaused) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_activeSessionId != null && !_isPaused) {
              AppLogger.info(
                  '[LOCATION_MANAGER] Restarting location service after stream error');
              // Full restart of location service instead of just reattaching listener
              _locationService.stopLocationTracking();
              Future.delayed(const Duration(seconds: 1), () {
                if (_activeSessionId != null && !_isPaused) {
                  _startLocationTracking();
                }
              });
            }
          });
        }
      },
      onDone: () {
        AppLogger.critical(
            '[LOCATION_MANAGER] 🚨 GPS STREAM DIED - attempting restart');
        AppLogger.critical(
            '[LOCATION_MANAGER] Session active: ${_activeSessionId != null}, Paused: $_isPaused');
        if (_activeSessionId != null && !_isPaused) {
          AppLogger.critical(
              '[LOCATION_MANAGER] 🔄 Restarting GPS stream in 1 second...');
          Future.delayed(const Duration(seconds: 1), () {
            if (_activeSessionId != null && !_isPaused) {
              AppLogger.critical(
                  '[LOCATION_MANAGER] 🔄 Executing GPS stream restart...');
              _attachLocationListener();
            }
          });
        } else {
          AppLogger.critical(
              '[LOCATION_MANAGER] 🛑 Not restarting GPS: session=${_activeSessionId != null ? 'active' : 'null'}, paused=$_isPaused');
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _startLocationTracking() async {
    AppLogger.info('[LOCATION_MANAGER] Starting location tracking');

    try {
      // CRITICAL FIX: Always create a fresh stream when starting location tracking
      // Reusing a dead stream was causing location updates to stop after ~15 minutes
      _rawLocationStream = _locationService.startLocationTracking();

      _attachLocationListener();

      // Start batch upload timer
      _batchUploadTimer?.cancel();
      _batchUploadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _processBatchUpload();
      });

      // Start watchdog timer
      _startWatchdog();
      // Start journaling timer (durable on-disk persistence)
      _startLocationJournaling();

      AppLogger.info(
          '[LOCATION_MANAGER] Location tracking started successfully');
    } catch (e) {
      AppLogger.error(
          '[LOCATION_MANAGER] Failed to start location tracking: $e');
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

    // CRITICAL: Clear the stream reference so a fresh one is created on restart
    _rawLocationStream = null;

    _batchUploadTimer?.cancel();
    _batchUploadTimer = null;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _journalTimer?.cancel();
    _journalTimer = null;

    _locationService.stopLocationTracking();

    // Skip final upload if session is already completed to avoid 400 errors
    // The session completion process handles the final data upload
    if (_pendingLocationPoints.isNotEmpty && _activeSessionId != null) {
      AppLogger.info(
          '[LOCATION_MANAGER] Skipping final location upload - session completion handles final data');
      // Just clear the pending points without uploading
      _pendingLocationPoints.clear();
    }

    // CRITICAL: Clear session ID to prevent further uploads
    _activeSessionId = null;

    AppLogger.info(
        '[LOCATION_MANAGER] Location tracking fully stopped, session ID cleared');
  }

  /// Start sophisticated watchdog timer to monitor GPS health
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _isWatchdogActive = true;
    _watchdogStartTime = DateTime.now();
    _watchdogRestartCount = 0;

    // Start with 30 second intervals, then use exponential backoff
    _scheduleNextWatchdogCheck();
  }

  void _scheduleNextWatchdogCheck() {
    if (!_isWatchdogActive) return;

    // Exponential backoff: starts at 30s, maxes out at 5 minutes
    // First 10 attempts: 30s (5 minutes)
    // Next 10 attempts: 60s (10 minutes)
    // Next 20 attempts: 120s (40 minutes)
    // Remaining attempts: 300s (5 minutes each) for ~2+ hours
    int intervalSeconds;
    if (_watchdogRestartCount < 10) {
      intervalSeconds = 30; // First 5 minutes - aggressive
    } else if (_watchdogRestartCount < 20) {
      intervalSeconds = 60; // Next 10 minutes - moderate
    } else if (_watchdogRestartCount < 40) {
      intervalSeconds = 120; // Next 40 minutes - relaxed
    } else {
      intervalSeconds = 300; // Remaining 2+ hours - very relaxed
    }

    _watchdogTimer = Timer(Duration(seconds: intervalSeconds), () async {
      if (!_isWatchdogActive) return;

      final now = DateTime.now();
      // Distinguish raw updates from accepted valid points
      final timeSinceLastRaw = _lastRawLocationTimestamp != null
          ? now.difference(_lastRawLocationTimestamp!).inSeconds
          : 9999;
      final timeSinceLastValid = _lastLocationTimestamp != null
          ? now.difference(_lastLocationTimestamp!).inSeconds
          : 9999;

      // Case 1: No raw updates coming in – restart the GPS stack (but only if not paused)
      if (timeSinceLastRaw > 60 && _validLocationCount > 0) {
        if (_isPaused) {
          // During pause, just log the detection but don't restart - resume will handle it
          AppLogger.warning(
              '[LOCATION] Watchdog: Stream appears dead during pause (${timeSinceLastRaw}s). '
              'Will restart on resume.');
          return; // Exit early, don't increment restart count during pause
        }

        _watchdogRestartCount++;

        AppLogger.warning(
            '[LOCATION] Watchdog: No raw location update for ${timeSinceLastRaw}s. '
            'Reattaching listener (attempt $_watchdogRestartCount).');

        // Extended adaptive restart strategy - try for up to 30 minutes
        if (_watchdogRestartCount <= 10) {
          // Normal restart for first 10 attempts (5 minutes)
          AppLogger.info(
              '[LOCATION] Watchdog: GPS reattach attempt $_watchdogRestartCount/60 (normal mode)');
          // CRITICAL FIX: Don't stop the entire location service! Just reattach the listener
          _attachLocationListener();
          _lastRawLocationTimestamp = now;
        } else if (_watchdogRestartCount <= 50) {
          // High accuracy mode for next 20 attempts (10 minutes)
          AppLogger.info(
              '[LOCATION] Watchdog: GPS reattach attempt $_watchdogRestartCount/60 (high accuracy mode)');
          // CRITICAL FIX: Just reattach listener, don't kill the service
          _attachLocationListener();
          _lastRawLocationTimestamp = now;
        } else if (_watchdogRestartCount <= 100) {
          // Emergency mode - try full restart (50-100 attempts = next ~2 hours)
          final elapsedHours = now.difference(_watchdogStartTime!).inHours;
          AppLogger.warning(
              '[LOCATION] Watchdog: GPS FULL restart attempt $_watchdogRestartCount (${elapsedHours}h elapsed)');
          // Only do full restart in emergency mode after many failures
          _locationService.stopLocationTracking();
          await Future.delayed(const Duration(seconds: 3));
          await _startLocationTracking();
          _lastRawLocationTimestamp = now;
        } else {
          // After 3+ hours, continue trying but log as critical
          final elapsedHours = now.difference(_watchdogStartTime!).inHours;
          AppLogger.critical(
              '[LOCATION] Watchdog: GPS still dead after ${elapsedHours} hours, attempt $_watchdogRestartCount');

          // Keep trying with full restart
          _locationService.stopLocationTracking();
          await Future.delayed(const Duration(seconds: 5));
          await _startLocationTracking();
          _lastRawLocationTimestamp = now;

          // Emit offline state
          _updateState(_currentState.copyWith(
            isGpsReady: false,
            errorMessage:
                'GPS unavailable after 30 minutes - estimating position from sensors',
          ));

          // Clear error message after 10 seconds
          Timer(const Duration(seconds: 10), () {
            _updateState(_currentState.copyWith(
              errorMessage: null,
            ));
          });
        }
      } else if (timeSinceLastValid > 90 &&
          timeSinceLastRaw < 30 &&
          _validLocationCount > 0) {
        // Case 2: Raw updates are flowing but validation rejects everything – try a soft recovery
        if (_isPaused) {
          AppLogger.info(
              '[LOCATION] Watchdog: Validation stall detected during pause - normal during pause state');
          return;
        }

        _watchdogRestartCount++;
        AppLogger.warning(
            '[LOCATION] Watchdog: Validation stall – raw ok but no valid point for ${timeSinceLastValid}s. '
            'Relaxing validation thresholds (attempt $_watchdogRestartCount).');
        // CRITICAL FIX: Don't restart GPS when validation is the problem!
        // The GPS is working, validation is just too strict
        // Just mark the timestamp to prevent repeated triggers
        _lastRawLocationTimestamp = now;
        _lastLocationTimestamp = now; // Reset validation timestamp too
      }

      // Reset restart counter if we've been getting good locations
      if (timeSinceLastRaw < 30 &&
          timeSinceLastValid < 30 &&
          _watchdogRestartCount > 0) {
        _watchdogRestartCount = 0;
        AppLogger.info(
            '[LOCATION] Watchdog: GPS health restored, reset restart counter');
      }

      // Inactivity detection removed - now handled by SessionCompletionDetectionService
      // This eliminates duplicate notifications and improves accuracy

      // Schedule next check with exponential backoff
      _scheduleNextWatchdogCheck();
    });
  }

  /// Stop watchdog timer
  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _isWatchdogActive = false;
    _watchdogStartTime = null;
  }

  /// Start a lightweight journaling timer to persist new points to disk every 2 seconds
  void _startLocationJournaling() {
    _journalTimer?.cancel();
    _journalLastIndex = _locationPoints.length; // initialize baseline
    _journalTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await _journalNewPoints();
      } catch (e) {
        AppLogger.debug(
            '[LOCATION_MANAGER] Journal flush failed (non-fatal): $e');
      }
    });
  }

  /// Append newly collected points to on-disk journal for crash resilience
  Future<void> _journalNewPoints({bool forceAllPending = false}) async {
    if (_activeSessionId == null || _locationPoints.isEmpty) return;
    final startIndex = forceAllPending ? 0 : _journalLastIndex;
    if (startIndex >= _locationPoints.length) return;

    final newPoints =
        _locationPoints.sublist(startIndex).map((p) => p.toJson()).toList();
    try {
      final storage = GetIt.I<StorageService>();
      final key = 'location_journal_${_activeSessionId}';
      final existing = await storage.getObject(key) ?? <String, dynamic>{};
      final list = (existing['points'] as List<dynamic>? ?? <dynamic>[]);
      list.addAll(newPoints);
      existing['points'] = list;
      existing['last_updated'] = DateTime.now().toIso8601String();
      await storage.setObject(key, existing);

      _journalLastIndex = _locationPoints.length; // advance watermark

      // Prevent unbounded growth: soft cap at 50k points; prune oldest 10k if uploaded allows
      if (list.length > 50000 && _lastUploadedLocationIndex > 10000) {
        final toDrop = 10000;
        existing['points'] = list.sublist(toDrop);
        await storage.setObject(key, existing);
      }
    } catch (e) {
      AppLogger.debug(
          '[LOCATION_MANAGER] Journal append skipped (storage unavailable): $e');
    }
  }

  /// Prune journal entries that have been successfully uploaded
  Future<void> _pruneLocationJournal() async {
    if (_activeSessionId == null) return;
    try {
      final storage = GetIt.I<StorageService>();
      final key = 'location_journal_${_activeSessionId}';
      final existing = await storage.getObject(key);
      if (existing == null) return;
      final list = (existing['points'] as List<dynamic>? ?? <dynamic>[]);
      // If journal is longer than uploaded count, keep tail beyond uploaded points
      if (_lastUploadedLocationIndex > 0 &&
          list.isNotEmpty &&
          list.length > _lastUploadedLocationIndex) {
        existing['points'] = list.sublist(_lastUploadedLocationIndex);
        await storage.setObject(key, existing);
      }
    } catch (e) {
      AppLogger.debug('[LOCATION_MANAGER] Journal prune skipped: $e');
    }
  }

  Future<void> _processBatchUpload() async {
    // Avoid overlapping uploads
    if (_isUploadingBatch) {
      AppLogger.debug(
          '[LOCATION_MANAGER] Batch upload already in progress; skipping trigger');
      return;
    }
    if (_pendingLocationPoints.isEmpty) {
      AppLogger.debug(
          '[LOCATION_MANAGER] 📤 No pending points for batch upload');
      return;
    }
    if (_activeSessionId == null) {
      AppLogger.critical(
          '[LOCATION_MANAGER] 🚨 CRITICAL: No active session ID but GPS tracking is running!');
      AppLogger.critical(
          '[LOCATION_MANAGER] 📤 Cannot upload ${_pendingLocationPoints.length} pending points');
      AppLogger.critical(
          '[LOCATION_MANAGER] 🔧 This suggests session ID was inappropriately cleared during upload errors');

      // TODO: Add recovery logic here - maybe try to get active session from backend
      // For now, just log the critical state
      return;
    }

    AppLogger.info(
        '[LOCATION_MANAGER] 📤 STARTING batch upload: ${_pendingLocationPoints.length} points queued for session ${_activeSessionId}');

    _isUploadingBatch = true;
    List<LocationPoint> batch = const [];
    int index = 0;
    try {
      // Snapshot pending points and clear queue for this cycle
      batch = _pendingLocationPoints.toList();
      _pendingLocationPoints.clear();

      AppLogger.info(
          '[LOCATION_MANAGER] Processing batch upload of ${batch.length} points');

      // Sequentially upload in chunks
      index = 0;
      while (index < batch.length) {
        // Session may have been cleared during processing
        if (_activeSessionId == null) {
          AppLogger.warning(
              '[LOCATION_MANAGER] Active session ended during batch processing; aborting remaining uploads');
          break;
        }

        final end = math.min(index + _uploadChunkSize, batch.length);
        final chunk = batch.sublist(index, end);
        final chunkNumber = (index ~/ _uploadChunkSize) + 1;
        final totalChunks =
            ((batch.length + _uploadChunkSize - 1) / _uploadChunkSize).floor();
        AppLogger.debug(
            '[LOCATION_MANAGER] Uploading chunk $chunkNumber/$totalChunks (${chunk.length} pts)');

        // Delegate to existing handler for actual upload + error handling
        try {
          await handleEvent(BatchLocationUpdated(locationPoints: chunk));
          index = end;
        } catch (uploadError) {
          // NEVER clear _activeSessionId on upload errors - this kills GPS tracking!
          // The session is still active on the device regardless of backend state
          AppLogger.critical(
              '[LOCATION_MANAGER] Failed to upload chunk $chunkNumber: $uploadError',
              exception: uploadError);

          // Re-queue ALL failed chunks for retry - backend issues shouldn't stop local tracking
          _pendingLocationPoints.addAll(chunk);

          // Log the specific error type for debugging
          final errorMsg = uploadError.toString().toLowerCase();
          if (errorMsg.contains('404') ||
              errorMsg.contains('session not found')) {
            AppLogger.critical(
                '[LOCATION_MANAGER] 🚨 Backend session 404 error - keeping GPS alive and retrying',
                exception: uploadError);
            // DO NOT clear session ID or stop tracking!
          }

          // Continue to next chunk instead of rethrowing
          // This prevents cascading failures from blocking all uploads
          continue;
        }
      }
    } catch (e) {
      AppLogger.warning('[LOCATION_MANAGER] Batch upload processing error: $e');
      // Requeue any remaining points that were not processed yet
      if (index < batch.length) {
        try {
          final remaining = batch.sublist(index);
          _pendingLocationPoints.addAll(remaining);
          AppLogger.warning(
              '[LOCATION_MANAGER] Re-queued ${remaining.length} unprocessed points after error');
        } catch (_) {}
      }
    } finally {
      _isUploadingBatch = false;
    }
  }

  double _calculateTotalDistance() {
    // SOPHISTICATED DISTANCE TRACKING: Cumulative calculation with memory management
    if (_locationPoints.length < 2) {
      // CRITICAL FIX: If frontend validation has blocked too many points,
      // try to calculate distance from pending points that went to database
      if (_pendingLocationPoints.isNotEmpty &&
          _pendingLocationPoints.length >= 2) {
        AppLogger.info(
            '[LOCATION_MANAGER] FRONTEND_RECOVERY: Frontend has insufficient points (${_locationPoints.length}), attempting distance calc from ${_pendingLocationPoints.length} pending points');
        try {
          return _calculateDistanceFromPendingPoints();
        } catch (e) {
          AppLogger.warning(
              '[LOCATION_MANAGER] FRONTEND_RECOVERY: Failed to calculate from pending points: $e');
        }
      }
      return _lastKnownTotalDistance;
    }

    // Start from the last known total distance (in meters)
    double totalDistance = _lastKnownTotalDistance * 1000;

    // ROBUST INDEX MANAGEMENT: Handle edge cases after trimming
    int startIndex;

    // If we've never processed any points, start from index 1
    if (_lastProcessedLocationIndex < 0) {
      startIndex = 1;
    } else {
      // Start from the next unprocessed point
      startIndex = _lastProcessedLocationIndex + 1;
    }

    // BOUNDARY VALIDATION: Ensure indices are within valid range
    if (startIndex >= _locationPoints.length) {
      // All points already processed
      AppLogger.debug(
          '[LOCATION_MANAGER] DISTANCE_CALC: All points processed, returning cached distance: ${_lastKnownTotalDistance.toStringAsFixed(3)}km');
      return _lastKnownTotalDistance;
    }

    // Ensure we have at least 2 points and a valid starting index
    if (_locationPoints.length < 2) {
      AppLogger.debug(
          '[LOCATION_MANAGER] DISTANCE_CALC: Insufficient points (${_locationPoints.length}), returning cached distance: ${_lastKnownTotalDistance.toStringAsFixed(3)}km');
      return _lastKnownTotalDistance;
    }

    // Ensure we have a valid previous point for the first calculation
    if (startIndex <= 0) {
      startIndex = 1;
    }

    // Final boundary check after adjustments
    if (startIndex >= _locationPoints.length) {
      AppLogger.debug(
          '[LOCATION_MANAGER] DISTANCE_CALC: Start index beyond bounds after adjustment, returning cached distance: ${_lastKnownTotalDistance.toStringAsFixed(3)}km');
      return _lastKnownTotalDistance;
    }

    // INCREMENTAL DISTANCE CALCULATION: Only process new points
    for (int i = startIndex; i < _locationPoints.length; i++) {
      // ROBUST BOUNDARY CHECKING: Verify both current and previous points exist
      if (i <= 0 ||
          i >= _locationPoints.length ||
          (i - 1) < 0 ||
          (i - 1) >= _locationPoints.length) {
        AppLogger.warning(
            '[LOCATION_MANAGER] DISTANCE_CALC: Invalid indices i=$i, prev=${i - 1}, length=${_locationPoints.length}, skipping');
        continue;
      }

      try {
        final prevPoint = _locationPoints[i - 1];
        final currPoint = _locationPoints[i];

        final distance = Geolocator.distanceBetween(
          prevPoint.latitude,
          prevPoint.longitude,
          currPoint.latitude,
          currPoint.longitude,
        );

        // GPS NOISE FILTERING: Only add realistic distances with bounded speed
        final timeDiffSeconds =
            currPoint.timestamp.difference(prevPoint.timestamp).inSeconds;
        final bool hasMinimumTime =
            timeDiffSeconds >= 1; // At least 1 second apart
        final bool isRealisticDistance = distance < 100; // Less than 100m jump
        final bool boundedSpeed = timeDiffSeconds > 0
            ? (distance / timeDiffSeconds) <=
                4.5 // <= 4.5 m/s (~10 mph) upper bound for rucking
            : false;

        // Accept segment if it is realistic and timed, OR implied speed is within bounds
        if ((isRealisticDistance && hasMinimumTime) || boundedSpeed) {
          totalDistance += distance;
          AppLogger.debug(
              '[LOCATION_MANAGER] DISTANCE_CALC: Added ${distance.toStringAsFixed(2)}m segment (${i - 1} -> $i)');
        } else {
          AppLogger.warning(
              '[LOCATION_MANAGER] DISTANCE_CALC: Filtered unrealistic segment: ${distance.toStringAsFixed(2)}m in ${timeDiffSeconds}s');
        }
      } catch (e) {
        AppLogger.error(
            '[LOCATION_MANAGER] DISTANCE_CALC: Error processing segment $i: $e');
        continue;
      }
    }

    // UPDATE TRACKING STATE: Mark all points as processed
    _lastProcessedLocationIndex = _locationPoints.length - 1;

    // Convert to km and enforce monotonic non-decreasing total distance
    double candidateKm = totalDistance / 1000;
    if (candidateKm < _lastKnownTotalDistance) {
      candidateKm = _lastKnownTotalDistance;
    }
    // If distance did not increase despite new points, run a recovery recompute occasionally
    final bool noIncrease = (candidateKm <= _lastKnownTotalDistance + 1e-6);
    final now = DateTime.now();
    if (noIncrease &&
        _locationPoints.length > (_lastProcessedLocationIndex + 1) &&
        (_lastDistanceRecalcAttempt == null ||
            now.difference(_lastDistanceRecalcAttempt!).inSeconds >= 60)) {
      _lastDistanceRecalcAttempt = now;
      try {
        final double recomputedKm =
            _recomputeTotalDistanceFromPoints(maxLookback: 2000);
        if (recomputedKm > candidateKm) {
          AppLogger.warning(
              '[LOCATION_MANAGER] DISTANCE_RECOVERY: Recomputed distance=${recomputedKm.toStringAsFixed(3)}km (prev candidate=${candidateKm.toStringAsFixed(3)}km)');
          // Sentry/SaaS telemetry for successful recovery adoption
          try {
            AppErrorHandler.handleError(
              'distance_recovery_adopted',
              'Adopted recomputed distance after stall',
              context: {
                'prev_candidate_km': candidateKm.toStringAsFixed(3),
                'recomputed_km': recomputedKm.toStringAsFixed(3),
                'points': _locationPoints.length,
                'last_processed_index': _lastProcessedLocationIndex,
              },
              severity: ErrorSeverity.info,
            );
          } catch (_) {}
          candidateKm = recomputedKm;
        } else {
          // Telemetry when recovery ran but did not improve distance
          try {
            AppErrorHandler.handleError(
              'distance_recovery_no_change',
              'Recompute did not increase distance',
              context: {
                'candidate_km': candidateKm.toStringAsFixed(3),
                'recomputed_km': recomputedKm.toStringAsFixed(3),
                'points': _locationPoints.length,
                'last_processed_index': _lastProcessedLocationIndex,
              },
              severity: ErrorSeverity.warning,
            );
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.debug(
            '[LOCATION_MANAGER] DISTANCE_RECOVERY: Recompute failed: $e');
        try {
          AppErrorHandler.handleError(
            'distance_recovery_failed',
            e,
            context: {
              'candidate_km': candidateKm.toStringAsFixed(3),
              'points': _locationPoints.length,
              'last_processed_index': _lastProcessedLocationIndex,
            },
            severity: ErrorSeverity.error,
          );
        } catch (_) {}
      }
    }

    _lastKnownTotalDistance = candidateKm;

    AppLogger.info(
        '[LOCATION_MANAGER] SOPHISTICATED_DISTANCE: Updated to ${_lastKnownTotalDistance.toStringAsFixed(3)}km, '
        'processed ${_locationPoints.length} points (start: $startIndex, last: $_lastProcessedLocationIndex)');

    return _lastKnownTotalDistance;
  }

  /// Lenient validation for database storage - only reject extreme GPS errors
  bool _shouldAcceptForDatabase(LocationPoint newPoint) {
    // CRITICAL FIX: EXTREMELY lenient validation - accept almost everything for database storage
    // The database should capture the raw GPS data, validation happens separately

    // 1. Only reject points with catastrophically impossible accuracy (>5000m suggests complete GPS failure)
    if (newPoint.accuracy > 5000.0) {
      AppLogger.warning(
          '[LOCATION_MANAGER] Rejecting point for database: catastrophic GPS accuracy ${newPoint.accuracy}m');
      return false;
    }

    // 2. Only reject completely impossible coordinates (outside Earth)
    if (newPoint.latitude.abs() > 90.0 || newPoint.longitude.abs() > 180.0) {
      AppLogger.warning(
          '[LOCATION_MANAGER] Rejecting point for database: impossible coordinates ${newPoint.latitude}, ${newPoint.longitude}');
      return false;
    }

    // 3. Only reject if we're clearly in airplane/teleportation mode (>50km jumps in <60 seconds)
    if (_lastValidLocation != null) {
      final distance = _haversineDistance(
            _lastValidLocation!.latitude,
            _lastValidLocation!.longitude,
            newPoint.latitude,
            newPoint.longitude,
          ) *
          1000.0; // Convert to meters

      final timeDiff = newPoint.timestamp
          .difference(_lastValidLocation!.timestamp)
          .inSeconds;

      // Only reject extreme teleportation (50km in <60 seconds = 3000 km/h)
      if (distance > 50000.0 && timeDiff < 60) {
        AppLogger.warning(
            '[LOCATION_MANAGER] Rejecting point for database: teleportation detected ${distance.toStringAsFixed(0)}m in ${timeDiff}s');
        return false;
      }
    }

    // 4. Only reject points clearly in space or underground mines
    if (newPoint.elevation < -1000.0 || newPoint.elevation > 15000.0) {
      AppLogger.warning(
          '[LOCATION_MANAGER] Rejecting point for database: impossible elevation ${newPoint.elevation}m');
      return false;
    }

    // ACCEPT EVERYTHING ELSE - let the backend and validation service handle quality
    // Database storage should be separate from validation
    return true;
  }

  /// Calculate distance from pending points (database queue) as emergency fallback
  double _calculateDistanceFromPendingPoints() {
    if (_pendingLocationPoints.length < 2) return _lastKnownTotalDistance;

    double totalMeters = 0.0;
    final points = _pendingLocationPoints.toList();

    AppLogger.info(
        '[LOCATION_MANAGER] EMERGENCY_DISTANCE: Calculating from ${points.length} pending points');

    for (int i = 1; i < points.length; i++) {
      try {
        final prevPoint = points[i - 1];
        final currPoint = points[i];

        final distance = Geolocator.distanceBetween(
          prevPoint.latitude,
          prevPoint.longitude,
          currPoint.latitude,
          currPoint.longitude,
        );

        // Apply basic filtering - more lenient than frontend validation
        final timeDiffSeconds =
            currPoint.timestamp.difference(prevPoint.timestamp).inSeconds;
        final isReasonable =
            distance < 200 && timeDiffSeconds >= 1; // More lenient 200m vs 100m

        if (isReasonable) {
          totalMeters += distance;
        }
      } catch (e) {
        AppLogger.debug(
            '[LOCATION_MANAGER] EMERGENCY_DISTANCE: Error processing segment $i: $e');
        continue;
      }
    }

    final distanceKm = totalMeters / 1000.0;
    AppLogger.info(
        '[LOCATION_MANAGER] EMERGENCY_DISTANCE: Calculated ${distanceKm.toStringAsFixed(3)}km from pending points');

    return math.max(
        distanceKm, _lastKnownTotalDistance); // Ensure non-decreasing
  }

  // Recompute distance from recent points to recover from index drift or over-filtering
  double _recomputeTotalDistanceFromPoints({int maxLookback = 2000}) {
    if (_locationPoints.length < 2) return _lastKnownTotalDistance;
    final int start = (_locationPoints.length > maxLookback)
        ? _locationPoints.length - maxLookback
        : 1;
    double meters = (_lastKnownTotalDistance * 1000);
    // If recomputing from a shorter window, drop baseline to avoid double-counting only when starting beyond index 1
    if (start > 1) {
      meters = 0.0;
    }
    int prevIndex = start - 1;
    for (int i = start; i < _locationPoints.length; i++) {
      final prev = _locationPoints[prevIndex];
      final curr = _locationPoints[i];
      final d = Geolocator.distanceBetween(
          prev.latitude, prev.longitude, curr.latitude, curr.longitude);
      final dt = curr.timestamp.difference(prev.timestamp).inSeconds;
      final bool realistic = d < 120; // slightly relaxed threshold for recovery
      final bool timed = dt >= 1;
      final bool bounded = dt > 0 ? (d / dt) <= 5.0 : false;
      if ((realistic && timed) || bounded) {
        meters += d;
        prevIndex = i;
      }
    }
    return meters / 1000.0;
  }

  double _calculateCurrentPace(double speedMs) {
    // DEBUG: Log pace calculation inputs
    AppLogger.debug(
        '[PACE DEBUG] _calculateCurrentPace called with speedMs: $speedMs');

    // VERSION 2.5: Don't show pace for the first minute of the session
    if (_sessionStartTime != null) {
      final elapsedTime = DateTime.now().difference(_sessionStartTime!);
      AppLogger.debug(
          '[PACE DEBUG] Session elapsed time: ${elapsedTime.inSeconds} seconds');
      if (elapsedTime.inSeconds < 60) {
        AppLogger.debug(
            '[PACE DEBUG] Returning 0.0 - session less than 60 seconds old');
        return 0.0; // No pace for first minute
      }
    }

    // Only recalculate pace every 5 seconds for performance optimization
    final now = DateTime.now();
    if (_cachedCurrentPace != null && _lastPaceCalculation != null) {
      final timeSinceLastCalc = now.difference(_lastPaceCalculation!).inSeconds;
      if (timeSinceLastCalc < 5) {
        AppLogger.debug(
            '[PACE DEBUG] Returning cached pace: $_cachedCurrentPace');
        return _cachedCurrentPace!;
      }
    }

    double rawPace = 0.0;

    // VERSION 2.7: Multi-point pace calculation with GPS noise filtering
    if (_locationPoints.length >= 5) {
      // Use last 5 points for more stable pace calculation
      final recentPoints = _locationPoints.sublist(_locationPoints.length - 5);
      double totalDistance = 0.0;
      int totalTime = 0;

      AppLogger.debug('[PACE DEBUG] Using last 5 points for pace calculation');

      for (int i = 1; i < recentPoints.length; i++) {
        final prevPoint = recentPoints[i - 1];
        final currentPoint = recentPoints[i];

        final segmentDistance = _haversineDistance(
          prevPoint.latitude,
          prevPoint.longitude,
          currentPoint.latitude,
          currentPoint.longitude,
        );
        final segmentTime =
            currentPoint.timestamp.difference(prevPoint.timestamp).inSeconds;

        // Only include segments with meaningful movement (>5 meters)
        if (segmentDistance > 0.005 && segmentTime > 0) {
          // 0.005km = 5 meters
          totalDistance += segmentDistance;
          totalTime += segmentTime;
        }
      }

      AppLogger.debug(
          '[PACE DEBUG] Total distance over 5 points: ${totalDistance}km');
      AppLogger.debug(
          '[PACE DEBUG] Total time over 5 points: ${totalTime} seconds');

      if (totalTime > 0 && totalDistance > 0.01) {
        // Require at least 10 meters total
        final paceMinutesPerKm = (totalTime / 60) / totalDistance;
        rawPace = paceMinutesPerKm * 60; // Convert to seconds per km

        AppLogger.debug(
            '[PACE DEBUG] Multi-point paceMinutesPerKm: $paceMinutesPerKm');
        AppLogger.debug(
            '[PACE DEBUG] Multi-point rawPace: $rawPace seconds/km');

        // SANITY CHECK: Cap pace at reasonable values
        if (rawPace > 3600) {
          // More than 60 minutes per km is unrealistic
          AppLogger.debug(
              '[PACE DEBUG] Pace too slow ($rawPace), capping at 3600 seconds/km');
          rawPace = 3600;
        } else if (rawPace < 120) {
          // Less than 2 minutes per km is unrealistic for rucking
          AppLogger.debug(
              '[PACE DEBUG] Pace too fast ($rawPace), capping at 120 seconds/km');
          rawPace = 120;
        }
      } else {
        AppLogger.debug(
            '[PACE DEBUG] Insufficient meaningful movement, using fallback method');
        // Fallback to average pace if recent movement is too small
        rawPace = _calculateAveragePace(_lastKnownTotalDistance);
      }
    } else if (_locationPoints.length >= 2) {
      // Fallback: Original 2-point method for early session
      final lastPoint = _locationPoints.last;
      final secondLastPoint = _locationPoints[_locationPoints.length - 2];

      final distance = _haversineDistance(
        secondLastPoint.latitude,
        secondLastPoint.longitude,
        lastPoint.latitude,
        lastPoint.longitude,
      );

      final timeDiff =
          lastPoint.timestamp.difference(secondLastPoint.timestamp).inSeconds;

      AppLogger.debug(
          '[PACE DEBUG] Fallback 2-point method: distance=${distance}km, time=${timeDiff}s');

      if (timeDiff > 0 && distance > 0.005) {
        // Require at least 5 meters
        final paceMinutesPerKm = (timeDiff / 60) / (distance / 1000);
        rawPace = paceMinutesPerKm * 60;

        // Apply stricter caps for 2-point method (more noise-prone)
        if (rawPace > 2400 || rawPace < 180) {
          // 40 min/km max, 3 min/km min
          AppLogger.debug(
              '[PACE DEBUG] 2-point pace out of range ($rawPace), using average pace');
          rawPace = _calculateAveragePace(_lastKnownTotalDistance);
        }
      } else {
        AppLogger.debug(
            '[PACE DEBUG] Invalid 2-point data, using average pace');
        rawPace = _calculateAveragePace(_lastKnownTotalDistance);
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
        rawPace =
            _sessionValidationService.getSmoothedPace(rawPace, _recentPaces);
      }
    }

    // Cache the result with timestamp
    _cachedCurrentPace = rawPace;
    _lastPaceCalculation = now;

    AppLogger.debug('[PACE DEBUG] Final calculated pace: $rawPace seconds/km');
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
      final elapsedTime =
          DateTime.now().difference(_sessionStartTime!).inMilliseconds / 1000.0;
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
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    final double lat1Rad = _degreesToRadians(lat1);
    final double lat2Rad = _degreesToRadians(lat2);
    final double deltaLatRad = _degreesToRadians(lat2 - lat1);
    final double deltaLonRad = _degreesToRadians(lon2 - lon1);

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);

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

    // Threshold and gating to reduce noise accumulation
    const double elevationThreshold =
        1.5; // Reduced from 2.0m - more sensitive to elevation changes
    const double minHorizontalMeters =
        0.3; // 30cm - captures walking but filters standing still
    const double maxStepMeters =
        25.0; // clamp per-step vertical change to avoid rare spikes

    // Hysteresis accumulator: build up changes until they exceed threshold, then commit
    double pending =
        0.0; // signed accumulator (positive for up, negative for down)
    int dir = 0; // 1 = up, -1 = down, 0 = neutral

    for (int i = 1; i < _locationPoints.length; i++) {
      final prev = _locationPoints[i - 1];
      final curr = _locationPoints[i];

      // Ignore vertical noise if there's no meaningful horizontal movement
      final double hMeters = _haversineDistance(
            prev.latitude,
            prev.longitude,
            curr.latitude,
            curr.longitude,
          ) *
          1000.0; // Convert km to meters!

      // Clamp unrealistic single-step vertical changes (additional guard besides vertical speed gate)
      double step = (curr.elevation - prev.elevation);

      // DEBUG: Log elevation values to understand the issue
      if (i <= 10 || i % 10 == 0) {
        // Log first 10 and then every 10th
        AppLogger.debug(
            '[ELEVATION DEBUG] Point $i: prev=${prev.elevation.toStringAsFixed(2)}m, curr=${curr.elevation.toStringAsFixed(2)}m, step=${step.toStringAsFixed(2)}m, hMeters=${hMeters.toStringAsFixed(2)}m, pending=${pending.toStringAsFixed(2)}m, dir=$dir');
        if (hMeters < minHorizontalMeters) {
          AppLogger.debug(
              '[ELEVATION DEBUG] Point $i SKIPPED - horizontal movement ${hMeters.toStringAsFixed(2)}m < ${minHorizontalMeters}m minimum');
        }
      }

      if (hMeters < minHorizontalMeters) {
        continue;
      }

      if (step > maxStepMeters) step = maxStepMeters;
      if (step < -maxStepMeters) step = -maxStepMeters;
      if (step == 0.0) {
        continue;
      }

      // Maintain direction-aware hysteresis accumulator
      final int stepDir = step > 0 ? 1 : -1;
      if (dir == 0 || dir == stepDir) {
        pending += step; // continue accumulating in same direction
        dir = stepDir;
      } else {
        // Direction changed; reset accumulator to the current step
        pending = step;
        dir = stepDir;
      }

      // If accumulated change exceeds threshold, commit the full amount (common approach on Garmin/Strava-like devices)
      if (dir > 0 && pending >= elevationThreshold) {
        gain += pending;
        pending = 0.0;
        dir = 0;
      } else if (dir < 0 && -pending >= elevationThreshold) {
        loss += (-pending);
        pending = 0.0;
        dir = 0;
      }
    }

    print(
        '[ELEVATION] Calculated from ${_locationPoints.length} points: gain=${gain.toStringAsFixed(1)}m, loss=${loss.toStringAsFixed(1)}m');

    // Log sample of elevation values if we have points
    if (_locationPoints.isNotEmpty) {
      final firstElev = _locationPoints.first.elevation;
      final lastElev = _locationPoints.last.elevation;
      AppLogger.debug(
          '[ELEVATION] First point elevation: ${firstElev.toStringAsFixed(1)}m, Last point elevation: ${lastElev.toStringAsFixed(1)}m');
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
    int? steps,
  }) {
    _updateWatchWithSessionData(
      _currentState,
      caloriesFromCoordinator: calories,
      elevationGainFromCoordinator: elevationGain,
      elevationLossFromCoordinator: elevationLoss,
      stepsFromCoordinator: steps,
    );
  }

  /// Send current session metrics to watch for display
  void _updateWatchWithSessionData(
    LocationTrackingState state, {
    int? caloriesFromCoordinator,
    double? elevationGainFromCoordinator,
    double? elevationLossFromCoordinator,
    int? stepsFromCoordinator,
  }) {
    // Note: activeSessionId check is done in callers (_onTick, etc.)
    try {
      // Calculate session duration from start time, but freeze when paused
      Duration duration = Duration.zero;
      if (_sessionStartTime != null) {
        if (_isPaused && _pausedAt != null) {
          // When paused, use duration up to pause time only
          duration = _pausedAt!.difference(_sessionStartTime!);
        } else {
          // When active, use current time
          duration = DateTime.now().difference(_sessionStartTime!);
        }
      }

      // Use values from coordinator if provided, otherwise calculate locally
      final elevationData = _calculateElevation();
      final elevationGain =
          elevationGainFromCoordinator ?? elevationData['gain'] ?? 0.0;
      final elevationLoss =
          elevationLossFromCoordinator ?? elevationData['loss'] ?? 0.0;

      // Use calories from coordinator if provided, otherwise fall back to simple calculation
      final estimatedCalories =
          caloriesFromCoordinator ?? (duration.inMinutes * 400 / 60).round();

      AppLogger.debug('[LOCATION_MANAGER] WATCH_DATA: '
          'distance=${state.totalDistance.toStringAsFixed(2)}km, '
          'duration=${duration.inMinutes.toStringAsFixed(1)}min, '
          'pace=${state.currentPace.toStringAsFixed(1)}s/km, '
          'calories=${estimatedCalories}cal, '
          'elevation_gain=${elevationGain.toStringAsFixed(1)}m, '
          'elevation_loss=${elevationLoss.toStringAsFixed(1)}m'
          '${stepsFromCoordinator != null ? ", steps=$stepsFromCoordinator" : ""}');
      if (stepsFromCoordinator != null) {
        AppLogger.info(
            '[STEPS LIVE] [LOCATION_MANAGER] Including steps in watch update: $stepsFromCoordinator');
      }

      // Get user's metric preference
      _sendWatchUpdateWithUserPreferences(
        state: state,
        duration: duration,
        estimatedCalories: estimatedCalories,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        steps: stepsFromCoordinator,
      );
    } catch (e) {
      AppLogger.error(
          '[LOCATION_MANAGER] Error updating watch with session data: $e');
    }
  }

  /// Send watch update with user's metric preferences
  Future<void> _sendWatchUpdateWithUserPreferences({
    required LocationTrackingState state,
    required Duration duration,
    required int estimatedCalories,
    required double elevationGain,
    required double elevationLoss,
    int? steps,
  }) async {
    try {
      // Use cached metric preference to avoid API call on every location update
      // If preference is null, watchOS will use system locale default (US=imperial, most others=metric)
      final isMetric = _cachedIsMetric ?? true; // System default fallback

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
        steps: steps,
      );

      AppLogger.debug(
          '[LOCATION_MANAGER] WATCH_UPDATE: Sent session data to watch - Distance: ${state.totalDistance.toStringAsFixed(2)}km, Duration: ${duration.inMinutes}min, Pace: ${state.currentPace.toStringAsFixed(2)}min/km, Metric: $isMetric');
    } catch (e) {
      AppLogger.error(
          '[LOCATION_MANAGER] Error sending watch update with cached preferences: $e');

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
          steps: steps,
        );
        AppLogger.debug(
            '[LOCATION_MANAGER] WATCH_UPDATE: Sent fallback session data to watch (metric)');
      } catch (fallbackError) {
        AppLogger.error(
            '[LOCATION_MANAGER] Fallback watch update also failed: $fallbackError');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _stopLocationTracking();

    // Clean up barometer resources
    await _barometerSubscription?.cancel();
    _barometerSubscription = null;
    await _barometerService.stopStreaming();
    _barometerService.dispose();

    await _stateController.close();
  }

  @override
  Future<void> checkForCrashedSession() async {
    // No-op: LocationTrackingManager doesn't handle session recovery
    // Session recovery is handled by SessionLifecycleManager
    return;
  }

  @override
  Future<void> clearCrashRecoveryData() async {
    // No-op: LocationTrackingManager doesn't handle crash recovery data
    // Session recovery cleanup is handled by SessionLifecycleManager
    return;
  }

  Map<String, double> _calculateElevationGain() {
    double gain = 0.0;
    double loss = 0.0;

    if (_currentState.locations.length < 2) {
      return {'gain': gain, 'loss': loss};
    }

    // Use same conservative threshold as main elevation calculation
    const double elevationThreshold = 2.0; // 2 meters minimum change

    for (int i = 1; i < _currentState.locations.length; i++) {
      final prevElevation = _currentState.locations[i - 1].altitude;
      final currElevation = _currentState.locations[i].altitude;
      final diff = currElevation - prevElevation;

      // Only count significant elevation changes to avoid GPS noise accumulation
      if (diff > elevationThreshold) {
        gain += diff;
      } else if (diff < -elevationThreshold) {
        loss += diff.abs();
      }
    }

    return {'gain': gain, 'loss': loss};
  }

  // Getters for other managers
  // CRITICAL FIX: Use preserved cumulative distance to prevent data loss after trimming
  double get totalDistance =>
      _lastKnownTotalDistance > _currentState.totalDistance
          ? _lastKnownTotalDistance
          : _currentState.totalDistance;
  bool get isGpsReady => _validLocationCount > 5;
  List<LocationPoint> get locationPoints => List.unmodifiable(_locationPoints);
  List<TerrainSegment> get terrainSegments =>
      List.unmodifiable(_terrainSegments);
  Position? get currentPosition => _currentState.currentPosition;
  double get elevationGain => _currentState.elevationGain;
  double get elevationLoss => _currentState.elevationLoss;
  List<SessionSplit> get splits => _splitTrackingService
      .getSplits()
      .map((splitData) => SessionSplit.fromJson(splitData))
      .toList();

  /// Restore metrics from crash recovery
  void restoreMetricsFromRecovery({
    required double totalDistanceKm,
    required double elevationGainM,
    required double elevationLossM,
  }) {
    AppLogger.info('[LOCATION_MANAGER] Restoring metrics from crash recovery: '
        'distance=${totalDistanceKm}km, elevation_gain=${elevationGainM}m, elevation_loss=${elevationLossM}m');

    // Update private elevation tracking fields
    _elevationGain = elevationGainM;
    _elevationLoss = elevationLossM;

    // CRITICAL: Update the baseline distance for incremental calculations
    _lastKnownTotalDistance = totalDistanceKm;

    _updateState(_currentState.copyWith(
      totalDistance: totalDistanceKm,
      elevationGain: elevationGainM,
      elevationLoss: elevationLossM,
      isGpsReady: true, // Mark as GPS ready since we have recovered data
    ));

    AppLogger.info('[LOCATION_MANAGER] Metrics restored successfully');
    AppLogger.debug(
        '[LOCATION_MANAGER] Elevation getter test: gain=${elevationGain}m, loss=${elevationLoss}m');
  }

  void _startSensorEstimation() {
    if (_estimationStartTime != null) return;
    _estimationStartTime = DateTime.now();
    _lastEstimatedPosition = _lastValidLocation;
    _estimatedDistance = 0.0;
    _estimatedDirection =
        0.0; // Assume initial direction from last speed/heading if available

    // Subscribe to sensors
    _accelerometerSub = accelerometerEvents.listen((event) {
      // Simple step detection: magnitude > threshold counts as step
      final magnitude =
          math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z) -
              9.8;
      if (magnitude.abs() > 1.5) {
        // Tune threshold
        _estimatedDistance +=
            0.7; // Average stride length in meters, can personalize
      }
    });

    _gyroSub = gyroscopeEvents.listen((event) {
      // Integrate angular velocity for direction change
      _estimatedDirection +=
          event.z * 0.0167; // Assuming 60Hz, convert rad/s to degrees
      _estimatedDirection = _estimatedDirection % 360;
    });

    // Generate estimated points every 5s
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_estimationStartTime == null) {
        timer.cancel();
        return;
      }
      if (_lastEstimatedPosition == null) return;

      // Estimate new position: distance in direction from last
      final deltaLat = (_estimatedDistance / 6371000) *
          (180 / math.pi) *
          math.cos(_estimatedDirection * math.pi / 180);
      final deltaLng = (_estimatedDistance / 6371000) * (180 / math.pi);

      final newPoint = LocationPoint(
        latitude: _lastEstimatedPosition!.latitude + deltaLat,
        longitude: _lastEstimatedPosition!.longitude + deltaLng,
        elevation: _lastEstimatedPosition!.elevation, // Keep same or estimate
        accuracy: 50.0, // High uncertainty for estimated
        timestamp: DateTime.now(),
        speed: _estimatedDistance / 5, // Avg speed over interval
        isEstimated: true,
      );

      // Add to points and reset accumulators
      _locationPoints.add(newPoint);
      _lastEstimatedPosition = newPoint;
      _estimatedDistance = 0.0;

      // Update state as if real point using a properly constructed Position
      final position = Position(
        latitude: newPoint.latitude,
        longitude: newPoint.longitude,
        timestamp: newPoint.timestamp,
        altitude: newPoint.elevation,
        accuracy: newPoint.accuracy,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: newPoint.speed ?? 0,
        speedAccuracy: 0,
        floor: null,
        isMocked: false,
      );
      handleEvent(LocationUpdated(position: position));
    });
  }

  void _stopSensorEstimation() {
    _accelerometerSub?.cancel();
    _gyroSub?.cancel();
    _estimationStartTime = null;
    _lastEstimatedPosition = null;
  }

  // Apply EMA smoothing, vertical accuracy gating, vertical speed sanity checks, and barometric fusion to altitude.
  double _filterAltitude({
    required double rawAltitude,
    required double? altitudeAccuracy,
    required DateTime timestamp,
  }) {
    // Calibrate barometer with GPS if not yet calibrated
    if (!_isBarometerCalibrated && _lastBarometricAltitude != null) {
      // Use actual barometric pressure if available, otherwise use sea-level fallback
      final estimatedPressure = _lastBarometricPressure ?? 101325.0;
      _calibrateBarometer(
        gpsAltitude: rawAltitude,
        gpsAccuracy: altitudeAccuracy,
        pressurePa: estimatedPressure,
      );
    }

    // Fuse GPS and barometric altitude for improved accuracy
    final double fusedAltitude = _fuseAltitude(
      gpsAltitude: rawAltitude,
      gpsAccuracy: altitudeAccuracy,
      timestamp: timestamp,
    );

    // Initialize on first sample
    if (_filteredAltitude == null) {
      _filteredAltitude = fusedAltitude;
      _lastAltitudeTs = timestamp;
      return _filteredAltitude!;
    }

    final double prev = _filteredAltitude!;
    final double dt = (_lastAltitudeTs != null)
        ? (timestamp.difference(_lastAltitudeTs!).inMilliseconds / 1000.0)
            .clamp(0.0, 10.0)
        : 0.0;

    // Gate by vertical accuracy if provided (only apply to GPS, barometric helps when GPS is poor)
    if (altitudeAccuracy != null &&
        altitudeAccuracy > _verticalAccuracyGateM &&
        _lastBarometricAltitude == null) {
      // Ignore poor-accuracy altitude updates only if no barometric data available
      return prev;
    }

    // Deadband: ignore tiny oscillations before applying EMA
    const double deadbandM = 0.3; // small deadband to suppress micro-noise
    if ((fusedAltitude - prev).abs() < deadbandM) {
      _lastAltitudeTs = timestamp; // keep time updated for dt gating elsewhere
      return prev;
    }

    // Compute an EMA to smooth noise on the fused altitude
    final double ema = (_emaAlpha * fusedAltitude) + ((1 - _emaAlpha) * prev);
    final double delta = ema - prev;

    // Reject absurd vertical speed spikes
    if (dt > 0.0) {
      final double vSpeed = (delta.abs()) / dt; // m/s
      if (vSpeed > _maxVerticalSpeedMs) {
        return prev;
      }
    }

    _filteredAltitude = ema;
    _lastAltitudeTs = timestamp;
    return _filteredAltitude!;
  }

  /// Handle barometric pressure readings for altitude fusion
  void _onBarometricReading(BarometricReading reading) {
    _lastBarometricTimestamp = reading.timestamp;
    _lastBarometricPressure = reading.pressurePa;

    // On iOS, use relative altitude directly from CMAltimeter
    if (reading.relativeAltitudeM != null) {
      _lastBarometricAltitude = reading.relativeAltitudeM;
      AppLogger.debug(
          '[BAROMETER] iOS relative altitude: ${reading.relativeAltitudeM!.toStringAsFixed(1)}m');
    } else {
      // Android: Convert pressure to altitude using barometric formula
      _lastBarometricAltitude =
          _barometerService.pressureToAltitude(reading.pressurePa);
      AppLogger.debug(
          '[BAROMETER] Android pressure altitude: ${_lastBarometricAltitude!.toStringAsFixed(1)}m from ${reading.pressurePa.toStringAsFixed(0)}Pa');
    }
  }

  /// Fuse GPS and barometric altitude for improved accuracy
  double _fuseAltitude({
    required double gpsAltitude,
    required double? gpsAccuracy,
    required DateTime timestamp,
  }) {
    // If no barometric data or not calibrated, use GPS only
    if (_lastBarometricAltitude == null || !_isBarometerCalibrated) {
      return gpsAltitude;
    }

    // Check if barometric data is recent (within 10 seconds)
    if (_lastBarometricTimestamp != null &&
        timestamp.difference(_lastBarometricTimestamp!).inSeconds.abs() > 10) {
      AppLogger.debug(
          '[ALTITUDE_FUSION] Barometric data too old, using GPS only');
      return gpsAltitude;
    }

    // Weight fusion based on GPS accuracy
    double fusionWeight = _fusionWeight;
    if (gpsAccuracy != null && gpsAccuracy > 10.0) {
      // Poor GPS accuracy - rely more on barometer
      fusionWeight = 0.3; // 30% GPS, 70% barometric
    } else if (gpsAccuracy != null && gpsAccuracy < 5.0) {
      // Good GPS accuracy - rely more on GPS
      fusionWeight = 0.8; // 80% GPS, 20% barometric
    }

    final fusedAltitude = (fusionWeight * gpsAltitude) +
        ((1 - fusionWeight) * _lastBarometricAltitude!);

    AppLogger.debug(
        '[ALTITUDE_FUSION] GPS: ${gpsAltitude.toStringAsFixed(1)}m (acc: ${gpsAccuracy?.toStringAsFixed(1)}), '
        'Baro: ${_lastBarometricAltitude!.toStringAsFixed(1)}m, '
        'Fused: ${fusedAltitude.toStringAsFixed(1)}m (weight: ${fusionWeight.toStringAsFixed(2)})');

    return fusedAltitude;
  }

  /// Start barometric streaming asynchronously to avoid blocking UI
  void _startBarometricStreamingAsync() {
    // Delay barometer initialization to avoid blocking countdown screen
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        AppLogger.debug(
            '[LOCATION_MANAGER] Starting barometric streaming (delayed)...');

        // Start streaming with timeout to prevent hanging
        await _barometerService.startStreaming().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            AppLogger.warning(
                '[LOCATION_MANAGER] Barometer initialization timed out, continuing without fusion');
            throw TimeoutException(
                'Barometer initialization timeout', const Duration(seconds: 3));
          },
        );

        _barometerSubscription = _barometerService.readings.listen(
          _onBarometricReading,
          onError: (error) {
            AppLogger.warning(
                '[LOCATION_MANAGER] Barometric streaming error: $error');
          },
        );
        AppLogger.info('[LOCATION_MANAGER] Barometric altitude fusion enabled');
      } catch (e) {
        AppLogger.warning(
            '[LOCATION_MANAGER] Failed to start barometric streaming: $e');
        // Continue without barometric fusion - GPS altitude only
      }
    });
  }

  /// Calibrate barometer with GPS readings
  void _calibrateBarometer({
    required double gpsAltitude,
    required double? gpsAccuracy,
    required double pressurePa,
  }) {
    // Only calibrate with accurate GPS readings
    if (gpsAccuracy == null || gpsAccuracy > 8.0) {
      return;
    }

    _gpsCalibrationCount++;
    AppLogger.debug(
        '[BAROMETER] Calibration sample ${_gpsCalibrationCount}/${_gpsCalibrationSamples}: GPS ${gpsAltitude.toStringAsFixed(1)}m');

    if (_gpsCalibrationCount >= _gpsCalibrationSamples) {
      _barometerService.calibrateWithGPS(
        gpsAltitudeM: gpsAltitude,
        pressurePa: pressurePa,
      );
      _isBarometerCalibrated = true;
      AppLogger.info(
          '[BAROMETER] Calibration completed after ${_gpsCalibrationSamples} GPS samples');
    }
  }
}
