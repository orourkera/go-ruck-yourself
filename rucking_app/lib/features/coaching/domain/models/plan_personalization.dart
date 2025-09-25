class PlanPersonalization {
  final List<String>? why;
  final String? successDefinition;
  final int? trainingDaysPerWeek;
  final List<String>? preferredDays;
  final List<String>? challenges;
  final int? minimumSessionMinutes;
  final bool? unloadedOk;
  final int? streakTargetDays;
  final int? streakTargetRucks;
  final int? streakTimeframeDays;
  final String? equipmentType;
  final double? equipmentWeight;
  // Notification preferences
  final String? preferredNotificationTime;
  final bool? enableNotifications;
  // Custom fields from plan-specific questions
  final Map<String, dynamic>? customResponses;

  const PlanPersonalization({
    this.why,
    this.successDefinition,
    this.trainingDaysPerWeek,
    this.preferredDays,
    this.challenges,
    this.minimumSessionMinutes,
    this.unloadedOk,
    this.streakTargetDays,
    this.streakTargetRucks,
    this.streakTimeframeDays,
    this.equipmentType,
    this.equipmentWeight,
    this.preferredNotificationTime,
    this.enableNotifications,
    this.customResponses,
  });

  PlanPersonalization copyWith({
    List<String>? why,
    String? successDefinition,
    int? trainingDaysPerWeek,
    List<String>? preferredDays,
    List<String>? challenges,
    int? minimumSessionMinutes,
    bool? unloadedOk,
    int? streakTargetDays,
    int? streakTargetRucks,
    int? streakTimeframeDays,
    String? equipmentType,
    double? equipmentWeight,
    String? preferredNotificationTime,
    bool? enableNotifications,
    Map<String, dynamic>? customResponses,
  }) {
    return PlanPersonalization(
      why: why ?? this.why,
      successDefinition: successDefinition ?? this.successDefinition,
      trainingDaysPerWeek: trainingDaysPerWeek ?? this.trainingDaysPerWeek,
      preferredDays: preferredDays ?? this.preferredDays,
      challenges: challenges ?? this.challenges,
      minimumSessionMinutes:
          minimumSessionMinutes ?? this.minimumSessionMinutes,
      unloadedOk: unloadedOk ?? this.unloadedOk,
      streakTargetDays: streakTargetDays ?? this.streakTargetDays,
      streakTargetRucks: streakTargetRucks ?? this.streakTargetRucks,
      streakTimeframeDays: streakTimeframeDays ?? this.streakTimeframeDays,
      equipmentType: equipmentType ?? this.equipmentType,
      equipmentWeight: equipmentWeight ?? this.equipmentWeight,
      preferredNotificationTime: preferredNotificationTime ?? this.preferredNotificationTime,
      enableNotifications: enableNotifications ?? this.enableNotifications,
      customResponses: customResponses ?? this.customResponses,
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
      'streakTargetDays': streakTargetDays,
      'streakTargetRucks': streakTargetRucks,
      'streakTimeframeDays': streakTimeframeDays,
      'equipmentType': equipmentType,
      'equipmentWeight': equipmentWeight,
      'preferredNotificationTime': preferredNotificationTime,
      'enableNotifications': enableNotifications,
      'customResponses': customResponses,
    };
  }

  factory PlanPersonalization.fromJson(Map<String, dynamic> json) {
    return PlanPersonalization(
      why: (json['why'] as List<dynamic>?)?.cast<String>(),
      successDefinition: json['successDefinition'] as String?,
      trainingDaysPerWeek: json['trainingDaysPerWeek'] as int?,
      preferredDays: (json['preferredDays'] as List<dynamic>?)?.cast<String>(),
      challenges: (json['challenges'] as List<dynamic>?)?.cast<String>(),
      minimumSessionMinutes: json['minimumSessionMinutes'] as int?,
      unloadedOk: json['unloadedOk'] as bool?,
      streakTargetDays: json['streakTargetDays'] as int?,
      streakTargetRucks: json['streakTargetRucks'] as int?,
      streakTimeframeDays: json['streakTimeframeDays'] as int?,
      equipmentType: json['equipmentType'] as String?,
      equipmentWeight: (json['equipmentWeight'] as num?)?.toDouble(),
      preferredNotificationTime: json['preferredNotificationTime'] as String?,
      enableNotifications: json['enableNotifications'] as bool?,
      customResponses: json['customResponses'] as Map<String, dynamic>?,
    );
  }

  bool get isComplete {
    return why != null &&
        why!.isNotEmpty &&
        successDefinition != null &&
        trainingDaysPerWeek != null &&
        preferredDays != null &&
        preferredDays!.isNotEmpty &&
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
