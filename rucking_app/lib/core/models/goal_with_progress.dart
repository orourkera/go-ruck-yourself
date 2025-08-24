import 'goal.dart';
import 'goal_progress.dart';

class GoalWithProgress {
  final Goal goal;
  final GoalProgress? progress;

  GoalWithProgress({
    required this.goal,
    this.progress,
  });

  factory GoalWithProgress.fromJson(Map<String, dynamic> json) {
    // Support either flat combined or nested structure
    final goalJson = json['goal'] is Map<String, dynamic>
        ? json['goal'] as Map<String, dynamic>
        : json;
    return GoalWithProgress(
      goal: Goal.fromJson(goalJson),
      progress: json['progress'] is Map<String, dynamic>
          ? GoalProgress.fromJson(json['progress'] as Map<String, dynamic>)
          : (json['latest_progress'] is Map<String, dynamic>
              ? GoalProgress.fromJson(json['latest_progress'] as Map<String, dynamic>)
              : null),
    );
  }
}
