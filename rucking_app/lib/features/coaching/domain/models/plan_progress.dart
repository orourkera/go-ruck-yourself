import 'package:equatable/equatable.dart';
import 'plan_session.dart';

class PlanProgress extends Equatable {
  final int userCoachingPlanId;
  final int currentWeek;
  final double progressPercent;
  final int totalWeeks;
  final int completedSessions;
  final int totalSessions;
  final double overallAdherence;
  final List<WeeklyProgress> weeklyProgress;
  final int currentStreak;
  final String? nextMilestone;
  final PlanSession? nextSession;

  const PlanProgress({
    required this.userCoachingPlanId,
    required this.currentWeek,
    required this.progressPercent,
    required this.totalWeeks,
    required this.completedSessions,
    required this.totalSessions,
    required this.overallAdherence,
    required this.weeklyProgress,
    required this.currentStreak,
    this.nextMilestone,
    this.nextSession,
  });

  factory PlanProgress.fromJson(Map<String, dynamic> json) {
    return PlanProgress(
      userCoachingPlanId: json['user_coaching_plan_id'] as int,
      currentWeek: json['current_week'] as int,
      progressPercent: (json['progress_percent'] as num).toDouble(),
      totalWeeks: json['total_weeks'] as int,
      completedSessions: json['completed_sessions'] as int,
      totalSessions: json['total_sessions'] as int,
      overallAdherence: (json['overall_adherence'] as num).toDouble(),
      weeklyProgress: (json['weekly_progress'] as List)
          .map((weekData) => WeeklyProgress.fromJson(weekData))
          .toList(),
      currentStreak: json['current_streak'] as int,
      nextMilestone: json['next_milestone'] as String?,
      nextSession: json['next_session'] != null
          ? PlanSession.fromJson(json['next_session'])
          : null,
    );
  }

  /// Get progress status description
  String get progressStatus {
    if (progressPercent == 100.0) return 'Plan Completed!';
    if (progressPercent >= 75.0) return 'Almost there!';
    if (progressPercent >= 50.0) return 'Halfway done!';
    if (progressPercent >= 25.0) return 'Making progress!';
    return 'Just getting started!';
  }

  /// Get adherence status description
  String get adherenceStatus {
    if (overallAdherence >= 0.9) return 'Excellent adherence';
    if (overallAdherence >= 0.7) return 'Good adherence';
    if (overallAdherence >= 0.5) return 'Moderate adherence';
    return 'Need improvement';
  }

  /// Get streak description
  String get streakDescription {
    if (currentStreak == 0) return 'No current streak';
    if (currentStreak == 1) return '1 session streak';
    return '$currentStreak session streak';
  }

  @override
  List<Object?> get props => [
        userCoachingPlanId,
        currentWeek,
        progressPercent,
        totalWeeks,
        completedSessions,
        totalSessions,
        overallAdherence,
        weeklyProgress,
        currentStreak,
        nextMilestone,
        nextSession,
      ];
}

class WeeklyProgress extends Equatable {
  final int week;
  final int completedSessions;
  final int totalSessions;
  final double weeklyAdherence;

  const WeeklyProgress({
    required this.week,
    required this.completedSessions,
    required this.totalSessions,
    required this.weeklyAdherence,
  });

  factory WeeklyProgress.fromJson(Map<String, dynamic> json) {
    return WeeklyProgress(
      week: json['week'] as int,
      completedSessions: json['completed_sessions'] as int,
      totalSessions: json['total_sessions'] as int,
      weeklyAdherence: (json['weekly_adherence'] as num).toDouble(),
    );
  }

  /// Get completion percentage for this week
  double get completionPercent {
    if (totalSessions == 0) return 0.0;
    return (completedSessions / totalSessions * 100).clamp(0.0, 100.0);
  }

  /// Check if week is fully completed
  bool get isCompleted => completedSessions == totalSessions;

  /// Get week status description
  String get statusDescription {
    if (isCompleted) return 'Week completed';
    if (completedSessions > 0) return 'In progress';
    return 'Not started';
  }

  @override
  List<Object?> get props => [
        week,
        completedSessions,
        totalSessions,
        weeklyAdherence,
      ];
}
