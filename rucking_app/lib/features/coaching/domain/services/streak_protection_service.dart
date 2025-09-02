import 'dart:math' as math;
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/coaching/domain/models/coaching_notification_preferences.dart';

/// User's current streak information
class StreakInfo {
  final int currentDays;
  final int bestDays;
  final DateTime? lastSessionDate;
  final DateTime streakStartDate;
  final bool isActive;
  final StreakRiskLevel riskLevel;

  const StreakInfo({
    required this.currentDays,
    required this.bestDays,
    this.lastSessionDate,
    required this.streakStartDate,
    required this.isActive,
    required this.riskLevel,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> json) {
    return StreakInfo(
      currentDays: json['current_days'] ?? 0,
      bestDays: json['best_days'] ?? 0,
      lastSessionDate: json['last_session_date'] != null 
          ? DateTime.tryParse(json['last_session_date'])
          : null,
      streakStartDate: DateTime.tryParse(json['streak_start_date']) ?? DateTime.now(),
      isActive: json['is_active'] ?? false,
      riskLevel: StreakRiskLevel.values.firstWhere(
        (level) => level.name == json['risk_level'],
        orElse: () => StreakRiskLevel.safe,
      ),
    );
  }

  /// Days since last session
  int get daysSinceLastSession {
    if (lastSessionDate == null) return 0;
    return DateTime.now().difference(lastSessionDate!).inDays;
  }

  /// Check if streak is at risk
  bool get isAtRisk => riskLevel == StreakRiskLevel.high || riskLevel == StreakRiskLevel.critical;

  /// Get next milestone days
  int get nextMilestone {
    final milestones = [7, 14, 21, 30, 60, 90, 180, 365];
    return milestones.firstWhere(
      (milestone) => milestone > currentDays,
      orElse: () => ((currentDays ~/ 100) + 1) * 100,
    );
  }

  /// Days until next milestone
  int get daysToNextMilestone => nextMilestone - currentDays;
}

/// Risk levels for streak protection
enum StreakRiskLevel {
  safe,     // 0-1 days since last session
  medium,   // 2 days since last session  
  high,     // 3 days since last session
  critical, // 4+ days since last session
}

/// Streak protection recommendation
class StreakProtectionRecommendation {
  final String message;
  final String actionSuggestion;
  final StreakUrgency urgency;
  final List<String> motivationalFactors;

  const StreakProtectionRecommendation({
    required this.message,
    required this.actionSuggestion,
    required this.urgency,
    required this.motivationalFactors,
  });
}

/// Urgency levels for streak protection
enum StreakUrgency {
  low,      // Informational, building momentum
  medium,   // Gentle reminder
  high,     // Strong encouragement
  critical, // Urgent action needed
}

/// Service for protecting and motivating user streaks
class StreakProtectionService {
  final ApiClient _apiClient;

  StreakProtectionService(this._apiClient);

  /// Get current user streak information
  Future<StreakInfo?> getStreakInfo() async {
    try {
      final response = await _apiClient.get('/user/streak');
      return StreakInfo.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error fetching streak info: $e');
      return null;
    }
  }

  /// Calculate streak risk level based on days since last session
  StreakRiskLevel calculateRiskLevel(int daysSinceLastSession) {
    if (daysSinceLastSession <= 1) return StreakRiskLevel.safe;
    if (daysSinceLastSession == 2) return StreakRiskLevel.medium;
    if (daysSinceLastSession == 3) return StreakRiskLevel.high;
    return StreakRiskLevel.critical;
  }

  /// Generate streak protection recommendation
  StreakProtectionRecommendation generateProtectionRecommendation(
    StreakInfo streak,
    CoachingTone tone,
  ) {
    switch (streak.riskLevel) {
      case StreakRiskLevel.safe:
        return _generateSafeStreakRecommendation(streak, tone);
      case StreakRiskLevel.medium:
        return _generateMediumRiskRecommendation(streak, tone);
      case StreakRiskLevel.high:
        return _generateHighRiskRecommendation(streak, tone);
      case StreakRiskLevel.critical:
        return _generateCriticalRiskRecommendation(streak, tone);
    }
  }

