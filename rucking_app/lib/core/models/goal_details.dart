import 'goal.dart';
import 'goal_progress.dart';
import 'goal_schedule.dart';
import 'goal_message.dart';

class GoalDetails {
  final Goal goal;
  final GoalProgress? progress;
  final GoalSchedule? schedule;
  final List<GoalMessage> messages;

  GoalDetails({
    required this.goal,
    this.progress,
    this.schedule,
    required this.messages,
  });

  factory GoalDetails.fromJson(Map<String, dynamic> json) {
    final goalJson = json['goal'] as Map<String, dynamic>? ?? json;
    return GoalDetails(
      goal: Goal.fromJson(goalJson),
      progress: json['progress'] is Map<String, dynamic>
          ? GoalProgress.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      schedule: json['schedule'] is Map<String, dynamic>
          ? GoalSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
          : null,
      messages: (json['messages'] as List?)
              ?.map((e) =>
                  GoalMessage.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }
}
