import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/features/health_integration/domain/health_service.dart';
import 'package:rucking_app/features/ruck_session/data/heart_rate_sample_storage.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'rucking_api_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/features/ruck_session/domain/services/heart_rate_zone_service.dart';

/// Service for managing communication with Apple Watch companion app
class WatchService {
  final LocationService _locationService;
  final HealthService _healthService;
  final AuthService _authService;

  // Session state
  bool _isSessionActive = false;
  bool _isPaused = false;
  String? _currentSessionId; // Track current session ID for sync
  double _currentDistance = 0.0;
  Duration _currentDuration = Duration.zero;
  double _currentPace = 0.0;
  double? _currentHeartRate;
  double _ruckWeight = 0.0;
  int _currentCalories = 0;
  double _currentElevationGain = 0.0;
  double _currentElevationLoss = 0.0;
  DateTime? _watchStartedAt;

  // Persisted settings
  static const String _lastRuckWeightKey = 'last_ruck_weight_kg';
  static const String _lastUserWeightKey = 'last_user_weight_kg';
  double? _lastRuckWeightKg;
  double? _lastUserWeightKg;

  // Method channels
  late MethodChannel _watchSessionChannel;
  late EventChannel _heartRateEventChannel;
  late EventChannel _stepEventChannel;

  // Stream controllers for watch events
  final _sessionEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _healthDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _heartRateController = StreamController<double>.broadcast();
  final _stepsController = StreamController<int>.broadcast();
  StreamSubscription? _nativeHeartRateSubscription;
  StreamSubscription? _nativeStepsSubscription;
  
  // Constants for heart rate sampling
  static const Duration _heartRateSampleInterval = Duration(seconds: 30); // Sample every 30 seconds
  static const int _heartRateSignificantChangeBpm = 10; // Consider changes of 10+ BPM significant
  
  // Heart rate sampling variables
  DateTime? _lastHeartRateSampleTime;
  double? _lastSampledHeartRate;
  
  // Flag to track if we've attempted to reconnect the heart rate listener
  bool _isReconnectingHeartRate = false;
  int _heartRateReconnectAttempts = 0;
  Timer? _heartRateWatchdogTimer;
  DateTime? _lastHeartRateUpdateTime;

  // Heart rate samples list
  List<HeartRateSample> _currentSessionHeartRateSamples = [];

  // Force state sync flag
  bool _forceStateSync = false;

  WatchService(this._locationService, this._healthService, this._authService) {
    // Watch service initialization
    _initPlatformChannels();
    // Watch service initialized
  }

  /// Public stream of live step count updates from the watch
  Stream<int> get stepsStream => _stepsController.stream;

  void _initPlatformChannels() {
    // Initialize platform channels - use different prefixes for iOS vs Android
    if (Platform.isIOS) {
      _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');
      _heartRateEventChannel = const EventChannel('com.getrucky.gfy/heartRateStream');
      _stepEventChannel = const EventChannel('com.getrucky.gfy/stepStream');
    } else {
      // Android uses com.ruck.app prefix
      _watchSessionChannel = const MethodChannel('com.ruck.app/watch_session');
      _heartRateEventChannel = const EventChannel('com.ruck.app/heartRateStream');
      _stepEventChannel = const EventChannel('com.ruck.app/stepStream');
    }

    // Setup method call handlers
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);

    // Heart rate handled via WatchConnectivity direct messages (watchHeartRateUpdate command)
    // No need for separate EventChannel - removed to eliminate dual stream conflict

    // Setup steps event channel
    _setupNativeStepsListener();

    // Register Pigeon handler
    RuckingApi.setUp(RuckingApiHandler(this));
    // Platform channels setup complete

    // Drain any queued watch messages that arrived while Flutter wasn't ready
    // This ensures world-class reliability when the iPhone app wasn't foregrounded.
    Future.delayed(const Duration(milliseconds: 500), _drainQueuedMessages);

