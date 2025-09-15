import 'dart:math' as math;
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/models/user.dart';

/// Service for detecting AI Cheerleader triggers and assembling context
class AICheerleaderService {
  static const int _milestoneIntervalMeters = 1000; // Every 1km milestone
  static const int _timeCheckIntervalSeconds = 900; // Every 15 minutes
  static const double _slowPaceThreshold =
      0.6; // 60% of average pace = slow (more conservative)
  static const int _minimumTriggerIntervalSeconds =
      300; // Min 5 minutes between triggers
  static const int _hrSpikeMinElapsedSeconds =
      180; // Wait 3 minutes before HR analysis
  static const int _hrSpikeCooldownSeconds =
      600; // 10 minutes per HR spike (reduced frequency)
  static const double _hrSpikePercent =
      0.20; // 20% above baseline considered spike
  static const int _hrSpikeAbsoluteBpm = 150; // or absolute threshold

  // Randomization controls
  static const double _milestoneJitterPct = 0.20; // ±20%
  static const int _timeCheckMinSec = 12 * 60; // 12 minutes
  static const int _timeCheckMaxSec = 18 * 60; // 18 minutes
  static const double _paceThresholdJitter =
      0.05; // ±5% jitter on pace threshold

  DateTime? _lastTriggerTime;
  double? _lastDistance;
  DateTime? _lastTimeCheck;
  double? _averagePace;
  int _triggerCount = 0;
  double? _hrBaseline; // smoothed baseline BPM
  DateTime? _lastHeartRateSpikeTime;
  int? _lastHrSpikeCooldownSec;
  int? _nextMilestoneMeters;
  DateTime? _nextTimeCheckAt;
  TriggerType? _lastTriggerType;
  final math.Random _rand = math.Random();

  // Location mention tracking
  DateTime? _lastLocationMentionTime;
  String? _lastMentionedLocation;
  double? _lastMentionedLatitude;
  double? _lastMentionedLongitude;
  static const int _locationMentionCooldownMinutes = 12; // Don't mention location again for 12 minutes

