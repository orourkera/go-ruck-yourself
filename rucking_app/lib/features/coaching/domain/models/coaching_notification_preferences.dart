import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// User preferences for AI coaching notifications
class CoachingNotificationPreferences extends Equatable {
  /// Whether coaching notifications are enabled
  final bool enableCoaching;
  
  /// Preferred days of week for ruck reminders (0=Sunday, 6=Saturday)
  final List<int> preferredDays;
  
  /// Preferred time for reminder notifications
  final TimeOfDay reminderTime;
  
  /// Hours before planned session to send reminder
  final int hoursBeforeSession;
  
  /// Enable motivational/encouragement notifications
  final bool enableMotivational;
  
  /// Enable missed session recovery notifications
  final bool enableMissedSession;
  
  /// Enable progress celebration notifications
  final bool enableProgressCelebration;
  
  /// Enable weather-based suggestions
  final bool enableWeatherSuggestions;
  
  /// Enable streak protection notifications
  final bool enableStreakProtection;
  
  /// Coaching tone matching user's selected personality
  final String coachingTone;
  
  /// Maximum notifications per day (prevent spam)
  final int maxNotificationsPerDay;
  
  /// Quiet hours - no notifications during this time
  final TimeOfDay? quietHoursStart;
  final TimeOfDay? quietHoursEnd;