    // Load persisted settings and sync to watch immediately
    Future.delayed(const Duration(milliseconds: 100), () async {
      await _loadAndSyncUserPreferences();
    });
  }

  /// Handle method calls from the watch session channel
  Future<dynamic> _handleWatchSessionMethod(MethodCall call) async {
    // Silent method call processing

    switch (call.method) {
      case 'onWatchSessionUpdated':
        // Safely handle the arguments map with proper type casting
        if (call.arguments is! Map) {
          AppLogger.error('[WATCH] Invalid arguments type: ${call.arguments.runtimeType}');
          return;
        }
        
        // Convert from Map<Object?, Object?> to Map<String, dynamic>
        final rawMap = call.arguments as Map<Object?, Object?>;
        final data = <String, dynamic>{};
        rawMap.forEach((key, value) {
          if (key is String) {
            data[key] = value;
          }
        });
        
        AppLogger.info('[WATCH] Session updated with data: $data');
        _sessionEventController.add(data);
        
        // Get the command type from the message
        final command = data['command'] as String?;
        
        if (command == 'startSessionFromWatch') {
          AppLogger.info('[WATCH] Watch-initiated start received');
          await _handleSessionStartedFromWatch(data);
        } else if (command == 'startSession' || command == 'workoutStarted') {
          AppLogger.info('[WATCH] Start ACK received: $command (no-op)');
          // Do not create/start another session here
        } else if (command == 'pauseSession') {
          await pauseSessionFromWatchCallback();
        } else if (command == 'resumeSession') {
          await resumeSessionFromWatchCallback();
        } else if (command == 'pauseConfirmed') {
          AppLogger.info('[WATCH] Pause confirmed by watch');
          _isPaused = true;
        } else if (command == 'resumeConfirmed') {
          AppLogger.info('[WATCH] Resume confirmed by watch');
          _isPaused = false;
        } else if (command == 'endSession' || command == 'sessionEnded' || command == 'workoutStopped') {
          AppLogger.info('[WATCH] End command received: $command');
          await _handleSessionEndedFromWatch(data);
        } else if (command == 'watchHeartRateUpdate') {
          final hr = data['heartRate'];
          if (hr is num) {
            final hrValue = hr.toDouble();
            AppLogger.info('[WATCH_SERVICE] Heart rate update from WatchConnectivity: $hrValue BPM');
            handleWatchHeartRateUpdate(hrValue);
            _lastHeartRateUpdateTime = DateTime.now();
          } else {
            AppLogger.warning('[WATCH_SERVICE] [HR_DEBUG] Invalid heart rate from WatchConnectivity: $hr');
          }
        } else if (command == 'pingResponse') {
          AppLogger.info('[WATCH] Ping response received from watch: ${data['message']}');
        }

        return true;
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Handle a session started from the watch
  Future<void> _handleSessionStartedFromWatch(Map<String, dynamic> data) async {
    AppLogger.info('[WATCH] Processing session start from watch');
    
    // Watch cannot create sessions - only phone can create sessions
    AppLogger.info('[WATCH] Watch session creation disabled - sessions must be started from phone');
    await _sendMessageToWatch({
      'command': 'sessionStartFailed',
      'error': 'Sessions must be started from phone app'
    });
    return;
  }

  /// Backfill distance from Apple Health for watch-only period
  Future<void> backfillDistanceFromHealth({required String sessionId, required DateTime startedAt, required DateTime endedAt}) async {
    try {
      final health = GetIt.instance.get<HealthService>();
      final meters = await health.getDistanceMetersBetween(startedAt, endedAt);
      if (meters <= 0) return;
      final km = meters / 1000.0;
      await GetIt.instance<ApiClient>().patch('/rucks/$sessionId', {
        'distance_km': km,
        // Optionally set completed_at if this is a finalization path
      });
      AppLogger.info('[WATCH] Backfilled distance ${km.toStringAsFixed(3)} km from Health');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to backfill distance from Health: $e');
    }
  }

  DateTime? _parseEpochOrIso(dynamic value) {
    try {
      if (value == null) return null;
      if (value is int) {
        // seconds precision assumed
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
      }
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true);
      }
      if (value is String) {
        return DateTime.tryParse(value)?.toUtc();
      }
    } catch (_) {}
    return null;
  }

  /// Drain queued watch messages from native and process them
  Future<void> _drainQueuedMessages() async {
    try {
      final dynamic result = await _watchSessionChannel.invokeMethod('getQueuedWatchMessages');
      if (result is List) {
        for (final item in result) {
          if (item is Map) {
            final Map<String, dynamic> data = item.map((k, v) => MapEntry(k.toString(), v));
            final String? command = data['command'] as String?;
            if (command == null) continue;
            switch (command) {
              case 'startSessionFromWatch':
                await _handleSessionStartedFromWatch(data);
                break;
              case 'startSession':
              case 'workoutStarted':
                // ACKs only; do nothing
                break;
              case 'pauseSession':
                await pauseSessionFromWatchCallback();
                break;
              case 'resumeSession':
                await resumeSessionFromWatchCallback();
                break;
              case 'endSession':
              case 'workoutStopped':
              case 'sessionEnded':
                await _handleSessionEndedFromWatch(data);
                break;
              default:
                // Ignore unknown commands; may be metrics/context updates already handled elsewhere
                break;
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error('[WATCH] Failed to drain queued watch messages: $e');
    }
  }

  /// Handle a session ended from the watch
  Future<void> _handleSessionEndedFromWatch(Map<String, dynamic> data) async {
    try {
      AppLogger.info('[WATCH] Session ended from watch, completing session...');
      
      // Update local state
      _isSessionActive = false;
      _isPaused = false;
      
      // Save heart rate samples to storage
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
      
      // Resolve ActiveSessionBloc and current state/sessionId
      final activeBloc = GetIt.I.isRegistered<ActiveSessionBloc>() ? GetIt.I<ActiveSessionBloc>() : null;
      final currentState = activeBloc?.state;
      final String? sessionId = (currentState is ActiveSessionRunning) ? currentState.sessionId : null;

      // Attempt a final distance backfill from watch start to now (only when we know watch start time and sessionId)
      if (_watchStartedAt != null && sessionId != null) {
        AppLogger.info('[WATCH] Performing Health distance backfill before completion (sessionId=$sessionId, startedAt=$_watchStartedAt)');
        await backfillDistanceFromHealth(
          sessionId: sessionId,
          startedAt: _watchStartedAt!,
          endedAt: DateTime.now().toUtc(),
        );
      } else {
        AppLogger.debug('[WATCH] Skipping Health backfill: _watchStartedAt=${_watchStartedAt != null}, sessionId=${sessionId != null}');
      }

      // Always dispatch session completion to ActiveSessionBloc so phone ends the session
      if (activeBloc != null) {
        AppLogger.info('[WATCH] ===== WATCH DISPATCHING SESSION COMPLETED =====');
        AppLogger.info('[WATCH] Dispatching SessionCompleted to ActiveSessionBloc (currentState=${currentState?.runtimeType}, sessionId=$sessionId)');
        AppLogger.info('[WATCH] About to call activeBloc.add(SessionCompleted(sessionId: $sessionId))');
        activeBloc.add(SessionCompleted(sessionId: sessionId));
        AppLogger.info('[WATCH] SessionCompleted event dispatched successfully from watch');
        AppLogger.info('[WATCH] ===== WATCH SESSION COMPLETED DISPATCH COMPLETE =====');
      } else {
        AppLogger.warning('[WATCH] ActiveSessionBloc not registered; cannot dispatch SessionCompleted');
      }
      
      // Reset heart rate sampling variables
      _resetHeartRateSamplingVariables();

      // Proactively sync final state to the watch and send a stop signal
      try {
        await _sendMessageToWatch({
          'command': 'updateSessionState',
          'isPaused': false,
          'isMetric': true, // safe default; watch will override on next metrics push
          'isSessionActive': false, // CRITICAL: tell watch to cleanup and terminate
        });
        await _sendMessageToWatch({
          // Any of these are handled by the watch to terminate UI; prefer a clear end signal
          'command': 'sessionEnded',
        });
      } catch (e) {
        AppLogger.debug('[WATCH] Skipped/failed sending final stop/state-sync to watch: $e');
      }
      
    } catch (e) {
      AppLogger.error('[WATCH] Failed to handle session end from Watch: $e');
    }
  }

  /// Reset heart rate sampling tracking variables
  void _resetHeartRateSamplingVariables() {
    _lastHeartRateSampleTime = null;
    _lastSampledHeartRate = null;
    AppLogger.debug('[WATCH_SERVICE] Reset heart rate sampling variables');
  }

  /// Start a new rucking session on the watch (called from phone)
  Future<void> startSessionOnWatch(double ruckWeight, {bool isMetric = true}) async {
    AppLogger.info('[WATCH_SERVICE] Starting session on watch from phone - weight: $ruckWeight, metric: $isMetric');
    
    // Update local state first
    AppLogger.info('[WATCH] Setting session active before sending command to watch');
    _isSessionActive = true;
    _isPaused = false;
    _ruckWeight = ruckWeight;
    _resetHeartRateSamplingVariables();
    _currentSessionHeartRateSamples = [];

    try {
      // Send comprehensive session start data to watch with workout start command
      final message = {
        'command': 'workoutStarted', // Tell watch to start HealthKit workout session
        'isMetric': isMetric,
        'ruckWeight': ruckWeight,
        'sessionId': _currentSessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'phone',
        'startHeartRateMonitoring': true, // Explicitly request heart rate monitoring
        'forcePermissionCheck': true, // Force permission validation
      };
      
      AppLogger.info('[WATCH_SERVICE] Sending workout start command to watch: $message');
      await _sendMessageToWatch(message);
      
      // Send follow-up sync and permission requests asynchronously (non-blocking)
      Future.delayed(const Duration(milliseconds: 100), () async {
        try {
          await _sendMessageToWatch({
            'command': 'requestHealthKitPermissions',
            'requestHeartRate': true,
            'requestWorkout': true,
          });
          await syncSessionStateWithWatch();
        } catch (e) {
          AppLogger.debug('[WATCH] Background sync failed: $e');
        }
      });
      
      // Send session start notification with delay
      await Future.delayed(const Duration(milliseconds: 500));
      await sendSessionStartNotification(
        ruckWeight: ruckWeight,
        isMetric: isMetric,
      );
      
      AppLogger.info('[WATCH_SERVICE] Session successfully started on watch from phone');
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to start session on watch: $e');
      // Reset state on failure
      _isSessionActive = false;
      _isPaused = false;
    }
  }

  /// Send the session ID to the watch
  Future<void> sendSessionIdToWatch(String sessionId) async {
    try {
      // Send session ID to watch
      await _sendMessageToWatch({
        'command': 'setSessionId',
        'sessionId': sessionId,
      });
      // Session ID sent
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send session ID to Watch: $e');
    }
  }

  /// Send a message to the watch via the session channel
  Future<void> _sendMessageToWatch(Map<String, dynamic> message) async {
    try {
      AppLogger.debug('[WATCH] Sending message to watch: ${message['command']}');
      await _watchSessionChannel.invokeMethod('sendMessage', message);
      AppLogger.debug('[WATCH] Message sent successfully');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send message to Watch: $e');
      AppLogger.error('[WATCH] Message details: $message');
    }
  }

  /// Test connectivity to watch by sending a ping message
  Future<void> pingWatch() async {
    // Ping watch for connectivity test
    try {
      await _sendMessageToWatch({
        'command': 'ping',
        'timestamp': DateTime.now().toIso8601String(),
      });
      // Ping sent
    } catch (e) {
      AppLogger.error('[WATCH] Error pinging watch: $e');
    }
  }

  /// Load user preferences and sync to watch
  Future<void> _loadAndSyncUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load last ruck weight with sensible fallback
      _lastRuckWeightKg = prefs.getDouble(_lastRuckWeightKey) ?? AppConfig.defaultRuckWeight;
      _lastUserWeightKg = prefs.getDouble(_lastUserWeightKey) ?? 70.0; // Default user weight
      
      // Try to get user's actual weight from auth service
      try {
        final user = await _authService.getCurrentUser();
        if (user?.weightKg != null) {
          _lastUserWeightKg = user!.weightKg!;
        }
      } catch (e) {
        AppLogger.debug('[WATCH] Could not get user weight from auth service: $e');
      }
      
      AppLogger.info('[WATCH] Syncing preferences to watch - ruck: ${_lastRuckWeightKg}kg, user: ${_lastUserWeightKg}kg');
      
      // Sync to watch with guaranteed values
      await _sendMessageToWatch({
        'command': 'updateSettings',
        'ruckWeightKg': _lastRuckWeightKg,
        'userWeightKg': _lastUserWeightKg,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      AppLogger.info('[WATCH] User preferences synced to watch successfully');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to load/sync user preferences: $e');
    }
  }

  /// Set the current session ID for tracking (called when session starts from phone)
  void setCurrentSessionId(String sessionId) {
    _currentSessionId = sessionId;
    AppLogger.info('[WATCH] Session ID set for watch sync: $sessionId');
  }

  /// Synchronize session state between phone and watch
  Future<void> syncSessionStateWithWatch() async {
    try {
      // Get authoritative pause state from session bloc instead of local flag
      bool actualIsPaused = false;
      if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
        final bloc = GetIt.I<ActiveSessionBloc>();
        final state = bloc.state;
        actualIsPaused = state is ActiveSessionRunning ? state.isPaused : false;
      }
      
      AppLogger.info('[WATCH] Syncing session state with watch - isPaused: $actualIsPaused');
      await _sendMessageToWatch({
        'command': 'syncSessionState',
        'isSessionActive': _isSessionActive,
        'isPaused': actualIsPaused, // Use authoritative pause state
        'sessionId': _currentSessionId,
        'ruckWeight': _ruckWeight,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.error('[WATCH] Failed to sync session state: $e');
    }
  }

  /// Handle session state conflicts between phone and watch
  Future<void> _resolveSessionConflict(String source, Map<String, dynamic> data) async {
    AppLogger.warning('[WATCH] Session conflict detected from $source');
    
    // Phone takes precedence for session management
    if (_isSessionActive) {
      AppLogger.info('[WATCH] Phone session active - notifying watch to sync');
      await syncSessionStateWithWatch();
    } else {
      AppLogger.info('[WATCH] No phone session - allowing watch to proceed');
      if (source == 'watch') {
        await _handleSessionStartedFromWatch(data);
      }
    }
  }

  /// Sync user preferences to watch (can be called anytime)
  Future<void> syncUserPreferencesToWatch() async {
    await _loadAndSyncUserPreferences();
  }

  /// Send a split notification to the watch
  Future<bool> sendSplitNotification({
    required double splitDistance,
    required Duration splitDuration,
    required double totalDistance,
    required Duration totalDuration,
    required bool isMetric,
    double? splitCalories,
    double? splitElevationGain,
  }) async {
    try {
      AppLogger.info(
          '[WATCH] Sending split notification: $splitDistance ${isMetric ? 'km' : 'mi'}, time: ${_formatDuration(splitDuration)}, calories: ${splitCalories?.round() ?? 0}, elevation: ${splitElevationGain?.round() ?? 0}m');

      final String formattedSplitDistance = '${splitDistance.toStringAsFixed(1)} ${isMetric ? 'km' : 'mi'}';
      final String formattedTotalDistance = '${totalDistance.toStringAsFixed(1)} ${isMetric ? 'km' : 'mi'}';
      
      // Format calories and elevation for display
      final String formattedCalories = '${(splitCalories ?? 0).round()} cal';
      final String formattedElevation = isMetric 
          ? '${(splitElevationGain ?? 0).round()} m' 
          : '${((splitElevationGain ?? 0) * 3.28084).round()} ft'; // Convert meters to feet

      AppLogger.debug('[WATCH] Formatted split distance for watch: $formattedSplitDistance');
      AppLogger.debug('[WATCH] User isMetric preference: $isMetric');
      AppLogger.debug('[WATCH] Split calories: $formattedCalories, elevation: $formattedElevation');

      await _sendMessageToWatch({
        'command': 'splitNotification',
        'splitDistance': formattedSplitDistance,
        'splitTime': _formatDuration(splitDuration),
        'totalDistance': formattedTotalDistance,
        'totalTime': _formatDuration(totalDuration),
        'splitCalories': formattedCalories,
        'splitElevation': formattedElevation,
        'isMetric': isMetric,
        'shouldVibrate': true, // Add flag to trigger vibration on watch
      });

      // Split notification sent
      return true;
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send split notification: $e');
      return false;
    }
  }

  /// Send a session start notification to alert users the watch app is available
  Future<bool> sendSessionStartNotification({
    required double ruckWeight,
    required bool isMetric,
  }) async {
    try {
      AppLogger.info('[WATCH] Sending session start notification to alert user about watch app availability');
      
      // Format ruck weight for display
      final String formattedWeight = isMetric 
          ? '${ruckWeight.toStringAsFixed(1)} kg'
          : '${(ruckWeight * 2.20462).toStringAsFixed(1)} lbs'; // Convert kg to lbs
      
      final message = {
        'command': 'sessionStartAlert',
        'title': 'Ruck Session Started',
        'message': 'Session tracking on your watch with $formattedWeight',
        'ruckWeight': formattedWeight,
        'isMetric': isMetric,
        'shouldVibrate': true, // Alert vibration to get user's attention
        'showNotification': true, // Flag to show prominent notification
      };
      
      AppLogger.debug('[WATCH] Session start alert message: $message');
      await _sendMessageToWatch(message);
      
      // Session start notification sent successfully
      return true;
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send session start notification: $e');
      return false;
    }
  }

  /// Send updated metrics to the watch
  Future<void> updateMetricsOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
    required int calories,
    required double elevation,
    double? elevationLoss, // Optional parameter for elevation loss
    required bool isMetric, // Used to convert values before sending to watch
    int? steps, // Optional step count to display on watch
  }) async {
    try {
      AppLogger.info('[WATCH] Sending updated metrics to watch');
      AppLogger.debug('[WATCH] [HR_DEBUG] Current heart rate for watch update: $_currentHeartRate');
      if (steps != null) {
        AppLogger.info('[STEPS LIVE] [WATCH] Including steps in metrics payload: $steps');
      }
      AppLogger.info('[WATCH] Unit preference being sent: isMetric=$isMetric');
      // Send distance in km - watch handles unit conversion based on isMetric flag
      // No need to pre-convert since watch will convert km to user's preferred display unit
      double displayDistance = distance; // Always send in km
      await _sendMessageToWatch({
        'command': 'updateMetrics',
        'isMetric': isMetric, // Add unit preference at top-level for quick access
        'metrics': {
          'distance': displayDistance,
          'durationSeconds': duration.inSeconds.toDouble(), // Send as Double for watch compatibility
          'pace': pace,
          'isPaused': isPaused ? 1 : 0, // Convert bool to int for Swift compatibility
          'calories': calories,
          // Include both elevation formats for compatibility
          'elevation': elevation,
          'elevationGain': elevation,
          'elevationLoss': elevationLoss ?? 0.0, // Use provided loss or default to 0
          'isMetric': isMetric, // Embed unit preference in nested metrics map as well
          if (steps != null) 'steps': steps,
          'heartRate': _getCurrentHeartRateWithFallback(),
          'hrZone': _getCurrentHeartRateWithFallback() != null ? _inferZoneLabel(_getCurrentHeartRateWithFallback()!) : null,
          'cadence': 160, // Add cadence to metrics
        },
      });
      AppLogger.debug('[WATCH] Metrics updated successfully with calories=$calories, elevation gain=$elevation, loss=${elevationLoss ?? 0.0}, steps=${steps ?? 'null'}');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send metrics to watch: $e');
    }
  }

  /// Get current heart rate with HealthKit fallback
  /// Returns watch heart rate if available (primary), otherwise HealthKit heart rate (fallback)
  double? _getCurrentHeartRateWithFallback() {
    // Primary: Watch heart rate
    if (_currentHeartRate != null) {
      return _currentHeartRate;
    }
    
    // Fallback: HealthKit heart rate
    try {
      final healthService = GetIt.instance<HealthService>();
      return healthService.currentHeartRate;
    } catch (e) {
      AppLogger.debug('[WATCH] HealthKit heart rate fallback failed: $e');
      return null;
    }
  }

  /// Infer Z1..Z5 label from current HR using user profile thresholds if available
  String _inferZoneLabel(double hr) {
    try {
      final authBloc = GetIt.instance<AuthBloc>();
      final state = authBloc.state;
      if (state is Authenticated && state.user.restingHr != null && state.user.maxHr != null && state.user.maxHr! > state.user.restingHr!) {
        final zones = HeartRateZoneService.zonesFromProfile(restingHr: state.user.restingHr!, maxHr: state.user.maxHr!);
        for (final z in zones) {
          if (hr >= z.min && hr <= z.max) return z.name;
        }
        if (hr < zones.first.min) return zones.first.name;
        return zones.last.name;
      }
    } catch (_) {}
    // Fallback with simple bands
    if (hr < 100) return 'Z1';
    if (hr < 120) return 'Z2';
    if (hr < 140) return 'Z3';
    if (hr < 160) return 'Z4';
    return 'Z5';
  }

  /// Send updated session metrics to the watch.
  /// Primary method uses WatchConnectivity which is the reliable channel.
  Future<bool> updateSessionOnWatch({
    required double distance,
    required Duration duration,
    required double pace,
    required bool isPaused,
    required double calories,
    required double elevationGain,
    required double elevationLoss,
    required bool isMetric, // Add user's metric preference
    int? steps, // Optional step count to include
  }) async {
    // Attempt to update session on watch
    
    bool success = false;
    
    // Send via WatchConnectivity which is the channel that's working reliably
    try {
      _currentDistance = distance;
      _currentDuration = duration;
      // Use the enhanced updateMetricsOnWatch that includes both elevation gain and loss
      await updateMetricsOnWatch(
        distance: distance,
        duration: duration,
        pace: pace,
        isPaused: isPaused,
        calories: calories.toInt(), // Convert to int since updateMetricsOnWatch expects int
        elevation: elevationGain,    // This is for backward compatibility
        elevationLoss: elevationLoss, // Pass elevation loss directly
        isMetric: isMetric, // Pass user's unit preference
        steps: steps,
      );
      
      // Successfully sent metrics via WatchConnectivity
      success = true;
      
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to send metrics via WatchConnectivity: $e');
      success = false;
    }
    
    return success;
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  /// Format number to two digits
  String twoDigits(int n) => n.toString().padLeft(2, '0');

  /// Pause the session on the watch
  Future<bool> pauseSessionOnWatch() async {
    // If a session is active, pause it
    if (_isSessionActive && !_isPaused) {
      _isPaused = true;
      AppLogger.info('[WATCH] Sending pause command to watch via WatchConnectivity');
      try {
        // Use WatchConnectivity instead of method channel for watch communication
        await _sendMessageToWatch({
          'command': 'pauseSession',
          'isPaused': true,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      } catch (e) {
        AppLogger.error('[WATCH] Error sending pause command to watch: $e');
        _isPaused = false; // Revert optimistic update
        return false;
      }
    } else {
      // Return true if already paused, false if not active, to indicate desired state might be met or not applicable
      return _isPaused; 
    }
  }

  /// Resume the session on the watch
  Future<bool> resumeSessionOnWatch() async {
    // If a session is active and paused, resume it
    if (_isSessionActive && _isPaused) {
      _isPaused = false;
      AppLogger.info('[WATCH] Sending resume command to watch via WatchConnectivity');
      try {
        // Use WatchConnectivity instead of method channel for watch communication
        await _sendMessageToWatch({
          'command': 'resumeSession',
          'isPaused': false,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return true;
      } catch (e) {
        AppLogger.error('[WATCH] Error sending resume command to watch: $e');
        _isPaused = true; // Revert optimistic update
        return false;
      }
    } else {
      // Return true if already resumed (not paused), false if not active
      return !_isPaused && _isSessionActive;
    }
  }

  /// End the session on the watch
  Future<bool> endSessionOnWatch() async {
    // Update local state
    _isSessionActive = false;
    _isPaused = false;
    _resetHeartRateSamplingVariables();
    
    // First save heart rate samples (outside the try-catch for the API call)
    try {
      await HeartRateSampleStorage.saveSamples(_currentSessionHeartRateSamples);
    } catch (e) {
      // Sending heart rate samples to API
      // Continue anyway, try to end the session on watch
    }
    
    bool success = false;
    try {
      AppLogger.info('[WATCH_SERVICE] Ending session on watch...');
      
      // Send termination commands in sequence to ensure watch receives them
      try {
        // First update state to inactive
        await _sendMessageToWatch({
          'command': 'updateSessionState',
          'isSessionActive': false,
          'isPaused': false,
        });
        
        // Wait a moment then send termination command
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Send multiple termination commands to ensure watch receives at least one
        await _sendMessageToWatch({'command': 'sessionEnded'});
        await _sendMessageToWatch({'command': 'workoutStopped'});
        await _sendMessageToWatch({'command': 'endSession'});
        
        AppLogger.info('[WATCH_SERVICE] Sent session termination commands to watch');
        
      } catch (e) {
        AppLogger.debug('[WATCH_SERVICE] Non-fatal: failed to send termination commands to watch: $e');
      }
      
      // Give the watch a moment to process the termination commands
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Call native API to ensure watch session is properly terminated
      final api = FlutterRuckingApi();
      
      // Make the API call separately
      await api.endSessionOnWatch();
      
      // Set success flag if no exceptions
      success = true;
      
      AppLogger.info('[WATCH_SERVICE] Session ended on watch successfully, app should be terminated');
      
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to end session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] handleWatchHeartRateUpdate called with: $heartRate');
    
    // Update our local heart rate value
    _currentHeartRate = heartRate;
    AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Updated _currentHeartRate to: $_currentHeartRate');
    
    // Add to heart rate stream for UI components (always update UI in real-time)
    _heartRateController.add(heartRate);
    AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Added heart rate to UI stream controller: $heartRate');
    
    // Add to session heart rate samples with throttling to reduce database load
    if (_isSessionActive) {
      final now = DateTime.now().toUtc();
      final int currentBpm = heartRate.toInt();
      
      // Determine if we should save this sample based on time interval or significant change
      bool shouldSaveSample = false;
      
      // Always save the first sample
      if (_lastHeartRateSampleTime == null || _lastSampledHeartRate == null) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving initial heart rate sample: $currentBpm BPM');
      } 
      // Save if enough time has passed since last sample
      else if (now.difference(_lastHeartRateSampleTime!) >= _heartRateSampleInterval) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving heart rate sample after interval: $currentBpm BPM');
      }
      // Save if there's a significant change in heart rate, even if interval hasn't passed
      else if (_lastSampledHeartRate != null && 
               (currentBpm - _lastSampledHeartRate!).abs() >= _heartRateSignificantChangeBpm) {
        shouldSaveSample = true;
        AppLogger.debug('[WATCH_SERVICE] Saving heart rate sample due to significant change: $currentBpm BPM (changed from ${_lastSampledHeartRate!.toInt()} BPM)');
      }
      
      // If we should save this sample, add it to our collection
      if (shouldSaveSample) {
        final sample = HeartRateSample(
          bpm: currentBpm,
          timestamp: now,
        );
        _currentSessionHeartRateSamples.add(sample);
        
        // Update our tracking variables
        _lastHeartRateSampleTime = now;
        _lastSampledHeartRate = heartRate;
        
        // Store heart rate samples for processing
        try {
          // Just add to our local list for now - we'll save the entire list later
          // HeartRateSampleStorage has static methods only, not instance methods
          // We'll call HeartRateSampleStorage.saveSamples() when the session ends
        } catch (e) {
          // Only log errors for heart rate storage
          AppLogger.error('[WATCH_SERVICE] Failed to store heart rate sample: $e');
        }
      }
    }
  }

  /// Stream to listen for heart rate updates from the Watch
  Stream<double> get onHeartRateUpdate => _heartRateController.stream;

  /// Get current heart rate
  double? getCurrentHeartRate() => _currentHeartRate;

  /// Get current session heart rate samples
  List<HeartRateSample> getCurrentSessionHeartRateSamples() => _currentSessionHeartRateSamples;

  // Callbacks for RuckingApiHandler
  void sessionStartedFromWatchCallback(double ruckWeight, dynamic response) {
    _isSessionActive = true;
    _isPaused = false;
    _ruckWeight = ruckWeight;
    // Session started via watch
  }

  /// Callback when session is paused from the watch
  /// This will update the internal state and dispatch the appropriate events to the ActiveSessionBloc
  Future<void> pauseSessionFromWatchCallback() async {
    // Regardless of current _isPaused value, forward the pause request – let the
    // ActiveSessionBloc decide if it is a duplicate. This prevents dropped
    // commands when our local flag drifts out-of-sync with the Bloc.
    if (!_isSessionActive) {
      return;
    }

    // Dispatch pause event to ActiveSessionBloc if available
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      final bloc = GetIt.I<ActiveSessionBloc>();
      final currState = bloc.state;
      final String? sessionId = (currState is ActiveSessionRunning) ? currState.sessionId : null;
      bloc.add(SessionPaused(source: SessionActionSource.watch, sessionId: sessionId));
    } else {
      AppLogger.warning('[WATCH_SERVICE] ActiveSessionBloc not ready in GetIt for pauseSessionFromWatchCallback');
    }

    // Update local flag after dispatching
    _isPaused = true;

    // Acknowledge pause to the watch so UI toggles immediately
    try {
      await _sendMessageToWatch({'command': 'pauseConfirmed'});
    } catch (e) {
      AppLogger.debug('[WATCH] Failed to send pauseConfirmed to watch: $e');
    }
  }

  /// Callback when session is resumed from the watch
  /// This will update the internal state and dispatch the appropriate events to the ActiveSessionBloc
  Future<void> resumeSessionFromWatchCallback() async {
    if (!_isSessionActive) {
      return;
    }

    // Dispatch resume event regardless of local _isPaused – Bloc will ignore if necessary
    if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
      final bloc = GetIt.I<ActiveSessionBloc>();
      final currState = bloc.state;
      final String? sessionId = (currState is ActiveSessionRunning) ? currState.sessionId : null;
      bloc.add(SessionResumed(source: SessionActionSource.watch, sessionId: sessionId));
    } else {
      AppLogger.warning('[WATCH_SERVICE] ActiveSessionBloc not ready in GetIt for resumeSessionFromWatchCallback');
    }

    _isPaused = false;

    // Acknowledge resume to the watch so UI toggles immediately
    try {
      await _sendMessageToWatch({'command': 'resumeConfirmed'});
    } catch (e) {
      AppLogger.debug('[WATCH] Failed to send resumeConfirmed to watch: $e');
    }
  }

  void endSessionFromWatchCallback(int duration, double distance, double calories) {
    _isSessionActive = false;
    _isPaused = false;
    AppLogger.info(
        '[WATCH_SERVICE] Session ended via RuckingApiHandler callback. Duration: $duration, Distance: $distance, Calories: $calories');
  }

  void dispose() {
    _heartRateWatchdogTimer?.cancel();
    
    // Cancel heart rate subscription with error handling
    try {
      _nativeHeartRateSubscription?.cancel();
    } catch (e) {
      // Ignore cancellation errors for streams that may not be active
      AppLogger.debug('[WATCH_SERVICE] Heart rate subscription dispose cancellation (safe to ignore): $e');
    }
    // Cancel steps subscription with error handling
    try {
      _nativeStepsSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('[WATCH_SERVICE] Steps subscription dispose cancellation (safe to ignore): $e');
    }
    
    _sessionEventController.close();
    _healthDataController.close();
    _heartRateController.close();
    _stepsController.close();
  }

  // ------------------------------------------------------------
  // Native heart-rate stream resilience helpers
  // ------------------------------------------------------------

  /// Start a watchdog timer to ensure heart rate updates are being received
  void _startHeartRateWatchdog() {
    _heartRateWatchdogTimer?.cancel();
    _heartRateWatchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final lastUpdateTime = _lastHeartRateUpdateTime;
      if (lastUpdateTime != null) {
        final timeSinceLastUpdate = DateTime.now().difference(lastUpdateTime);
        if (timeSinceLastUpdate > const Duration(seconds: 60) && !_isReconnectingHeartRate) {
          AppLogger.warning('[WATCH_SERVICE] No heart rate updates received for ${timeSinceLastUpdate.inSeconds} seconds - restarting listener');
          _restartNativeHeartRateListener();
        }
      }
    });
  }

  void _setupNativeHeartRateListener() {
    // DISABLED: EventChannel heart rate listener removed to eliminate dual stream conflict
    // Heart rate now handled exclusively via WatchConnectivity 'watchHeartRateUpdate' command
    AppLogger.info('[WATCH_SERVICE] EventChannel heart rate listener disabled - using WatchConnectivity only');
    return;
    // Cancel any existing subscription first
    try {
      _nativeHeartRateSubscription?.cancel();
    } catch (e) {
      // Ignore cancellation errors for streams that may not be active
      AppLogger.debug('[WATCH_SERVICE] Heart rate subscription cancellation (safe to ignore): $e');
    }
    _nativeHeartRateSubscription = null;
    
    // Setup heart rate listener
    
    try {
      AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Setting up native heart rate EventChannel listener...');
      _nativeHeartRateSubscription = _heartRateEventChannel.receiveBroadcastStream().listen(
        (dynamic heartRate) {
          AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Raw heart rate received from native: $heartRate (type: ${heartRate.runtimeType})');
          
          double? hrValue;
          
          // Handle different data formats from watch
          if (heartRate is num) {
            // Direct numeric value
            hrValue = heartRate.toDouble();
            AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Direct numeric heart rate: $hrValue');
          } else if (heartRate is Map) {
            // Map format (WatchConnectivity message)
            final hr = heartRate['heartRate'];
            if (hr is num) {
              hrValue = hr.toDouble();
              AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Extracted heart rate from map: $hrValue');
            } else {
              AppLogger.warning('[WATCH_SERVICE] [HR_DEBUG] Invalid heartRate value in map: $hr');
            }
          } else {
            AppLogger.warning('[WATCH_SERVICE] [HR_DEBUG] Invalid heart rate type received: ${heartRate.runtimeType}, value: $heartRate');
          }
          
          if (hrValue != null) {
            handleWatchHeartRateUpdate(hrValue);
            _lastHeartRateUpdateTime = DateTime.now();
          }
        },
        onError: (error) {
          AppLogger.error('[WATCH_SERVICE] [HR_DEBUG] Native heart rate EventChannel error: $error');
          _onNativeHeartRateError(error);
        },
        onDone: () {
          AppLogger.warning('[WATCH_SERVICE] [HR_DEBUG] Native heart rate EventChannel stream closed');
          _onNativeHeartRateDone();
        },
        cancelOnError: false, // Don't cancel on error, let our error handler decide
      );
      
      AppLogger.debug('[WATCH_SERVICE] [HR_DEBUG] Native heart rate EventChannel listener setup complete');
      
      // Notify native code that Flutter is ready to receive heart rate updates
      try {
        _watchSessionChannel.invokeMethod('flutterHeartRateListenerReady')
          .then((_) {})
          .catchError((error) {
            AppLogger.error('[WATCH_SERVICE] Error notifying native code about heart rate listener: $error');
          });
      } catch (e) {
        AppLogger.error('[WATCH_SERVICE] Failed to notify native about heart rate listener: $e');
      }
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to set up heart rate listener: $e');
      _scheduleHeartRateReconnect();
    }
  }

  void _onNativeHeartRateError(dynamic error) {
    AppLogger.error('[WATCH_SERVICE] Heart rate channel error: $error – scheduling restart');
    _scheduleHeartRateReconnect();
  }

  void _onNativeHeartRateDone() {
    AppLogger.warning('[WATCH_SERVICE] Heart rate channel closed – scheduling restart');
    _scheduleHeartRateReconnect();
  }

  void _scheduleHeartRateReconnect() {
    if (_isReconnectingHeartRate) {
      // Already reconnecting heart rate channel
      return;
    }
    
    _isReconnectingHeartRate = true;
    _heartRateReconnectAttempts++;
    
    // Exponential backoff for reconnection attempts
    final delaySeconds = math.min(30, math.pow(2, math.min(5, _heartRateReconnectAttempts)).toInt());
    // Schedule heart rate reconnect
    
    // Small delay to avoid tight reconnection loops
    Future.delayed(Duration(seconds: delaySeconds), () {
      _restartNativeHeartRateListener();
    });
  }

  void _restartNativeHeartRateListener() {
    // Restart heart rate listener
    try {
      _nativeHeartRateSubscription?.cancel();
    } catch (e) {
      // Ignore cancellation errors for streams that may not be active
      AppLogger.debug('[WATCH_SERVICE] Heart rate subscription restart cancellation (safe to ignore): $e');
    }
    // _setupNativeHeartRateListener(); // DISABLED - using WatchConnectivity only
  }
 
  void _setupNativeStepsListener() {
    // Cancel any existing steps subscription
    try {
      _nativeStepsSubscription?.cancel();
    } catch (e) {
      AppLogger.debug('[WATCH_SERVICE] Steps subscription cancellation (safe to ignore): $e');
    }
    _nativeStepsSubscription = null;

    try {
      AppLogger.debug('[WATCH_SERVICE] [STEPS] Setting up native steps EventChannel listener...');
      _nativeStepsSubscription = _stepEventChannel
          .receiveBroadcastStream()
          .listen((dynamic event) {
        try {
          int? steps;
          if (event is int) {
            steps = event;
          } else if (event is num) {
            steps = event.toInt();
          } else if (event is Map) {
            final map = Map<Object?, Object?>.from(event);
            // Common shapes from native:
            // { 'steps': 123 }
            // { 'command': 'watchStepUpdate', 'value': 123 }
            // { 'command': 'watchStepUpdate', 'count': 123 }
            final cmd = map['command']?.toString();
            if (map.containsKey('steps')) {
              final val = map['steps'];
              if (val is int) steps = val;
              if (val is num) steps = val.toInt();
            }
            if (steps == null && cmd == 'watchStepUpdate') {
              final dynamic alt = map['value'] ?? map['count'];
              if (alt is int) steps = alt;
              if (alt is num) steps = alt.toInt();
            }
          }

          // Only forward step updates while a session is active and not paused
          if (steps != null) {
            if (_isSessionActive && !_isPaused) {
              AppLogger.info('[STEPS LIVE] Received step update from watch (active): $steps');
              _stepsController.add(steps);
            } else {
              AppLogger.debug('[WATCH_SERVICE] [STEPS] Dropping step update because session is not active or is paused (active=$_isSessionActive, paused=$_isPaused): $steps');
            }
          } else {
            AppLogger.debug('[WATCH_SERVICE] [STEPS] Unrecognized steps event payload: $event');
          }
        } catch (e) {
          AppLogger.error('[WATCH_SERVICE] [STEPS] Error processing steps event: $e');
        }
      }, onError: (error) {
        AppLogger.error('[WATCH_SERVICE] [STEPS] Steps channel error: $error');
      }, onDone: () {
        AppLogger.warning('[WATCH_SERVICE] [STEPS] Steps channel closed');
      });
    } catch (e) {
      AppLogger.error('[WATCH_SERVICE] Failed to set up steps listener: $e');
    }
  }
  
  /// Public method to force restart the heart rate monitoring from outside this class
  void restartHeartRateMonitoring() {
    // Manual restart of heart rate monitoring
    _heartRateReconnectAttempts = 0;
    _isReconnectingHeartRate = false;
    _restartNativeHeartRateListener();
  }
}