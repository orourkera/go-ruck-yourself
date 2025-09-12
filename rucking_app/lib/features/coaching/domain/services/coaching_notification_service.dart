import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_notification_preferences.dart';
import 'package:rucking_app/features/coaching/domain/services/weather_coaching_service.dart';
import 'package:rucking_app/features/coaching/domain/services/streak_protection_service.dart';
import 'package:rucking_app/features/coaching/domain/services/coaching_message_generator.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service responsible for scheduling and managing AI coaching notifications
class CoachingNotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final ApiClient _apiClient;
  final WeatherCoachingService _weatherService;
  final StreakProtectionService _streakService;
  final CoachingMessageGenerator _messageGenerator;
  Timer? _dailyScheduleTimer;

  static const String _channelId = 'coaching_notifications';
  static const String _channelName = 'AI Coaching';
  static const String _channelDescription =
      'Personalized AI coaching reminders and motivation';

  CoachingNotificationService(
    this._apiClient,
    this._weatherService,
    this._streakService,
    this._messageGenerator,
  );

  /// Initialize the notification service
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    await _createNotificationChannel();
    await _requestPermissions();

    // Start daily scheduling timer
    _startDailyScheduler();

    AppLogger.info('CoachingNotificationService initialized');
  }

  /// Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  /// Schedule all notifications based on user preferences
  Future<void> scheduleNotifications(
      CoachingNotificationPreferences preferences) async {
    if (!preferences.enableCoaching) {
      await cancelAllNotifications();
      return;
    }

    try {
      // Cancel existing notifications
      await cancelAllNotifications();

      // Get coaching plan data
      final coachingPlan = await _getCoachingPlan();
      if (coachingPlan == null) {
        AppLogger.warning(
            'No coaching plan found, skipping notification scheduling');
        return;
      }

      // Schedule different types of notifications
      await _scheduleSessionReminders(preferences, coachingPlan);
      await _scheduleMotivationalNotifications(preferences, coachingPlan);
      await _scheduleMissedSessionChecks(preferences, coachingPlan);
      await _scheduleProgressCelebrations(preferences, coachingPlan);
      await _scheduleStreakProtection(preferences, coachingPlan);

      if (preferences.enableWeatherSuggestions) {
        await _scheduleWeatherSuggestions(preferences, coachingPlan);
      }

      AppLogger.info('Coaching notifications scheduled successfully');
    } catch (e) {
      AppLogger.error('Error scheduling coaching notifications: $e');
    }
  }

  /// Schedule session reminder notifications
  Future<void> _scheduleSessionReminders(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    final nextSessions = coachingPlan['next_sessions'] as List<dynamic>? ?? [];

    for (int i = 0; i < math.min(nextSessions.length, 7); i++) {
      final session = nextSessions[i] as Map<String, dynamic>;
      final sessionDate = DateTime.tryParse(session['scheduled_date'] ?? '');

      if (sessionDate == null) continue;

      // Check if it's a preferred day
      if (!preferences.isPreferredDay(sessionDate)) continue;

      final reminderTime =
          sessionDate.subtract(Duration(hours: preferences.hoursBeforeSession));

      // Don't schedule past reminders
      if (reminderTime.isBefore(DateTime.now())) continue;

      // Check quiet hours
      final reminderTimeOfDay = TimeOfDay.fromDateTime(reminderTime);
      if (preferences.isInQuietHours(reminderTimeOfDay)) continue;

      final message = await _generateCoachingMessage(
          CoachingNotificationType.sessionReminder,
          preferences.coachingTone,
          {'session': session, 'plan': coachingPlan});

      await _scheduleNotification(
        id: 1000 + i,
        title: 'Ruck Session Reminder',
        body: message,
        scheduledDate: reminderTime,
        type: CoachingNotificationType.sessionReminder,
      );
    }
  }

  /// Schedule motivational notifications
  Future<void> _scheduleMotivationalNotifications(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    if (!preferences.enableMotivational) return;

    final now = DateTime.now();

    // Schedule motivational messages for the next 7 days
    for (int day = 1; day <= 7; day++) {
      final targetDate = now.add(Duration(days: day));

      // Skip if not a preferred day
      if (!preferences.isPreferredDay(targetDate)) continue;

      // Schedule at random time during the day (avoiding quiet hours)
      final scheduledTime = _getRandomMotivationalTime(targetDate, preferences);
      if (scheduledTime == null) continue;

      final message = await _generateCoachingMessage(
          CoachingNotificationType.motivational,
          preferences.coachingTone,
          {'plan': coachingPlan, 'day': day});

      await _scheduleNotification(
        id: 2000 + day,
        title: 'Daily Motivation',
        body: message,
        scheduledDate: scheduledTime,
        type: CoachingNotificationType.motivational,
      );
    }
  }

  /// Schedule missed session recovery notifications
  Future<void> _scheduleMissedSessionChecks(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    if (!preferences.enableMissedSession) return;

    // Check for missed sessions daily at 8 PM
    final now = DateTime.now();
    for (int day = 1; day <= 7; day++) {
      final checkDate = DateTime(
        now.year,
        now.month,
        now.day + day,
        20, // 8 PM
        0,
      );

      // Skip if in quiet hours
      final checkTime = TimeOfDay.fromDateTime(checkDate);
      if (preferences.isInQuietHours(checkTime)) continue;

      await _scheduleNotification(
        id: 3000 + day,
        title: 'Session Check-in',
        body: 'Checking in on your ruck plan...',
        scheduledDate: checkDate,
        type: CoachingNotificationType.missedSession,
        payload: {'check_type': 'missed_session'},
      );
    }
  }

  /// Schedule progress celebration notifications
  Future<void> _scheduleProgressCelebrations(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    if (!preferences.enableProgressCelebration) return;

    final milestones = coachingPlan['milestones'] as List<dynamic>? ?? [];

    for (final milestone in milestones) {
      final milestoneDate = DateTime.tryParse(milestone['target_date'] ?? '');
      if (milestoneDate == null || milestoneDate.isBefore(DateTime.now()))
        continue;

      // Schedule celebration 1 day after milestone
      final celebrationDate = milestoneDate.add(const Duration(days: 1));

      await _scheduleNotification(
        id: 4000 + milestone['id'].hashCode % 1000,
        title: 'Milestone Achievement!',
        body: 'Time to celebrate your progress!',
        scheduledDate: celebrationDate,
        type: CoachingNotificationType.progressCelebration,
        payload: {'milestone': milestone},
      );
    }
  }

  /// Schedule streak protection notifications
  Future<void> _scheduleStreakProtection(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    if (!preferences.enableStreakProtection) return;

    try {
      // Get current streak info
      final streakInfo = await _streakService.getStreakInfo();
      if (streakInfo == null) return;

      // Only schedule if streak protection is needed
      if (!_streakService.shouldSendStreakProtection(streakInfo, preferences)) {
        return;
      }

      // Generate streak protection recommendation
      final tone = CoachingTone.fromValue(preferences.coachingTone);
      final recommendation =
          _streakService.generateProtectionRecommendation(streakInfo, tone);

      // Schedule notification based on urgency
      final now = DateTime.now();
      late DateTime notificationTime;

      switch (recommendation.urgency) {
        case StreakUrgency.critical:
          // Send within 1 hour for critical situations
          notificationTime = now.add(const Duration(hours: 1));
          break;
        case StreakUrgency.high:
          // Send in 2-4 hours for high urgency
          notificationTime =
              now.add(Duration(hours: 2 + math.Random().nextInt(3)));
          break;
        case StreakUrgency.medium:
          // Send at 6 PM today or tomorrow
          notificationTime = DateTime(now.year, now.month, now.day, 18, 0);
          if (notificationTime.isBefore(now)) {
            notificationTime = notificationTime.add(const Duration(days: 1));
          }
          break;
        case StreakUrgency.low:
          // Send as regular motivational notification
          notificationTime =
              now.add(Duration(hours: 4 + math.Random().nextInt(8)));
          break;
      }

      // Check quiet hours
      final timeOfDay = TimeOfDay.fromDateTime(notificationTime);
      if (preferences.isInQuietHours(timeOfDay)) {
        // Adjust to just after quiet hours end
        notificationTime = DateTime(
          notificationTime.year,
          notificationTime.month,
          notificationTime.day,
          preferences.quietHoursEnd?.hour ?? 8,
          preferences.quietHoursEnd?.minute ?? 0,
        );

        // If that's in the past, schedule for next day
        if (notificationTime.isBefore(now)) {
          notificationTime = notificationTime.add(const Duration(days: 1));
        }
      }

      await _scheduleNotification(
        id: 5000,
        title: _getStreakNotificationTitle(recommendation.urgency),
        body: recommendation.message,
        scheduledDate: notificationTime,
        type: CoachingNotificationType.streakProtection,
        payload: {
          'urgency': recommendation.urgency.name,
          'action_suggestion': recommendation.actionSuggestion,
          'streak_days': streakInfo.currentDays,
        },
      );

      AppLogger.debug(
          'Scheduled streak protection notification for $notificationTime with urgency ${recommendation.urgency}');
    } catch (e) {
      AppLogger.error('Error scheduling streak protection: $e');
    }
  }

  /// Get notification title based on streak urgency
  String _getStreakNotificationTitle(StreakUrgency urgency) {
    switch (urgency) {
      case StreakUrgency.critical:
        return 'Streak Emergency!';
      case StreakUrgency.high:
        return 'Streak at Risk!';
      case StreakUrgency.medium:
        return 'Streak Check-in';
      case StreakUrgency.low:
        return 'Streak Momentum';
    }
  }

  /// Schedule weather-based suggestions
  Future<void> _scheduleWeatherSuggestions(
      CoachingNotificationPreferences preferences,
      Map<String, dynamic> coachingPlan) async {
    try {
      // Get weather forecast for the next 7 days
      final forecast = await _weatherService.getWeatherForecast();
      if (forecast.isEmpty) return;

      final tone = CoachingTone.fromValue(preferences.coachingTone);
      final now = DateTime.now();

      for (int day = 0; day < math.min(forecast.length, 7); day++) {
        final weather = forecast[day];

        // Only send notifications for significant weather conditions
        if (!_weatherService.shouldSendWeatherNotification(
            weather, preferences)) {
          continue;
        }

        // Generate weather-based suggestion
        final suggestion =
            _weatherService.generateRuckSuggestion(weather, tone);

        // Schedule notification for 7 AM each day
        final notificationTime = DateTime(
          now.year,
          now.month,
          now.day + day + 1,
          7, // 7 AM
          0,
        );

        // Skip if in quiet hours (though 7 AM usually isn't)
        final timeOfDay = TimeOfDay.fromDateTime(notificationTime);
        if (preferences.isInQuietHours(timeOfDay)) continue;

        await _scheduleNotification(
          id: 6000 + day,
          title: _getWeatherNotificationTitle(weather.severity),
          body: suggestion.suggestion,
          scheduledDate: notificationTime,
          type: CoachingNotificationType.weatherSuggestion,
          payload: {
            'weather_severity': weather.severity.name,
            'temperature': weather.temperature,
            'condition': weather.condition,
            'tips': suggestion.tips.join('; '),
            'is_recommended': suggestion.isRecommended,
          },
        );

        AppLogger.debug(
            'Scheduled weather notification for $notificationTime - ${weather.severity} conditions');
      }
    } catch (e) {
      AppLogger.error('Error scheduling weather suggestions: $e');
    }
  }

  /// Get notification title based on weather severity
  String _getWeatherNotificationTitle(WeatherSeverity severity) {
    switch (severity) {
      case WeatherSeverity.ideal:
        return 'Perfect Ruck Weather!';
      case WeatherSeverity.moderate:
        return 'Weather Update';
      case WeatherSeverity.challenging:
        return 'Weather Advisory';
      case WeatherSeverity.extreme:
        return 'Weather Warning';
    }
  }

  /// Generate personalized coaching message based on tone and context
  Future<String> _generateCoachingMessage(
    CoachingNotificationType type,
    String tone,
    Map<String, dynamic> context,
  ) async {
    try {
      return await _messageGenerator.generateMessage(
        type: type,
        tone: CoachingTone.fromValue(tone),
        context: context,
      );
    } catch (e) {
      AppLogger.error('Error generating coaching message: $e');
      return _getFallbackMessage(type, tone);
    }
  }

  /// Get fallback message when AI generation fails
  String _getFallbackMessage(CoachingNotificationType type, String tone) {
    final coachingTone = CoachingTone.fromValue(tone);

    switch (type) {
      case CoachingNotificationType.sessionReminder:
        return _getSessionReminderMessage(coachingTone);
      case CoachingNotificationType.motivational:
        return _getMotivationalMessage(coachingTone);
      case CoachingNotificationType.missedSession:
        return _getMissedSessionMessage(coachingTone);
      case CoachingNotificationType.progressCelebration:
        return _getProgressMessage(coachingTone);
      case CoachingNotificationType.streakProtection:
        return _getStreakMessage(coachingTone);
      default:
        return coachingTone.sampleMessage;
    }
  }

  /// Get session reminder message based on tone
  String _getSessionReminderMessage(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return 'Your ruck session is coming up! Time to gear up and move out!';
      case CoachingTone.supportiveFriend:
        return 'Hey there! Just a friendly reminder about your ruck session today. You\'ve got this!';
      case CoachingTone.dataNerd:
        return 'Session alert: Your planned ruck is scheduled soon. Check your metrics and execute!';
      case CoachingTone.minimalist:
        return 'Ruck time.';
    }
  }

  /// Get motivational message based on tone
  String _getMotivationalMessage(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return 'No excuses today! Your goals won\'t achieve themselves!';
      case CoachingTone.supportiveFriend:
        return 'You\'re making amazing progress! Keep pushing forward, one step at a time.';
      case CoachingTone.dataNerd:
        return 'Your consistency rate is improving. Maintain momentum for optimal results.';
      case CoachingTone.minimalist:
        return 'Keep going.';
    }
  }

  /// Get missed session message based on tone
  String _getMissedSessionMessage(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return 'Missed your session? Get back in formation! Make it up today!';
      case CoachingTone.supportiveFriend:
        return 'Life happens! Don\'t worry about the missed session - let\'s get back on track together.';
      case CoachingTone.dataNerd:
        return 'Session adherence dip detected. Recommend immediate course correction.';
      case CoachingTone.minimalist:
        return 'Missed one. Next?';
    }
  }

  /// Get progress celebration message based on tone
  String _getProgressMessage(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return 'Outstanding! You crushed that milestone! Keep the momentum!';
      case CoachingTone.supportiveFriend:
        return 'Incredible work! You should be proud of how far you\'ve come!';
      case CoachingTone.dataNerd:
        return 'Milestone achieved! Progress metrics are trending positive.';
      case CoachingTone.minimalist:
        return 'Milestone reached.';
    }
  }

  /// Get streak protection message based on tone
  String _getStreakMessage(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return 'Your streak is on the line! Don\'t break it now!';
      case CoachingTone.supportiveFriend:
        return 'You\'ve built an amazing streak! Let\'s keep it going strong!';
      case CoachingTone.dataNerd:
        return 'Streak at risk. Immediate action required to maintain consistency.';
      case CoachingTone.minimalist:
        return 'Streak active.';
    }
  }

  /// Get random time for motivational notifications (avoiding quiet hours)
  DateTime? _getRandomMotivationalTime(
      DateTime date, CoachingNotificationPreferences preferences) {
    final random = math.Random();
    final startHour = 8; // 8 AM
    final endHour = 20; // 8 PM

    for (int attempt = 0; attempt < 10; attempt++) {
      final hour = startHour + random.nextInt(endHour - startHour);
      final minute = random.nextInt(60);
      final scheduledTime =
          DateTime(date.year, date.month, date.day, hour, minute);
      final timeOfDay = TimeOfDay.fromDateTime(scheduledTime);

      if (!preferences.isInQuietHours(timeOfDay)) {
        return scheduledTime;
      }
    }

    return null; // Couldn't find suitable time
  }

  /// Schedule a single notification
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required CoachingNotificationType type,
    Map<String, dynamic>? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // For immediate notifications, use show; for scheduled, would use zonedSchedule
    if (scheduledDate
        .isBefore(DateTime.now().add(const Duration(seconds: 10)))) {
      await _notifications.show(
        id,
        title,
        body,
        details,
        payload: payload?.toString(),
      );
    } else {
      // For future scheduling, we'd need timezone package and zonedSchedule
      // For now, log that this would be scheduled
      AppLogger.debug(
          'Would schedule ${type.value} notification for $scheduledDate (scheduling not implemented)');
    }

    AppLogger.debug('Scheduled ${type.value} notification for $scheduledDate');
  }

  /// Cancel all coaching notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    AppLogger.info('All coaching notifications cancelled');
  }

  /// Start daily scheduler to refresh notifications
  void _startDailyScheduler() {
    _dailyScheduleTimer?.cancel();
    _dailyScheduleTimer =
        Timer.periodic(const Duration(hours: 24), (timer) async {
      AppLogger.info('Running daily notification refresh');
      // This will be triggered by a background task or when app opens
      // The actual rescheduling will be handled by the preferences service
    });
  }

  /// Get coaching plan from API
  Future<Map<String, dynamic>?> _getCoachingPlan() async {
    try {
      final response = await _apiClient.get('/user/coaching-plan');
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      AppLogger.error('Error fetching coaching plan: $e');
      return null;
    }
  }

  /// Handle background notification checks (called by system when notifications trigger)
  Future<void> handleBackgroundCheck(
      String notificationType, Map<String, dynamic>? payload) async {
    try {
      switch (notificationType) {
        case 'missed_session':
          await _processMissedSessionCheck(payload);
          break;
        case 'streak_protection':
          await _processStreakProtectionCheck(payload);
          break;
        case 'weather':
          await _processWeatherCheck(payload);
          break;
        default:
          AppLogger.warning(
              'Unknown notification type for background check: $notificationType');
      }
    } catch (e) {
      AppLogger.error('Error handling background notification check: $e');
    }
  }

  /// Process missed session background check
  Future<void> _processMissedSessionCheck(Map<String, dynamic>? payload) async {
    try {
      // Check if user has completed sessions today
      final response = await _apiClient.get('/user/sessions/today');
      final todaySessions = response.data['sessions'] as List<dynamic>? ?? [];

      if (todaySessions.isEmpty) {
        // User hasn't rucked today - send encouragement
        final preferences = await _getUserNotificationPreferences();
        if (preferences?.enableMissedSession == true) {
          final tone = CoachingTone.fromValue(preferences!.coachingTone);
          final message = _getMissedSessionMessage(tone);

          await _sendImmediateNotification(
            title: 'Session Check-in',
            body: message,
            type: CoachingNotificationType.missedSession,
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error processing missed session check: $e');
    }
  }

  /// Process streak protection background check
  Future<void> _processStreakProtectionCheck(
      Map<String, dynamic>? payload) async {
    try {
      final streakInfo = await _streakService.getStreakInfo();
      if (streakInfo == null) return;

      final preferences = await _getUserNotificationPreferences();
      if (preferences == null) return;

      if (_streakService.shouldSendStreakProtection(streakInfo, preferences)) {
        final tone = CoachingTone.fromValue(preferences.coachingTone);
        final recommendation =
            _streakService.generateProtectionRecommendation(streakInfo, tone);

        await _sendImmediateNotification(
          title: _getStreakNotificationTitle(recommendation.urgency),
          body: recommendation.message,
          type: CoachingNotificationType.streakProtection,
        );
      }
    } catch (e) {
      AppLogger.error('Error processing streak protection check: $e');
    }
  }

  /// Process weather background check
  Future<void> _processWeatherCheck(Map<String, dynamic>? payload) async {
    try {
      final weather = await _weatherService.getCurrentWeather();
      if (weather == null) return;

      final preferences = await _getUserNotificationPreferences();
      if (preferences == null) return;

      if (_weatherService.shouldSendWeatherNotification(weather, preferences)) {
        final tone = CoachingTone.fromValue(preferences.coachingTone);
        final suggestion =
            _weatherService.generateRuckSuggestion(weather, tone);

        await _sendImmediateNotification(
          title: _getWeatherNotificationTitle(weather.severity),
          body: suggestion.suggestion,
          type: CoachingNotificationType.weatherSuggestion,
        );
      }
    } catch (e) {
      AppLogger.error('Error processing weather check: $e');
    }
  }

  /// Send immediate notification (for background checks)
  Future<void> _sendImmediateNotification({
    required String title,
    required String body,
    required CoachingNotificationType type,
    Map<String, dynamic>? payload,
  }) async {
    await _scheduleNotification(
      id: DateTime.now().millisecondsSinceEpoch % 10000, // Unique ID
      title: title,
      body: body,
      scheduledDate: DateTime.now(),
      type: type,
      payload: payload,
    );
  }

  /// Get user notification preferences
  Future<CoachingNotificationPreferences?>
      _getUserNotificationPreferences() async {
    try {
      final response = await _apiClient.get('/user/notification-preferences');
      return CoachingNotificationPreferences.fromJson(
          response.data as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error fetching notification preferences: $e');
      return null;
    }
  }

  /// Dispose of resources
  void dispose() {
    _dailyScheduleTimer?.cancel();
  }
}