  /// Generate recommendation for safe streaks
  StreakProtectionRecommendation _generateSafeStreakRecommendation(
    StreakInfo streak,
    CoachingTone tone,
  ) {
    final messages = _getSafeStreakMessages(tone);
    final actions = _getSafeStreakActions();
    final motivationalFactors = [
      '${streak.currentDays} days of consistency',
      'Building strong habits',
      'Momentum is growing',
    ];

    if (streak.currentDays > 0 && streak.daysToNextMilestone <= 3) {
      motivationalFactors.add('Only ${streak.daysToNextMilestone} days to ${streak.nextMilestone}-day milestone!');
    }

    return StreakProtectionRecommendation(
      message: messages[math.Random().nextInt(messages.length)],
      actionSuggestion: actions[math.Random().nextInt(actions.length)],
      urgency: StreakUrgency.low,
      motivationalFactors: motivationalFactors,
    );
  }

  /// Generate recommendation for medium risk streaks
  StreakProtectionRecommendation _generateMediumRiskRecommendation(
    StreakInfo streak,
    CoachingTone tone,
  ) {
    final messages = _getMediumRiskMessages(tone);
    final actions = _getMediumRiskActions();
    final motivationalFactors = [
      '${streak.currentDays} days of hard work at stake',
      '2 days since last session',
      'Easy to get back on track',
    ];

    return StreakProtectionRecommendation(
      message: messages[math.Random().nextInt(messages.length)],
      actionSuggestion: actions[math.Random().nextInt(actions.length)],
      urgency: StreakUrgency.medium,
      motivationalFactors: motivationalFactors,
    );
  }

  /// Generate recommendation for high risk streaks
  StreakProtectionRecommendation _generateHighRiskRecommendation(
    StreakInfo streak,
    CoachingTone tone,
  ) {
    final messages = _getHighRiskMessages(tone);
    final actions = _getHighRiskActions();
    final motivationalFactors = [
      '${streak.currentDays} days of dedication on the line',
      '3 days without a session',
      'Your streak needs you now',
    ];

    if (streak.currentDays >= streak.bestDays) {
      motivationalFactors.add('This is your personal best streak!');
    }

    return StreakProtectionRecommendation(
      message: messages[math.Random().nextInt(messages.length)],
      actionSuggestion: actions[math.Random().nextInt(actions.length)],
      urgency: StreakUrgency.high,
      motivationalFactors: motivationalFactors,
    );
  }

  /// Generate recommendation for critical risk streaks
  StreakProtectionRecommendation _generateCriticalRiskRecommendation(
    StreakInfo streak,
    CoachingTone tone,
  ) {
    final messages = _getCriticalRiskMessages(tone);
    final actions = _getCriticalRiskActions();
    final motivationalFactors = [
      '${streak.currentDays} days of commitment about to be lost',
      '${streak.daysSinceLastSession} days without activity',
      'Last chance to save your streak',
    ];

    return StreakProtectionRecommendation(
      message: messages[math.Random().nextInt(messages.length)],
      actionSuggestion: actions[math.Random().nextInt(actions.length)],
      urgency: StreakUrgency.critical,
      motivationalFactors: motivationalFactors,
    );
  }

