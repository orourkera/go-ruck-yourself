import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/models/user.dart';

/// Service for detecting AI Cheerleader triggers and assembling context
class AICheerleaderService {
  static const int _milestoneIntervalMeters = 1000; // Every 1km
  static const int _timeCheckIntervalSeconds = 600; // Every 10 minutes
  static const double _slowPaceThreshold = 0.7; // 70% of average pace = slow
  static const int _minimumTriggerIntervalSeconds = 120; // Min 2 minutes between triggers
  static const int _hrSpikeMinElapsedSeconds = 180; // Wait 3 minutes before HR analysis
  static const int _hrSpikeCooldownSeconds = 300; // 5 minutes per HR spike
  static const double _hrSpikePercent = 0.20; // 20% above baseline considered spike
  static const int _hrSpikeAbsoluteBpm = 150; // or absolute threshold
  
  DateTime? _lastTriggerTime;
  double? _lastDistance;
  DateTime? _lastTimeCheck;
  double? _averagePace;
  int _triggerCount = 0;
  double? _hrBaseline; // smoothed baseline BPM
  DateTime? _lastHeartRateSpikeTime;

  /// Analyzes session state and returns trigger type if one should fire
  CheerleaderTrigger? analyzeTriggers(ActiveSessionRunning state) {
    final now = DateTime.now();
    
    // Respect minimum interval between triggers
    if (_lastTriggerTime != null && 
        now.difference(_lastTriggerTime!).inSeconds < _minimumTriggerIntervalSeconds) {
      return null;
    }

    // Skip if session just started (less than 2 minutes)
    if (state.elapsedSeconds < 120) {
      return null;
    }

    // 1. Distance Milestone Trigger
    final distanceTrigger = _checkDistanceMilestone(state);
    if (distanceTrigger != null) {
      _lastTriggerTime = now;
      _triggerCount++;
      return distanceTrigger;
    }

    // 2. Heart Rate Spike Trigger
    final hrTrigger = _checkHeartRateSpike(state, now);
    if (hrTrigger != null) {
      _lastTriggerTime = now;
      _triggerCount++;
      return hrTrigger;
    }

    // 3. Pace Drop Trigger
    final paceTrigger = _checkPaceDropTrigger(state);
    if (paceTrigger != null) {
      _lastTriggerTime = now;
      _triggerCount++;
      return paceTrigger;
    }

    // 4. Time Check-in Trigger
    final timeTrigger = _checkTimeCheckTrigger(state);
    if (timeTrigger != null) {
      _lastTriggerTime = now;
      _triggerCount++;
      return timeTrigger;
    }

    return null;
  }

  /// Check for distance milestone achievements
  CheerleaderTrigger? _checkDistanceMilestone(ActiveSessionRunning state) {
    final distanceKm = state.distanceKm;
    
    // First milestone at 1km
    if (_lastDistance == null && distanceKm >= 1) {
      _lastDistance = distanceKm;
      return CheerleaderTrigger(
        type: TriggerType.milestone,
        data: {'distance': distanceKm, 'milestone': 1},
      );
    }
    
    // Subsequent milestones
    if (_lastDistance != null) {
      final lastMilestone = (_lastDistance! / 1).floor();
      final currentMilestone = (distanceKm / 1).floor();
      
      if (currentMilestone > lastMilestone) {
        _lastDistance = distanceKm;
        return CheerleaderTrigger(
          type: TriggerType.milestone,
          data: {'distance': distanceKm, 'milestone': currentMilestone},
        );
      }
    }
    
    return null;
  }

  /// Check for heart rate spikes that need encouragement
  CheerleaderTrigger? _checkHeartRateSpike(ActiveSessionRunning state, DateTime now) {
    // Skip if session too short or no heart rate data
    if (state.elapsedSeconds < _hrSpikeMinElapsedSeconds || state.latestHeartRate == null) {
      return null;
    }

    // Respect cooldown period between HR spike triggers
    if (_lastHeartRateSpikeTime != null && 
        now.difference(_lastHeartRateSpikeTime!).inSeconds < _hrSpikeCooldownSeconds) {
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
    final isSpike = currentHR > spikeThreshold || currentHR >= _hrSpikeAbsoluteBpm;
    
    if (isSpike) {
      _lastHeartRateSpikeTime = now;
      AppLogger.info('[AI_CHEERLEADER] Heart rate spike detected: ${currentHR}bpm (baseline: ${_hrBaseline!.round()}bpm)');
      
      return CheerleaderTrigger(
        type: TriggerType.heartRateSpike,
        data: {
          'heartRate': currentHR,
          'baseline': _hrBaseline!.round(),
          'spikePercent': (((currentHR - _hrBaseline!) / _hrBaseline!) * 100).round(),
        },
      );
    }
    
    return null;
  }

  /// Check for pace drops that need encouragement
  CheerleaderTrigger? _checkPaceDropTrigger(ActiveSessionRunning state) {
    if (state.elapsedSeconds < 300) return null; // Need 5min for pace analysis
    
    final currentPace = state.pace;
    if (currentPace == null || currentPace == 0) return null;
    
    // Calculate average pace
    _averagePace ??= currentPace;
    _averagePace = (_averagePace! * 0.8) + (currentPace * 0.2); // Smooth average
    
    // Check if current pace is significantly slower than average
    if (currentPace < (_averagePace! * _slowPaceThreshold)) {
      return CheerleaderTrigger(
        type: TriggerType.paceDrop,
        data: {
          'currentPace': currentPace,
          'averagePace': _averagePace,
          'slowdownPercent': ((1 - (currentPace / _averagePace!)) * 100).round(),
        },
      );
    }
    
    return null;
  }

  /// Check for regular time-based check-ins
  CheerleaderTrigger? _checkTimeCheckTrigger(ActiveSessionRunning state) {
    final now = DateTime.now();
    
    if (_lastTimeCheck == null) {
      _lastTimeCheck = now;
      return null;
    }
    
    if (now.difference(_lastTimeCheck!).inSeconds >= _timeCheckIntervalSeconds) {
      _lastTimeCheck = now;
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
  ) {
    AppLogger.info('[AI_CONTEXT_DEBUG] Starting context assembly for trigger type: ${trigger.type}');
    AppLogger.info('[AI_CONTEXT_DEBUG] User data: ${user.toJson()}');
    AppLogger.info('[AI_CONTEXT_DEBUG] Session state - elapsed: ${state.elapsedSeconds}s, distance: ${state.distanceKm}km');
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
      'environment': <String, dynamic>{
        'timeOfDay': _getTimeOfDay(),
        'sessionPhase': _getSessionPhase(state),
      }
    };
    
    AppLogger.info('[AI_CONTEXT_DEBUG] Final assembled context:');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Trigger: ${context['trigger']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Session: ${context['session']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - User: ${context['user']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Environment: ${context['environment']}');
    AppLogger.info('[AI_CONTEXT_DEBUG] - Environment runtimeType: ${context['environment']?.runtimeType}');
    
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

  /// Resets service state for new session
  void reset() {
    _lastTriggerTime = null;
    _lastDistance = null;
    _lastTimeCheck = null;
    _averagePace = null;
    _triggerCount = 0;
    _hrBaseline = null;
    _lastHeartRateSpikeTime = null;
    AppLogger.info('[AI_CHEERLEADER] Service reset for new session');
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
