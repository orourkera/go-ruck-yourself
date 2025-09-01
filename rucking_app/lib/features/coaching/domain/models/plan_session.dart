import 'package:equatable/equatable.dart';

class PlanSession extends Equatable {
  final int id;
  final int userCoachingPlanId;
  final int? sessionId;
  final int plannedWeek;
  final String plannedSessionType;
  final String completionStatus;
  final double? planAdherenceScore;
  final String? notes;
  final DateTime? scheduledDate;
  final DateTime? completedDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlanSession({
    required this.id,
    required this.userCoachingPlanId,
    this.sessionId,
    required this.plannedWeek,
    required this.plannedSessionType,
    required this.completionStatus,
    this.planAdherenceScore,
    this.notes,
    this.scheduledDate,
    this.completedDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlanSession.fromJson(Map<String, dynamic> json) {
    return PlanSession(
      id: json['id'] as int,
      userCoachingPlanId: json['user_coaching_plan_id'] as int,
      sessionId: json['session_id'] as int?,
      plannedWeek: json['planned_week'] as int,
      plannedSessionType: json['planned_session_type'] as String,
      completionStatus: json['completion_status'] as String,
      planAdherenceScore: json['plan_adherence_score'] != null
          ? (json['plan_adherence_score'] as num).toDouble()
          : null,
      notes: json['notes'] as String?,
      scheduledDate: json['scheduled_date'] != null
          ? DateTime.parse(json['scheduled_date'] as String)
          : null,
      completedDate: json['completed_date'] != null
          ? DateTime.parse(json['completed_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_coaching_plan_id': userCoachingPlanId,
      'session_id': sessionId,
      'planned_week': plannedWeek,
      'planned_session_type': plannedSessionType,
      'completion_status': completionStatus,
      'plan_adherence_score': planAdherenceScore,
      'notes': notes,
      'scheduled_date': scheduledDate?.toIso8601String().split('T')[0],
      'completed_date': completedDate?.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PlanSession copyWith({
    int? id,
    int? userCoachingPlanId,
    int? sessionId,
    int? plannedWeek,
    String? plannedSessionType,
    String? completionStatus,
    double? planAdherenceScore,
    String? notes,
    DateTime? scheduledDate,
    DateTime? completedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PlanSession(
      id: id ?? this.id,
      userCoachingPlanId: userCoachingPlanId ?? this.userCoachingPlanId,
      sessionId: sessionId ?? this.sessionId,
      plannedWeek: plannedWeek ?? this.plannedWeek,
      plannedSessionType: plannedSessionType ?? this.plannedSessionType,
      completionStatus: completionStatus ?? this.completionStatus,
      planAdherenceScore: planAdherenceScore ?? this.planAdherenceScore,
      notes: notes ?? this.notes,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      completedDate: completedDate ?? this.completedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if session is planned
  bool get isPlanned => completionStatus == 'planned';

  /// Check if session is completed
  bool get isCompleted => completionStatus == 'completed';

  /// Check if session is skipped
  bool get isSkipped => completionStatus == 'skipped';

  /// Check if session is missed
  bool get isMissed => completionStatus == 'missed';

  /// Check if session is overdue
  bool get isOverdue {
    if (scheduledDate == null || isCompleted || isSkipped) return false;
    return DateTime.now().isAfter(scheduledDate!.add(Duration(days: 1)));
  }

  /// Get adherence status description
  String get adherenceDescription {
    if (planAdherenceScore == null) return 'Not completed';
    if (planAdherenceScore! >= 0.9) return 'Excellent adherence';
    if (planAdherenceScore! >= 0.7) return 'Good adherence';
    if (planAdherenceScore! >= 0.5) return 'Moderate adherence';
    return 'Poor adherence';
  }

  @override
  List<Object?> get props => [
        id,
        userCoachingPlanId,
        sessionId,
        plannedWeek,
        plannedSessionType,
        completionStatus,
        planAdherenceScore,
        notes,
        scheduledDate,
        completedDate,
        createdAt,
        updatedAt,
      ];
}

enum SessionCompletionStatus {
  planned('planned', 'Planned'),
  completed('completed', 'Completed'),
  skipped('skipped', 'Skipped'),
  missed('missed', 'Missed');

  const SessionCompletionStatus(this.value, this.displayName);

  final String value;
  final String displayName;

  static SessionCompletionStatus fromString(String value) {
    return SessionCompletionStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => SessionCompletionStatus.planned,
    );
  }
}
