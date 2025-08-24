import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/api/rucking_api.dart';
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

  // Stream controllers for watch events
  final _sessionEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _healthDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _heartRateController = StreamController<double>.broadcast();
  StreamSubscription? _nativeHeartRateSubscription;
  
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

  WatchService(this._locationService, this._healthService, this._authService) {
    // Watch service initialization
    _initPlatformChannels();
    // Watch service initialized
  }

  void _initPlatformChannels() {
    // Initialize platform channels - use different prefixes for iOS vs Android
    if (Platform.isIOS) {
      _watchSessionChannel = const MethodChannel('com.getrucky.gfy/watch_session');
      _heartRateEventChannel = const EventChannel('com.getrucky.gfy/heartRateStream');
    } else {
      // Android uses com.ruck.app prefix
      _watchSessionChannel = const MethodChannel('com.ruck.app/watch_session');
      _heartRateEventChannel = const EventChannel('com.ruck.app/heartRateStream');
    }

    // Setup method call handlers
    _watchSessionChannel.setMethodCallHandler(_handleWatchSessionMethod);

    // Setup heart rate event channel
    _setupNativeHeartRateListener();
    _startHeartRateWatchdog();

    // Register Pigeon handler
    RuckingApi.setUp(RuckingApiHandler(this));
    // Platform channels setup complete

    // Drain any queued watch messages that arrived while Flutter wasn't ready
    // This ensures world-class reliability when the iPhone app wasn't foregrounded.
    Future.delayed(const Duration(milliseconds: 500), _drainQueuedMessages);

    // Load persisted settings and sync to watch
    Future.delayed(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _lastRuckWeightKg = prefs.getDouble(_lastRuckWeightKey) ?? _lastRuckWeightKg;
        _lastUserWeightKg = prefs.getDouble(_lastUserWeightKey) ?? _lastUserWeightKg;
        await _sendMessageToWatch({
          'command': 'updateSettings',
          if (_lastRuckWeightKg != null) 'ruckWeightKg': _lastRuckWeightKg,
          if (_lastUserWeightKg != null) 'userWeightKg': _lastUserWeightKg,
        });
      } catch (_) {}
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
        
        if (command == 'startSession' || command == 'startSessionFromWatch' || command == 'workoutStarted') {
          AppLogger.info('[WATCH] Start command received: $command');
          await _handleSessionStartedFromWatch(data);
        } else if (command == 'pauseSession') {
          await pauseSessionFromWatchCallback();
        } else if (command == 'resumeSession') {
          await resumeSessionFromWatchCallback();
        } else if (command == 'endSession' || command == 'sessionEnded' || command == 'workoutStopped') {
          AppLogger.info('[WATCH] End command received: $command');
          await _handleSessionEndedFromWatch(data);
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
    final double ruckWeight = (data['ruckWeight'] as num?)?.toDouble() ?? 10.0;
    final DateTime? startedAt = _parseEpochOrIso(data['startedAt']);
    final double? userWeightKg = (data['userWeightKg'] as num?)?.toDouble();
    final double? ruckWeightKg = (data['ruckWeightKg'] as num?)?.toDouble() ?? ruckWeight;
    // Handle session start from watch

    try {
      // Get current user
      final authState = await _authService.getCurrentUser();
      if (authState == null) {
        AppLogger.error('[WATCH] No authenticated user found - cannot create session from Watch');
        return;
      }
      // User authenticated

      // Create ruck session
      final response = await GetIt.instance<ApiClient>().post('/rucks', {
        'ruckWeight': ruckWeightKg,
        'ruck_weight_kg': ruckWeightKg,
        if (userWeightKg != null) 'weight_kg': userWeightKg,
        'is_manual': false,
        if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
      });

      AppLogger.debug('[WATCH] API response for session creation: $response');

      if (response == null || !response.containsKey('id')) {
        AppLogger.error('[WATCH] Failed to create session - invalid API response');
        return;
      }
      // Session created successfully

      final String sessionId = response['id'].toString();
      // Session ID extracted

      // Send session ID to watch
      await sendSessionIdToWatch(sessionId);

      // Start session on backend
      await GetIt.instance<ApiClient>().post('/rucks/$sessionId/start', {
        if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
      });

      // Notify watch of workout start
      await _sendMessageToWatch({
        'command': 'workoutStarted',
        'sessionId': sessionId,
        'ruckWeight': ruckWeight,
      });

      // Dispatch SessionStarted to ActiveSessionBloc so the phone app reflects the watch-initiated start
      try {
        if (GetIt.I.isRegistered<ActiveSessionBloc>()) {
          final userWeightForStart = userWeightKg ?? _lastUserWeightKg ?? 80.0;
          AppLogger.info('[WATCH] Dispatching SessionStarted to ActiveSessionBloc from watch (sessionId: $sessionId)');
          GetIt.I<ActiveSessionBloc>().add(SessionStarted(
            ruckWeightKg: ruckWeightKg ?? ruckWeight,
            userWeightKg: userWeightForStart,
            notes: 'Started from Apple Watch',
            plannedDuration: null,
            initialLocation: null,
            eventId: null,
            plannedRoute: null,
            plannedRouteDistance: null,
            plannedRouteDuration: null,
            aiCheerleaderEnabled: false,
            aiCheerleaderPersonality: null,
            aiCheerleaderExplicitContent: false,
          ));
        } else {
          AppLogger.warning('[WATCH] ActiveSessionBloc not registered; cannot dispatch SessionStarted');
        }
      } catch (e) {
        AppLogger.error('[WATCH] Failed to dispatch SessionStarted to ActiveSessionBloc: $e');
      }

      // Update app state
      _isSessionActive = true;
      _ruckWeight = ruckWeightKg ?? ruckWeight;
      _currentSessionHeartRateSamples = [];
      _watchStartedAt = startedAt ?? DateTime.now().toUtc();

      // Persist weights locally
      try {
        final prefs = await SharedPreferences.getInstance();
        if (ruckWeightKg != null) {
          _lastRuckWeightKg = ruckWeightKg;
          await prefs.setDouble(_lastRuckWeightKey, ruckWeightKg);
        }
        if (userWeightKg != null) {
          _lastUserWeightKg = userWeightKg;
          await prefs.setDouble(_lastUserWeightKey, userWeightKg);
        }
      } catch (_) {}

      // Backfill distance from Health for the watch-only window up to now
      try {
        final DateTime backfillStart = _watchStartedAt!;
        final DateTime backfillEnd = DateTime.now().toUtc();
        await backfillDistanceFromHealth(
          sessionId: sessionId,
          startedAt: backfillStart,
          endedAt: backfillEnd,
        );
      } catch (e) {
        AppLogger.debug('[WATCH] Backfill distance skipped/failed: $e');
      }
      // Session started successfully
    } catch (e) {
      AppLogger.error('[ERROR] Failed to process session start from Watch: $e');
    }
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
              case 'startSession':
              case 'startSessionFromWatch':
              case 'workoutStarted':
                await _handleSessionStartedFromWatch(data);
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
      final String? sessionId = (currentState is ActiveSessionRunning) ? currentState.sessionId?.toString() : null;

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
        AppLogger.info('[WATCH] Dispatching SessionCompleted to ActiveSessionBloc (currentState=${currentState?.runtimeType}, sessionId=$sessionId)');
        activeBloc.add(const SessionCompleted());
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

  /// Start a new rucking session on the watch
  Future<void> startSessionOnWatch(double ruckWeight, {bool isMetric = true}) async {
    AppLogger.info('[WATCH_SERVICE] startSessionOnWatch - sending isMetric: $isMetric to watch');
    _isSessionActive = true;
    _isPaused = false;
    _ruckWeight = ruckWeight;
    _resetHeartRateSamplingVariables();
    _currentSessionHeartRateSamples = []; // Clear samples for the new session

    try {
      // Store ruckWeight locally for calorie calculations, but don't send to watch
      // to prevent it from being displayed on the watch face
      final message = {
        'command': 'workoutStarted',
        'isMetric': isMetric, // Send user's unit preference to watch
        // ruckWeight intentionally omitted to prevent display on watch
      };
      AppLogger.info('[WATCH_SERVICE] Sending message to watch: $message');
      await _sendMessageToWatch(message);
      
      // Send session start notification to alert user about watch app availability
      // Small delay to ensure the workout start command is processed first
      await Future.delayed(const Duration(milliseconds: 500));
      await sendSessionStartNotification(
        ruckWeight: ruckWeight,
        isMetric: isMetric,
      );
    } catch (e) {
      AppLogger.error('[ERROR] Failed to start session on Watch: $e');
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
  }) async {
    try {
      AppLogger.info('[WATCH] Sending updated metrics to watch');
      AppLogger.info('[WATCH] Unit preference being sent: isMetric=$isMetric');
      // Send distance in km - watch handles unit conversion based on isMetric flag
      // No need to pre-convert since watch will convert km to user's preferred display unit
      double displayDistance = distance; // Always send in km
      await _sendMessageToWatch({
        'command': 'updateMetrics',
        'isMetric': isMetric, // Add unit preference at top-level for quick access
        'metrics': {
          'distance': displayDistance,
          'duration': duration.inSeconds,
          'pace': pace,
          'isPaused': isPaused ? 1 : 0, // Convert bool to int for Swift compatibility
          'calories': calories,
          // Include both elevation formats for compatibility
          'elevation': elevation,
          'elevationGain': elevation,
          'elevationLoss': elevationLoss ?? 0.0, // Use provided loss or default to 0
          'isMetric': isMetric, // Embed unit preference in nested metrics map as well
          if (_currentHeartRate != null) 'heartRate': _currentHeartRate,
          if (_currentHeartRate != null) 'hrZone': _inferZoneLabel(_currentHeartRate!),
        },
      });
      AppLogger.debug('[WATCH] Metrics updated successfully with calories=$calories, elevation gain=$elevation, loss=${elevationLoss ?? 0.0}');
    } catch (e) {
      AppLogger.error('[WATCH] Failed to send metrics to watch: $e');
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
      AppLogger.info('[WATCH] Sending pause command to watch');
      try {
        await _watchSessionChannel.invokeMethod('pauseSession');
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
      AppLogger.info('[WATCH] Sending resume command to watch');
      try {
        await _watchSessionChannel.invokeMethod('resumeSession');
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
      // CRITICAL: Send workoutStopped command to the watch to terminate the app
      AppLogger.debug('[WATCH_SERVICE] Sending workoutStopped command to watch to terminate app');
      await _sendMessageToWatch({
        'command': 'workoutStopped',
      });
      
      // Give the watch a moment to process the termination command
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Create the API instance
      final api = FlutterRuckingApi();
      
      // Make the API call separately
      await api.endSessionOnWatch();
      
      // Set success flag if no exceptions
      success = true;
      AppLogger.info('[WATCH_SERVICE] Session ended on watch successfully, app should be terminated');
    } catch (e) {
      // Log the error
      AppLogger.error('[WATCH_SERVICE] Failed to end session on watch: $e');
      success = false;
    }
    
    // Return the success flag explicitly
    return success;
  }

  /// Handle heart rate updates from the watch
  void handleWatchHeartRateUpdate(double heartRate) {
    // Update our local heart rate value
    _currentHeartRate = heartRate;
    // Add to heart rate stream for UI components (always update UI in real-time)
    _heartRateController.add(heartRate);
    
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
      GetIt.I<ActiveSessionBloc>().add(const SessionPaused(source: SessionActionSource.watch));
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
      GetIt.I<ActiveSessionBloc>().add(const SessionResumed(source: SessionActionSource.watch));
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
    
    _sessionEventController.close();
    _healthDataController.close();
    _heartRateController.close();
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
      _nativeHeartRateSubscription = _heartRateEventChannel.receiveBroadcastStream().listen(
        (dynamic heartRate) {
          if (heartRate is double) {
            _heartRateReconnectAttempts = 0; // Reset reconnect counter on successful update
            _lastHeartRateUpdateTime = DateTime.now();
            _isReconnectingHeartRate = false;
            // Silently handle heart rate update
            handleWatchHeartRateUpdate(heartRate);
          }
        },
        onError: _onNativeHeartRateError,
        onDone: _onNativeHeartRateDone,
        cancelOnError: false, // Don't cancel on error, let our error handler decide
      );
      
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
    _setupNativeHeartRateListener();
  }
  
  /// Public method to force restart the heart rate monitoring from outside this class
  void restartHeartRateMonitoring() {
    // Manual restart of heart rate monitoring
    _heartRateReconnectAttempts = 0;
    _isReconnectingHeartRate = false;
    _restartNativeHeartRateListener();
  }
}