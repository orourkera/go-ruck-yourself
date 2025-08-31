class PlanPersonalization {
  final String? why;
  final String? successDefinition;
  final int? trainingDaysPerWeek;
  final List<String>? preferredDays;
  final List<String>? challenges;
  final int? minimumSessionMinutes;
  final bool? unloadedOk;

  const PlanPersonalization({
    this.why,
    this.successDefinition,
    this.trainingDaysPerWeek,
    this.preferredDays,
    this.challenges,
    this.minimumSessionMinutes,
    this.unloadedOk,
  });

  PlanPersonalization copyWith({
    String? why,
    String? successDefinition,
    int? trainingDaysPerWeek,
    List<String>? preferredDays,
    List<String>? challenges,
    int? minimumSessionMinutes,
    bool? unloadedOk,
  }) {
    return PlanPersonalization(
      why: why ?? this.why,
      successDefinition: successDefinition ?? this.successDefinition,
      trainingDaysPerWeek: trainingDaysPerWeek ?? this.trainingDaysPerWeek,
      preferredDays: preferredDays ?? this.preferredDays,
      challenges: challenges ?? this.challenges,
      minimumSessionMinutes: minimumSessionMinutes ?? this.minimumSessionMinutes,
      unloadedOk: unloadedOk ?? this.unloadedOk,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'why': why,
      'successDefinition': successDefinition,
      'trainingDaysPerWeek': trainingDaysPerWeek,
      'preferredDays': preferredDays,
      'challenges': challenges,
      'minimumSessionMinutes': minimumSessionMinutes,
      'unloadedOk': unloadedOk,
    };
  }

  factory PlanPersonalization.fromJson(Map<String, dynamic> json) {
    return PlanPersonalization(
      why: json['why'] as String?,
      successDefinition: json['successDefinition'] as String?,
      trainingDaysPerWeek: json['trainingDaysPerWeek'] as int?,
      preferredDays: (json['preferredDays'] as List<dynamic>?)?.cast<String>(),
      challenges: (json['challenges'] as List<dynamic>?)?.cast<String>(),
      minimumSessionMinutes: json['minimumSessionMinutes'] as int?,
      unloadedOk: json['unloadedOk'] as bool?,
    );
  }

  bool get isComplete {
    return why != null &&
           successDefinition != null &&
           trainingDaysPerWeek != null &&
           preferredDays != null && preferredDays!.isNotEmpty &&
           challenges != null &&
           minimumSessionMinutes != null &&
           unloadedOk != null;
  }

  // Suggested responses
  static const whySuggestions = [
    'Energy',
    'Confidence', 
    'Pass an event',
    'Stress relief',
    'Weight loss',
    'Age strong',
  ];

  static const challengeSuggestions = [
    'Time',
    'Motivation',
    'Sleep',
    'Travel',
    'Weather',
    'Feet/skin issues',
    'Injury worries',
  ];

  static const weekdays = [
    'Monday',
    'Tuesday', 
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}