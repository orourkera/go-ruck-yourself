class GoalSchedule {
  final String goalId;
  final bool? enabled;
  final String? status;
  final DateTime? nextRunAt;
  final DateTime? lastSentAt;
  final Map<String, dynamic>? rules;

  GoalSchedule({
    required this.goalId,
    this.enabled,
    this.status,
    this.nextRunAt,
    this.lastSentAt,
    this.rules,
  });

  factory GoalSchedule.fromJson(Map<String, dynamic> json) {
    return GoalSchedule(
      goalId: json['goal_id']?.toString() ?? json['goalId']?.toString() ?? '',
      enabled: json['enabled'] is bool
          ? json['enabled']
          : (json['enabled']?.toString() == 'true'),
      status: json['status']?.toString(),
      nextRunAt: _parseDate(json['next_run_at'] ?? json['nextRunAt']),
      lastSentAt: _parseDate(json['last_sent_at'] ?? json['lastSentAt']),
      rules: _ensureMap(json['schedule_rules_json'] ?? json['rules']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goal_id': goalId,
      if (enabled != null) 'enabled': enabled,
      if (status != null) 'status': status,
      if (nextRunAt != null) 'next_run_at': nextRunAt!.toIso8601String(),
      if (lastSentAt != null) 'last_sent_at': lastSentAt!.toIso8601String(),
      if (rules != null) 'schedule_rules_json': rules,
    };
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.tryParse(v.toString());
  }

  static Map<String, dynamic>? _ensureMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
