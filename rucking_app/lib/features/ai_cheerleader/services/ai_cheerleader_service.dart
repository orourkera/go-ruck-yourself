import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/core/models/user.dart';

/// Service for detecting AI Cheerleader triggers and assembling context
class AICheerleaderService {
  static const int _milestoneIntervalMeters = 1000; // Every 1km
  static const int _timeCheckIntervalSeconds = 600; // Every 10 minutes
  static const double _slowPaceThreshold = 0.7; // 70% of average pace = slow
  static const int _minimumTriggerIntervalSeconds = 120; // Min 2 minutes between triggers
  
  DateTime? _lastTriggerTime;
  double? _lastDistance;
  DateTime? _lastTimeCheck;
  double? _averagePace;
  int _triggerCount = 0;

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

    // 2. Pace Drop Trigger
    final paceTrigger = _checkPaceDropTrigger(state);
    if (paceTrigger != null) {
      _lastTriggerTime = now;
      _triggerCount++;
      return paceTrigger;
    }

    // 3. Time Check-in Trigger
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

  /// Assembles comprehensive context for AI text generation
  Map<String, dynamic> assembleContext(
    ActiveSessionRunning state,
    CheerleaderTrigger trigger,
    User user,
    String personality,
    bool explicitContent,
  ) {
    return {
      'trigger': {
        'type': trigger.type.name,
        'data': trigger.data,
        'triggerCount': _triggerCount,
      },
      'session': {
        'elapsedTime': {
          'elapsedMinutes': state.elapsedSeconds ~/ 60,
          'elapsedSeconds': state.elapsedSeconds,
          'formatted': _formatDuration(Duration(seconds: state.elapsedSeconds)),
        },
        'distance': {
          'distanceKm': state.distanceKm,
          'distanceMeters': state.distanceKm * 1000,
          'distanceMiles': state.distanceKm * 0.621371,
        },
        'pace': {
          'pace': state.pace,
          'average': _averagePace,
        },
        'performance': {
          'calories': state.calories,
          'heartRate': state.latestHeartRate,
          'elevationGain': state.elevationGain,
        },
        'plannedDuration': state.plannedDuration,
        'progress': state.plannedDuration != null 
          ? (state.elapsedSeconds / state.plannedDuration!) * 100 
          : null,
      },
      'user': {
        'username': user.username,
        'preferMetric': user.preferMetric,
        'totalSessions': user.stats?.totalRucks ?? 0,
        'totalDistanceKm': user.stats?.totalDistanceKm ?? 0.0,
        'longestSessionMinutes': 0, // TODO: Add longest session tracking
      },
      'settings': {
        'personality': personality,
        'explicitContent': explicitContent,
      },
      'environment': {
        'timeOfDay': _getTimeOfDay(),
        'sessionPhase': _getSessionPhase(state),
      }
    };
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
    AppLogger.info('[AI_CHEERLEADER] Service reset for new session');
  }
}

enum TriggerType {
  milestone,
  paceDrop,
  timeCheckIn,
  sessionComplete,
  manualRequest,
}

class CheerleaderTrigger {
  final TriggerType type;
  final Map<String, dynamic> data;

  CheerleaderTrigger({
    required this.type,
    required this.data,
  });
}
