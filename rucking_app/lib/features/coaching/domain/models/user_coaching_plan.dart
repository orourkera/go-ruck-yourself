import 'package:equatable/equatable.dart';
import 'coaching_plan_template.dart';

class UserCoachingPlan extends Equatable {
  final int id;
  final String userId;
  final int coachingPlanId;
  final String coachingPersonality;
  final DateTime startDate;
  final int currentWeek;
  final String currentStatus;
  final Map<String, dynamic> planModifications;
  final DateTime createdAt;
  final DateTime updatedAt;
  final CoachingPlanTemplate? template;

  const UserCoachingPlan({
    required this.id,
    required this.userId,
    required this.coachingPlanId,
    required this.coachingPersonality,
    required this.startDate,
    required this.currentWeek,
    required this.currentStatus,
    required this.planModifications,
    required this.createdAt,
    required this.updatedAt,
    this.template,
  });

  factory UserCoachingPlan.fromJson(Map<String, dynamic> json) {
    return UserCoachingPlan(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      coachingPlanId: json['coaching_plan_id'] as int,
      coachingPersonality: json['coaching_personality'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      currentWeek: json['current_week'] as int,
      currentStatus: json['current_status'] as String,
      planModifications: Map<String, dynamic>.from(json['plan_modifications'] ?? {}),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      template: json['coaching_plan_templates'] != null
          ? CoachingPlanTemplate.fromJson(json['coaching_plan_templates'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'coaching_plan_id': coachingPlanId,
      'coaching_personality': coachingPersonality,
      'start_date': startDate.toIso8601String().split('T')[0], // Date only
      'current_week': currentWeek,
      'current_status': currentStatus,
      'plan_modifications': planModifications,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserCoachingPlan copyWith({
    int? id,
    String? userId,
    int? coachingPlanId,
    String? coachingPersonality,
    DateTime? startDate,
    int? currentWeek,
    String? currentStatus,
    Map<String, dynamic>? planModifications,
    DateTime? createdAt,
    DateTime? updatedAt,
    CoachingPlanTemplate? template,
  }) {
    return UserCoachingPlan(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      coachingPlanId: coachingPlanId ?? this.coachingPlanId,
      coachingPersonality: coachingPersonality ?? this.coachingPersonality,
      startDate: startDate ?? this.startDate,
      currentWeek: currentWeek ?? this.currentWeek,
      currentStatus: currentStatus ?? this.currentStatus,
      planModifications: planModifications ?? this.planModifications,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      template: template ?? this.template,
    );
  }

  /// Calculate weeks elapsed since plan start
  int get weeksElapsed {
    final now = DateTime.now();
    final daysDiff = now.difference(startDate).inDays;
    return ((daysDiff / 7).floor() + 1).clamp(1, template?.durationWeeks ?? 999);
  }

  /// Calculate progress percentage
  double get progressPercent {
    if (template == null) return 0.0;
    return (weeksElapsed / template!.durationWeeks * 100).clamp(0.0, 100.0);
  }

  /// Check if plan is active
  bool get isActive => currentStatus == 'active';

  /// Check if plan is completed
  bool get isCompleted => currentStatus == 'completed';

  /// Check if plan is paused
  bool get isPaused => currentStatus == 'paused';

  @override
  List<Object?> get props => [
        id,
        userId,
        coachingPlanId,
        coachingPersonality,
        startDate,
        currentWeek,
        currentStatus,
        planModifications,
        createdAt,
        updatedAt,
        template,
      ];
}

enum CoachingPersonality {
  drillSergeant('drill_sergeant', 'Drill Sergeant'),
  supportiveFriend('supportive_friend', 'Supportive Friend'),
  dataNerd('data_nerd', 'Data Nerd'),
  minimalist('minimalist', 'Minimalist');

  const CoachingPersonality(this.value, this.displayName);

  final String value;
  final String displayName;

  static CoachingPersonality fromString(String value) {
    return CoachingPersonality.values.firstWhere(
      (personality) => personality.value == value,
      orElse: () => CoachingPersonality.supportiveFriend,
    );
  }
}

enum PlanStatus {
  active('active', 'Active'),
  paused('paused', 'Paused'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const PlanStatus(this.value, this.displayName);

  final String value;
  final String displayName;

  static PlanStatus fromString(String value) {
    return PlanStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => PlanStatus.active,
    );
  }
}