  /// Analyzes session state and returns trigger type if one should fire
  CheerleaderTrigger? analyzeTriggers(ActiveSessionRunning state,
      {required bool preferMetric}) {
    final now = DateTime.now();

    // Respect minimum interval between triggers
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!).inSeconds <
            _minimumTriggerIntervalSeconds) {
      return null;
    }

    // Skip if session just started (less than 30 seconds)
    if (state.elapsedSeconds < 30) {
      return null;
    }

    // Prefer momentary conditions first (HR spike, pace drop), then milestone, then time check-in
    final hrTrigger = _checkHeartRateSpike(state, now);
    if (hrTrigger != null && _shouldAllowRepeat(TriggerType.heartRateSpike)) {
      _lastTriggerTime = now;
      _lastTriggerType = hrTrigger.type;
      _triggerCount++;
      return hrTrigger;
    }

    final paceTrigger = _checkPaceDropTrigger(state);
    if (paceTrigger != null && _shouldAllowRepeat(TriggerType.paceDrop)) {
      _lastTriggerTime = now;
      _lastTriggerType = paceTrigger.type;
      _triggerCount++;
      return paceTrigger;
    }

    final distanceTrigger =
        _checkDistanceMilestone(state, preferMetric: preferMetric);
    if (distanceTrigger != null && _shouldAllowRepeat(TriggerType.milestone)) {
      _lastTriggerTime = now;
      _lastTriggerType = distanceTrigger.type;
      _triggerCount++;
      return distanceTrigger;
    }

    final timeTrigger = _checkTimeCheckTrigger(state);
    if (timeTrigger != null && _shouldAllowRepeat(TriggerType.timeCheckIn)) {
      _lastTriggerTime = now;
      _lastTriggerType = timeTrigger.type;
      _triggerCount++;
      return timeTrigger;
    }

    return null;
  }

  /// Check for distance milestone achievements
  CheerleaderTrigger? _checkDistanceMilestone(ActiveSessionRunning state,
      {required bool preferMetric}) {
    final distanceMeters = state.distanceKm * 1000.0;
    final base = preferMetric ? _milestoneIntervalMeters : 1609; // meters

    // Only log preferences once during initialization, not on every distance check
    // This was causing excessive logging and potential ANR on Android

    // Initialize next milestone with jitter
    _nextMilestoneMeters ??= _jitteredInterval(base).toInt();

    if (distanceMeters >= _nextMilestoneMeters!) {
      // Compute milestone count in user's unit for context
      final milestoneCount = (distanceMeters ~/ base);
      // Only log the actual milestone trigger, not the next milestone calculation
      AppLogger.info(
          '[AI_MILESTONE] Milestone #$milestoneCount triggered at ${state.distanceKm}km');

      // Schedule the next milestone
      _nextMilestoneMeters =
          _nextMilestoneMeters! + _jitteredInterval(base).toInt();
      _lastDistance = state.distanceKm;
      return CheerleaderTrigger(
        type: TriggerType.milestone,
        data: {'distance': state.distanceKm, 'milestone': milestoneCount},
      );
    }
    return null;
  }

  /// Check for heart rate spikes that need encouragement
  CheerleaderTrigger? _checkHeartRateSpike(
      ActiveSessionRunning state, DateTime now) {
    // Skip if session too short or no heart rate data
    if (state.elapsedSeconds < _hrSpikeMinElapsedSeconds ||
        state.latestHeartRate == null) {
      return null;
    }

    // Respect cooldown period between HR spike triggers
    final cooldownSec = _lastHrSpikeCooldownSec ?? _hrSpikeCooldownSeconds;
    if (_lastHeartRateSpikeTime != null &&
        now.difference(_lastHeartRateSpikeTime!).inSeconds < cooldownSec) {
      return null;
    }

    final currentHR = state.latestHeartRate!;

    // Initialize baseline with first reading
    if (_hrBaseline == null) {
      _hrBaseline = currentHR.toDouble();
      return null;
    }

    // Update baseline with exponential moving average (90% old, 10% new)
    _hrBaseline = (_hrBaseline! * 0.9) + (currentHR * 0.1);

    // Detect spike: 20% above baseline OR absolute threshold of 150+ bpm
    final spikeThreshold = _hrBaseline! * (1 + _hrSpikePercent);
    final isSpike =
        currentHR > spikeThreshold || currentHR >= _hrSpikeAbsoluteBpm;

    if (isSpike) {
      final spikePct =
          ((currentHR - _hrBaseline!) / _hrBaseline!).clamp(0.0, 10.0);
      // Probability increases with spike magnitude; 0.4..1.0
      final p = _clamp(0.4 + (spikePct / 0.25) * 0.1, 0.4, 1.0);
      if (_rand.nextDouble() <= p) {
        _lastHeartRateSpikeTime = now;
        // Randomize cooldown between 8–12 minutes
        _lastHrSpikeCooldownSec =
            _randomInt(_timeCheckMinSec, _timeCheckMaxSec);
        AppLogger.info(
            '[AI_CHEERLEADER] Heart rate spike detected: ${currentHR}bpm (baseline: ${_hrBaseline!.round()}bpm, p=${p.toStringAsFixed(2)})');
        return CheerleaderTrigger(
          type: TriggerType.heartRateSpike,
          data: {
            'heartRate': currentHR,
            'baseline': _hrBaseline!.round(),
            'spikePercent': (spikePct * 100).round(),
          },
        );
      }
    }

    return null;
  }

  /// Check for pace drops that need encouragement
  CheerleaderTrigger? _checkPaceDropTrigger(ActiveSessionRunning state) {
    if (state.elapsedSeconds < 60) {
      return null; // Need 1min for pace analysis (for testing)
    }

    final currentPace = state.pace;
    if (currentPace == null || currentPace == 0) return null;

    // Calculate average pace
    _averagePace ??= currentPace;
    _averagePace =
        (_averagePace! * 0.8) + (currentPace * 0.2); // Smooth average

    // Check if current pace is significantly slower than average with jittered threshold
    final effThreshold = _slowPaceThreshold +
        (_rand.nextDouble() * 2 * _paceThresholdJitter - _paceThresholdJitter);
    if (currentPace < (_averagePace! * effThreshold)) {
      final slowdownPercent =
          ((1 - (currentPace / _averagePace!)) * 100).clamp(0.0, 100.0).round();
      // Probability scales with severity: 0.3..1.0 across 0–30%
      final p = _clamp(slowdownPercent / 30.0, 0.3, 1.0);
      if (_rand.nextDouble() > p) return null;
      return CheerleaderTrigger(
        type: TriggerType.paceDrop,
        data: {
          'currentPace': currentPace,
          'averagePace': _averagePace,
          'slowdownPercent': slowdownPercent,
        },
      );
    }

    return null;
  }

  /// Check for regular time-based check-ins
  CheerleaderTrigger? _checkTimeCheckTrigger(ActiveSessionRunning state) {
    final now = DateTime.now();
    _nextTimeCheckAt ??= now
        .add(Duration(seconds: _randomInt(_timeCheckMinSec, _timeCheckMaxSec)));
    if (now.isAfter(_nextTimeCheckAt!)) {
      _nextTimeCheckAt = now.add(
          Duration(seconds: _randomInt(_timeCheckMinSec, _timeCheckMaxSec)));
      return CheerleaderTrigger(
        type: TriggerType.timeCheckIn,
        data: {
          'elapsedMinutes': state.elapsedSeconds ~/ 60,
          'distanceKm': state.distanceKm,
        },
      );
    }
    return null;
  }

  /// Assemble context for AI generation based on current session state and trigger
  Map<String, dynamic> assembleContext(
      ActiveSessionRunning state,
      CheerleaderTrigger trigger,
      User user,
      String personality,
      bool explicitContent,
      {Map<String, dynamic>? history,
      Map<String, dynamic>? coachingPlan}) {
    AppLogger.info(
        '[AI_CONTEXT_DEBUG] Starting context assembly for trigger type: ${trigger.type}');
    AppLogger.info('[AI_CONTEXT_DEBUG] User data: ${user.toJson()}');
    AppLogger.info(
        '[AI_CONTEXT_DEBUG] Session state - elapsed: ${state.elapsedSeconds}s, distance: ${state.distanceKm}km');
    final Map<String, dynamic> context = <String, dynamic>{
      'trigger': <String, dynamic>{
        'type': trigger.type.name,
        'data': trigger.data,
        'triggerCount': _triggerCount,
      },
      'session': <String, dynamic>{
        'elapsedTime': {
          'elapsedMinutes': state.elapsedSeconds ~/ 60,
          'elapsedSeconds': state.elapsedSeconds,
          'formatted': _formatDuration(Duration(seconds: state.elapsedSeconds)),
        },
        'distance': <String, dynamic>{
          'distanceKm': state.distanceKm,
          'distanceMeters': state.distanceKm * 1000,
          'distanceMiles': state.distanceKm * 0.621371,
          'formatted': user.preferMetric
              ? '${state.distanceKm.toStringAsFixed(2)}km'
              : '${(state.distanceKm * 0.621371).toStringAsFixed(2)}mi',
          'unit': user.preferMetric ? 'km' : 'mi',
          'primaryValue': user.preferMetric
              ? state.distanceKm
              : (state.distanceKm * 0.621371),
        },
        'pace': <String, dynamic>{
          'pace': state.pace,
          'average': _averagePace,
        },
        'performance': <String, dynamic>{
          'calories': state.calories,
          'heartRate': state.latestHeartRate,
          'elevationGain': state.elevationGain,
        },
        'plannedDuration': state.plannedDuration,
        'progress': state.plannedDuration != null
            ? (state.elapsedSeconds / state.plannedDuration!) * 100
            : null,
      },
      'user': <String, dynamic>{
        'username': user.username,
        'preferMetric': user.preferMetric,
        'totalSessions': user.stats?.totalRucks ?? 0,
        'totalDistanceKm': user.stats?.totalDistanceKm ?? 0.0,
        'longestSessionMinutes': 0, // TODO: Add longest session tracking
      },
      'settings': <String, dynamic>{
        'personality': personality,
        'explicitContent': explicitContent,
      },
      // Historical user data for richer context
      'history': history,
      'environment': <String, dynamic>{
        'timeOfDay': _getTimeOfDay(),
        'sessionPhase': _getSessionPhase(state),
      },
      // Coaching plan context for personalized guidance
      'coachingPlan': coachingPlan,
    };

    AppLogger.info('[AI_CONTEXT_DEBUG] Final assembled context:');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Trigger: ${context['trigger']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Session: ${context['session']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - User: ${context['user']}');
    AppLogger.info(
        '[AI_CONTEXT_DEBUG] - Environment: ${context['environment']}');
    AppLogger.info(
        '[AI_CONTEXT_DEBUG] - Environment runtimeType: ${context['environment']?.runtimeType}');

    return context;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'early_morning';
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    if (hour < 20) return 'evening';
    return 'night';
  }

  String _getSessionPhase(ActiveSessionRunning state) {
    final elapsedMinutes = state.elapsedSeconds ~/ 60;
    if (elapsedMinutes < 10) return 'warmup';
    if (state.plannedDuration != null) {
      final progress = state.elapsedSeconds / state.plannedDuration!;
      if (progress < 0.3) return 'early';
      if (progress < 0.7) return 'middle';
      return 'final_push';
    } else if (state.elapsedSeconds < 900) {
      return 'warmup'; // 15 minutes
    }
    return elapsedMinutes < 30 ? 'early' : 'steady_state';
  }

  /// Check if location should be included in context based on cooldown and distance
  bool shouldIncludeLocationContext({
    String? currentLocation,
    double? currentLatitude,
    double? currentLongitude,
  }) {
    final now = DateTime.now();

    // Always include if no previous mention
    if (_lastLocationMentionTime == null) {
      return true;
    }

    // Check cooldown period
    final timeSinceLastMention = now.difference(_lastLocationMentionTime!);
    if (timeSinceLastMention.inMinutes < _locationMentionCooldownMinutes) {
      // Only include if location has changed significantly (>1km)
      if (currentLatitude != null && currentLongitude != null &&
          _lastMentionedLatitude != null && _lastMentionedLongitude != null) {
        final distance = _calculateDistance(
          _lastMentionedLatitude!, _lastMentionedLongitude!,
          currentLatitude, currentLongitude
        );
        return distance > 1000; // More than 1km difference
      }
      return false;
    }

    // Cooldown period has passed, allow location mention
    return true;
  }

  /// Record that location was mentioned in an AI response
  void recordLocationMention({
    String? location,
    double? latitude,
    double? longitude,
  }) {
    _lastLocationMentionTime = DateTime.now();
    _lastMentionedLocation = location;
    _lastMentionedLatitude = latitude;
    _lastMentionedLongitude = longitude;
    AppLogger.info('[AI_CHEERLEADER] Location mention recorded: $location');
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    final double dLat = (lat2 - lat1) * (math.pi / 180);
    final double dLon = (lon2 - lon1) * (math.pi / 180);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) * math.cos(lat2 * (math.pi / 180)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Resets service state for new session
  void reset() {
    _lastTriggerTime = null;
    _lastDistance = null;
    _lastTimeCheck = null;
    _averagePace = null;
    _triggerCount = 0;
    _hrBaseline = null;
    _lastHeartRateSpikeTime = null;
    _lastHrSpikeCooldownSec = null;
    _nextMilestoneMeters = null;
    _nextTimeCheckAt = null;
    _lastTriggerType = null;
    // Reset location tracking
    _lastLocationMentionTime = null;
    _lastMentionedLocation = null;
    _lastMentionedLatitude = null;
    _lastMentionedLongitude = null;
    AppLogger.info('[AI_CHEERLEADER] Service reset for new session');
  }

  int _randomInt(int min, int max) => min + _rand.nextInt((max - min) + 1);
  double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
  double _jitteredInterval(int baseMeters) {
    final jitter = 1.0 +
        (_rand.nextDouble() * 2 * _milestoneJitterPct - _milestoneJitterPct);
    return baseMeters * jitter;
  }

  bool _shouldAllowRepeat(TriggerType type) {
    // Prefer variety: if same as last type, allow only with small probability
    if (_lastTriggerType == null || _lastTriggerType != type) return true;
    return _rand.nextDouble() <
        0.3; // 30% chance to allow immediate repeat of same type
  }
}

enum TriggerType {
  milestone,
  paceDrop,
  timeCheckIn,
  sessionComplete,
  manualRequest,
  heartRateSpike,
}

class CheerleaderTrigger {
  final TriggerType type;
  final Map<String, dynamic> data;

  CheerleaderTrigger({
    required this.type,
    required this.data,
  });
}