  const CoachingNotificationPreferences({
    this.enableCoaching = true,
    this.preferredDays = const [1, 3, 5], // Mon, Wed, Fri default
    this.reminderTime = const TimeOfDay(hour: 18, minute: 0), // 6 PM default
    this.hoursBeforeSession = 1,
    this.enableMotivational = true,
    this.enableMissedSession = true,
    this.enableProgressCelebration = true,
    this.enableWeatherSuggestions = false, // Off by default (requires weather API)
    this.enableStreakProtection = true,
    this.coachingTone = 'supportive_friend',
    this.maxNotificationsPerDay = 3,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  /// Creates preferences from JSON (API response)
  factory CoachingNotificationPreferences.fromJson(Map<String, dynamic> json) {
    return CoachingNotificationPreferences(
      enableCoaching: json['enable_coaching'] ?? true,
      preferredDays: (json['preferred_days'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList() ?? [1, 3, 5],
      reminderTime: _parseTimeOfDay(json['reminder_time']) ?? const TimeOfDay(hour: 18, minute: 0),
      hoursBeforeSession: json['hours_before_session'] ?? 1,
      enableMotivational: json['enable_motivational'] ?? true,
      enableMissedSession: json['enable_missed_session'] ?? true,
      enableProgressCelebration: json['enable_progress_celebration'] ?? true,
      enableWeatherSuggestions: json['enable_weather_suggestions'] ?? false,
      enableStreakProtection: json['enable_streak_protection'] ?? true,
      coachingTone: json['coaching_tone'] ?? 'supportive_friend',
      maxNotificationsPerDay: json['max_notifications_per_day'] ?? 3,
      quietHoursStart: _parseTimeOfDay(json['quiet_hours_start']),
      quietHoursEnd: _parseTimeOfDay(json['quiet_hours_end']),
    );
  }

  /// Converts preferences to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'enable_coaching': enableCoaching,
      'preferred_days': preferredDays,
      'reminder_time': _formatTimeOfDay(reminderTime),
      'hours_before_session': hoursBeforeSession,
      'enable_motivational': enableMotivational,
      'enable_missed_session': enableMissedSession,
      'enable_progress_celebration': enableProgressCelebration,
      'enable_weather_suggestions': enableWeatherSuggestions,
      'enable_streak_protection': enableStreakProtection,
      'coaching_tone': coachingTone,
      'max_notifications_per_day': maxNotificationsPerDay,
      'quiet_hours_start': quietHoursStart != null ? _formatTimeOfDay(quietHoursStart!) : null,
      'quiet_hours_end': quietHoursEnd != null ? _formatTimeOfDay(quietHoursEnd!) : null,
    };
  }

  /// Helper to parse TimeOfDay from "HH:MM" string
  static TimeOfDay? _parseTimeOfDay(String? timeString) {
    if (timeString == null) return null;
    final parts = timeString.split(':');
    if (parts.length != 2) return null;
    
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Helper to format TimeOfDay as "HH:MM" string
  static String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Gets display name for coaching tone
  String get coachingToneDisplayName {
    switch (coachingTone) {
      case 'drill_sergeant':
        return 'Drill Sergeant';
      case 'supportive_friend':
        return 'Supportive Friend';
      case 'data_nerd':
        return 'Data Nerd';
      case 'minimalist':
        return 'Minimalist';
      default:
        return 'Supportive Friend';
    }
  }

  /// Gets list of preferred day names for display
  List<String> get preferredDayNames {
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return preferredDays.map((day) => dayNames[day]).toList();
  }

  /// Checks if given day is a preferred day
  bool isPreferredDay(DateTime date) {
    return preferredDays.contains(date.weekday % 7); // Convert to 0-6 format
  }

  /// Checks if current time is in quiet hours
  bool isInQuietHours(TimeOfDay currentTime) {
    if (quietHoursStart == null || quietHoursEnd == null) return false;
    
    final current = currentTime.hour * 60 + currentTime.minute;
    final start = quietHoursStart!.hour * 60 + quietHoursStart!.minute;
    final end = quietHoursEnd!.hour * 60 + quietHoursEnd!.minute;
    
    if (start <= end) {
      // Same day quiet hours (e.g., 10:00 - 22:00)
      return current >= start && current <= end;
    } else {
      // Overnight quiet hours (e.g., 22:00 - 06:00)
      return current >= start || current <= end;
    }
  }

  /// Creates a copy with updated values
  CoachingNotificationPreferences copyWith({
    bool? enableCoaching,
    List<int>? preferredDays,
    TimeOfDay? reminderTime,
    int? hoursBeforeSession,
    bool? enableMotivational,
    bool? enableMissedSession,
    bool? enableProgressCelebration,
    bool? enableWeatherSuggestions,
    bool? enableStreakProtection,
    String? coachingTone,
    int? maxNotificationsPerDay,
    TimeOfDay? quietHoursStart,
    TimeOfDay? quietHoursEnd,
  }) {
    return CoachingNotificationPreferences(
      enableCoaching: enableCoaching ?? this.enableCoaching,
      preferredDays: preferredDays ?? this.preferredDays,
      reminderTime: reminderTime ?? this.reminderTime,
      hoursBeforeSession: hoursBeforeSession ?? this.hoursBeforeSession,
      enableMotivational: enableMotivational ?? this.enableMotivational,
      enableMissedSession: enableMissedSession ?? this.enableMissedSession,
      enableProgressCelebration: enableProgressCelebration ?? this.enableProgressCelebration,
      enableWeatherSuggestions: enableWeatherSuggestions ?? this.enableWeatherSuggestions,
      enableStreakProtection: enableStreakProtection ?? this.enableStreakProtection,
      coachingTone: coachingTone ?? this.coachingTone,
      maxNotificationsPerDay: maxNotificationsPerDay ?? this.maxNotificationsPerDay,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
    );
  }

  @override
  List<Object?> get props => [
    enableCoaching,
    preferredDays,
    reminderTime,
    hoursBeforeSession,
    enableMotivational,
    enableMissedSession,
    enableProgressCelebration,
    enableWeatherSuggestions,
    enableStreakProtection,
    coachingTone,
    maxNotificationsPerDay,
    quietHoursStart,
    quietHoursEnd,
  ];
}

/// Types of coaching notifications
enum CoachingNotificationType {
  sessionReminder('session_reminder', 'Session Reminder'),
  motivational('motivational', 'Motivational'),
  missedSession('missed_session', 'Missed Session'),
  progressCelebration('progress_celebration', 'Progress Celebration'),
  weatherSuggestion('weather_suggestion', 'Weather Suggestion'),
  streakProtection('streak_protection', 'Streak Protection'),
  planMilestone('plan_milestone', 'Plan Milestone');

  const CoachingNotificationType(this.value, this.displayName);
  
  final String value;
  final String displayName;
}

/// Available coaching tones with sample messages
enum CoachingTone {
  drillSergeant('drill_sergeant', 'Drill Sergeant', 'Direct, challenging, no-nonsense', 
    'Drop and give me 20! No excuses today - you committed to this plan!'),
  supportiveFriend('supportive_friend', 'Supportive Friend', 'Encouraging, empathetic, understanding',
    'You\'ve got this! Remember why you started - every step matters.'),
  dataNerd('data_nerd', 'Data Nerd', 'Analytical, metrics-focused, optimization-oriented',
    'Your pace improved 12% this week. Let\'s dial in your Zone 2 training.'),
  minimalist('minimalist', 'Minimalist', 'Brief, actionable, efficient',
    '2.5 miles. 20 lbs. Go.');

  const CoachingTone(this.value, this.displayName, this.description, this.sampleMessage);
  
  final String value;
  final String displayName;
  final String description;
  final String sampleMessage;
  
  static CoachingTone fromValue(String value) {
    return CoachingTone.values.firstWhere(
      (tone) => tone.value == value,
      orElse: () => CoachingTone.supportiveFriend,
    );
  }
}