  /// Get safe streak messages by tone
  List<String> _getSafeStreakMessages(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Solid work maintaining that streak! Keep the discipline strong!',
          'Your consistency is outstanding! Don\'t let up now!',
          'That\'s how you build character - day after day!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Your streak is looking great! You\'re building such good habits.',
          'Love seeing your consistency! You\'re really finding your rhythm.',
          'Your dedication is inspiring! Keep up the amazing work!',
        ];
      case CoachingTone.dataNerd:
        return [
          'Streak metrics show excellent consistency patterns.',
          'Your adherence algorithm is performing optimally.',
          'Current streak data indicates strong habit formation.',
        ];
      case CoachingTone.minimalist:
        return [
          'Streak strong.',
          'Good consistency.',
          'Keep it up.',
        ];
    }
  }

  /// Get medium risk messages by tone
  List<String> _getMediumRiskMessages(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'Your streak needs attention, soldier! Time to get back in line!',
          'Two days off the grid - time to recommit to your mission!',
          'That streak won\'t protect itself! Get moving!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Haven\'t seen you in a couple days - your streak misses you!',
          'Life got busy? No worries! Let\'s get your streak back on track.',
          'Your consistency has been so good - let\'s keep it going!',
        ];
      case CoachingTone.dataNerd:
        return [
          'Streak stability declining. Recommend immediate session.',
          '48-hour gap detected. Course correction advised.',
          'Consistency metrics need recalibration.',
        ];
      case CoachingTone.minimalist:
        return [
          'Streak slipping.',
          '2 days gap.',
          'Time to return.',
        ];
    }
  }

  /// Get high risk messages by tone
  List<String> _getHighRiskMessages(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'RED ALERT! Your streak is under attack! Defend it!',
          'Three days AWOL! Your streak demands immediate action!',
          'This is not a drill! Your consistency is compromised!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'Your amazing streak is in jeopardy! I know you can save it!',
          'Missing you! Your streak has been such a source of pride.',
          'Three days feels like forever! Let\'s get you back out there.',
        ];
      case CoachingTone.dataNerd:
        return [
          'Critical threshold reached. Immediate intervention required.',
          '72-hour streak gap approaching failure point.',
          'Streak protection protocol activated.',
        ];
      case CoachingTone.minimalist:
        return [
          'Streak critical.',
          '3 days out.',
          'Act now.',
        ];
    }
  }

  /// Get critical risk messages by tone
  List<String> _getCriticalRiskMessages(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return [
          'MAYDAY! MAYDAY! Your streak is going down! Emergency action required!',
          'Four days without contact! Your streak is hanging by a thread!',
          'This is it - save your streak or lose everything!',
        ];
      case CoachingTone.supportiveFriend:
        return [
          'I\'m really worried about your streak! Please don\'t give up now!',
          'Your incredible streak is about to break! Let\'s save it together!',
          'Four days is too long! Your streak means too much to lose now!',
        ];
      case CoachingTone.dataNerd:
        return [
          'SYSTEM FAILURE: Streak at imminent termination risk.',
          'Four-day gap detected. Streak preservation in critical state.',
          'Emergency protocols engaged. Immediate action mandatory.',
        ];
      case CoachingTone.minimalist:
        return [
          'Streak dying.',
          'Save now.',
          'Last chance.',
        ];
    }
  }

  /// Get safe streak action suggestions
  List<String> _getSafeStreakActions() {
    return [
      'Plan your next session to maintain momentum',
      'Consider adding variety to keep it interesting',
      'Share your progress with a friend for accountability',
      'Set a mini-goal for the upcoming week',
    ];
  }

  /// Get medium risk action suggestions
  List<String> _getMediumRiskActions() {
    return [
      'Schedule a short ruck session today',
      'Even a 15-minute walk with weight counts',
      'Plan something easy but consistent',
      'Reset your rhythm with a quick session',
    ];
  }

  /// Get high risk action suggestions
  List<String> _getHighRiskActions() {
    return [
      'Do anything - even 10 minutes saves your streak',
      'Lower the bar and just get moving',
      'A short recovery ruck is all you need',
      'Don\'t overthink it - just start walking',
    ];
  }

  /// Get critical risk action suggestions
  List<String> _getCriticalRiskActions() {
    return [
      'Emergency mini-session: 5 minutes is enough',
      'Put on your shoes and walk to the mailbox',
      'Anything counts - save your streak now',
      'Don\'t let perfect be the enemy of progress',
    ];
  }

  /// Check if streak protection notification should be sent
  bool shouldSendStreakProtection(
    StreakInfo streak,
    CoachingNotificationPreferences preferences,
  ) {
    if (!preferences.enableStreakProtection) return false;
    if (!streak.isActive || streak.currentDays < 3) return false; // Only protect meaningful streaks
    
    // Send notifications for medium risk and higher
    return streak.riskLevel == StreakRiskLevel.medium ||
           streak.riskLevel == StreakRiskLevel.high ||
           streak.riskLevel == StreakRiskLevel.critical;
  }

  /// Get notification urgency based on risk level
  StreakUrgency getNotificationUrgency(StreakRiskLevel riskLevel) {
    switch (riskLevel) {
      case StreakRiskLevel.safe:
        return StreakUrgency.low;
      case StreakRiskLevel.medium:
        return StreakUrgency.medium;
      case StreakRiskLevel.high:
        return StreakUrgency.high;
      case StreakRiskLevel.critical:
        return StreakUrgency.critical;
    }
  }

  /// Calculate streak milestone rewards
  List<String> getStreakMilestoneRewards(int streakDays) {
    final rewards = <String>[];
    
    if (streakDays >= 7) rewards.add('Week Warrior badge');
    if (streakDays >= 14) rewards.add('Two Week Champion');
    if (streakDays >= 21) rewards.add('Habit Builder');
    if (streakDays >= 30) rewards.add('Monthly Master');
    if (streakDays >= 60) rewards.add('Consistency King');
    if (streakDays >= 90) rewards.add('Quarter Quest');
    if (streakDays >= 180) rewards.add('Half-Year Hero');
    if (streakDays >= 365) rewards.add('Annual Achiever');
    
    return rewards;
  }
}