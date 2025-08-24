class GoalProgress {
  final String goalId;
  final num? currentValue;
  final num? progressPercent;
  final DateTime? lastEvaluatedAt;
  final Map<String, dynamic>? breakdown;

  GoalProgress({
    required this.goalId,
    this.currentValue,
    this.progressPercent,
    this.lastEvaluatedAt,
    this.breakdown,
  });

  factory GoalProgress.fromJson(Map<String, dynamic> json) {
    return GoalProgress(
      goalId: json['goal_id']?.toString() ?? json['goalId']?.toString() ?? '',
      currentValue: json['current_value'] ?? json['currentValue'],
      progressPercent: json['progress_percent'] ?? json['progressPercent'],
      lastEvaluatedAt: _parseDate(json['last_evaluated_at'] ?? json['lastEvaluatedAt']),
      breakdown: _ensureMap(json['breakdown_json'] ?? json['breakdown']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goal_id': goalId,
      if (currentValue != null) 'current_value': currentValue,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (lastEvaluatedAt != null) 'last_evaluated_at': lastEvaluatedAt!.toIso8601String(),
      if (breakdown != null) 'breakdown_json': breakdown,
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
