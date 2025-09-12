import 'dart:math' as math;
import 'package:rucking_app/features/coaching/domain/models/coaching_notification_preferences.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for generating personalized coaching messages with AI
class CoachingMessageGenerator {
  final ApiClient _apiClient;
  final math.Random _random = math.Random();

  CoachingMessageGenerator(this._apiClient);

  /// Generate a personalized coaching message
  Future<String> generateMessage({
    required CoachingNotificationType type,
    required CoachingTone tone,
    required Map<String, dynamic> context,
  }) async {
    try {
      // Build AI prompt based on context
      final prompt = _buildCoachingPrompt(type, tone, context);
      
      final response = await _apiClient.post('/ai/coaching-message', {
        'prompt': prompt,
        'tone': tone.value,
        'type': type.value,
        'context': context,
        'max_length': _getMaxLength(type),
      });
      
      final message = response.data['message'] as String?;
      if (message != null && message.trim().isNotEmpty) {
        return _validateAndCleanMessage(message);
      }
      
      return _getFallbackMessage(type, tone, context);
    } catch (e) {
      AppLogger.error('Error generating AI coaching message: $e');
      return _getFallbackMessage(type, tone, context);
    }
  }

  /// Build coaching prompt for AI
  String _buildCoachingPrompt(
    CoachingNotificationType type,
    CoachingTone tone,
    Map<String, dynamic> context,
  ) {
    final basePrompt = StringBuffer();
    
    // Set coaching personality
    basePrompt.writeln('You are a ${tone.description} AI fitness coach specializing in rucking.');
    basePrompt.writeln('Your communication style: ${tone.sampleMessage}');
    basePrompt.writeln();
    
    // Add user insights for personalized context
    final userInsights = context['user_insights'] as Map<String, dynamic>?;
    if (userInsights != null) {
      basePrompt.writeln(_buildUserInsightsContext(userInsights));
      basePrompt.writeln();
    }
    
    // Add context-specific information
    switch (type) {
      case CoachingNotificationType.sessionReminder:
        basePrompt.writeln(_buildSessionReminderContext(context));
        break;
      case CoachingNotificationType.motivational:
        basePrompt.writeln(_buildMotivationalContext(context));
        break;
      case CoachingNotificationType.missedSession:
        basePrompt.writeln(_buildMissedSessionContext(context));
        break;
      case CoachingNotificationType.progressCelebration:
        basePrompt.writeln(_buildProgressContext(context));
        break;
      case CoachingNotificationType.weatherSuggestion:
        basePrompt.writeln(_buildWeatherContext(context));
        break;
      case CoachingNotificationType.streakProtection:
        basePrompt.writeln(_buildStreakContext(context));
        break;
      case CoachingNotificationType.planMilestone:
        basePrompt.writeln(_buildMilestoneContext(context));
        break;
    }
    
    // Add general guidelines
    basePrompt.writeln();
    basePrompt.writeln('Guidelines:');
    basePrompt.writeln('- Keep message under ${_getMaxLength(type)} characters');
    basePrompt.writeln('- Be motivating and actionable');
    basePrompt.writeln('- Reference specific user data when available');
    basePrompt.writeln('- Match the ${tone.displayName} personality exactly');
    basePrompt.writeln('- No emojis unless tone specifically calls for them');
    
    return basePrompt.toString();
  }

  /// Build session reminder context
  String _buildSessionReminderContext(Map<String, dynamic> context) {
    final session = context['session'] as Map<String, dynamic>? ?? {};
    final plan = context['plan'] as Map<String, dynamic>? ?? {};
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a session reminder message.');
    buffer.writeln();
    
    if (session.isNotEmpty) {
      buffer.writeln('Upcoming Session:');
      buffer.writeln('- Type: ${session['type'] ?? 'Ruck Session'}');
      if (session['distance_km'] != null) {
        buffer.writeln('- Distance: ${session['distance_km']} km');
      }
      if (session['duration_minutes'] != null) {
        buffer.writeln('- Target Duration: ${session['duration_minutes']} minutes');
      }
      if (session['weight_kg'] != null) {
        buffer.writeln('- Weight: ${session['weight_kg']} kg');
      }
      if (session['notes'] != null && session['notes'].toString().trim().isNotEmpty) {
        buffer.writeln('- Notes: ${session['notes']}');
      }
    }
    
    if (plan.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Plan Context:');
      buffer.writeln('- Plan: ${plan['name'] ?? 'Current Plan'}');
      buffer.writeln('- Week: ${plan['current_week'] ?? 1}/${plan['duration_weeks'] ?? 8}');
      buffer.writeln('- Phase: ${plan['phase'] ?? 'Base Building'}');
    }
    
    return buffer.toString();
  }

  /// Build motivational context
  String _buildMotivationalContext(Map<String, dynamic> context) {
    final plan = context['plan'] as Map<String, dynamic>? ?? {};
    final userStats = context['user_stats'] as Map<String, dynamic>? ?? {};
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a motivational message to inspire the user.');
    buffer.writeln();
    
    if (plan.isNotEmpty) {
      buffer.writeln('Plan Progress:');
      buffer.writeln('- Current Week: ${plan['current_week'] ?? 1}/${plan['duration_weeks'] ?? 8}');
      buffer.writeln('- Phase: ${plan['phase'] ?? 'Base Building'}');
      if (plan['adherence_score'] != null) {
        buffer.writeln('- Adherence: ${plan['adherence_score']}%');
      }
    }
    
    if (userStats.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Recent Performance:');
      if (userStats['total_distance_km'] != null) {
        buffer.writeln('- Total Distance: ${userStats['total_distance_km']} km');
      }
      if (userStats['current_streak'] != null) {
        buffer.writeln('- Current Streak: ${userStats['current_streak']} days');
      }
      if (userStats['sessions_this_week'] != null) {
        buffer.writeln('- This Week: ${userStats['sessions_this_week']} sessions');
      }
    }
    
    // Include user insights for more context
    final userInsights = context['user_insights'] as Map<String, dynamic>?;
    if (userInsights != null) {
      buffer.writeln();
      buffer.writeln(_buildUserInsightsContext(userInsights));
    }
    
    return buffer.toString();
  }

  /// Build missed session context
  String _buildMissedSessionContext(Map<String, dynamic> context) {
    final missedSessions = context['missed_sessions'] as List<dynamic>? ?? [];
    final plan = context['plan'] as Map<String, dynamic>? ?? {};
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a recovery message for missed sessions.');
    buffer.writeln();
    
    buffer.writeln('Missed Sessions: ${missedSessions.length}');
    if (plan.isNotEmpty && plan['adherence_score'] != null) {
      buffer.writeln('Plan Adherence: ${plan['adherence_score']}%');
    }
    
    buffer.writeln();
    buffer.writeln('Focus on getting back on track rather than dwelling on missed sessions.');
    
    return buffer.toString();
  }

  /// Build progress celebration context
  String _buildProgressContext(Map<String, dynamic> context) {
    final milestone = context['milestone'] as Map<String, dynamic>? ?? {};
    final achievement = context['achievement'] as Map<String, dynamic>? ?? {};
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a progress celebration message.');
    buffer.writeln();
    
    if (milestone.isNotEmpty) {
      buffer.writeln('Milestone Achieved:');
      buffer.writeln('- Name: ${milestone['name'] ?? 'Progress Milestone'}');
      buffer.writeln('- Description: ${milestone['description'] ?? ''}');
    }
    
    if (achievement.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Achievement Details:');
      buffer.writeln('- Type: ${achievement['type'] ?? 'Progress'}');
      buffer.writeln('- Value: ${achievement['value'] ?? ''}');
    }
    
    return buffer.toString();
  }

  /// Build weather suggestion context
  String _buildWeatherContext(Map<String, dynamic> context) {
    final weather = context['weather'] as Map<String, dynamic>? ?? {};
    final suggestion = context['suggestion'] as String? ?? '';
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a weather-based ruck suggestion.');
    buffer.writeln();
    
    if (weather.isNotEmpty) {
      buffer.writeln('Current Weather:');
      buffer.writeln('- Condition: ${weather['condition'] ?? 'Unknown'}');
      buffer.writeln('- Temperature: ${weather['temperature'] ?? 'Unknown'}°C');
      if (weather['precipitation'] != null) {
        buffer.writeln('- Precipitation: ${weather['precipitation']}%');
      }
      if (weather['wind_speed'] != null) {
        buffer.writeln('- Wind: ${weather['wind_speed']} km/h');
      }
    }
    
    if (suggestion.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Suggested Action: $suggestion');
    }
    
    return buffer.toString();
  }

  /// Build streak protection context
  String _buildStreakContext(Map<String, dynamic> context) {
    final streak = context['streak'] as Map<String, dynamic>? ?? {};
    final risk = context['risk_level'] as String? ?? 'medium';
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a streak protection message.');
    buffer.writeln();
    
    if (streak.isNotEmpty) {
      buffer.writeln('Current Streak:');
      buffer.writeln('- Days: ${streak['current_days'] ?? 0}');
      buffer.writeln('- Best: ${streak['best_days'] ?? 0}');
      buffer.writeln('- Risk Level: $risk');
    }
    
    buffer.writeln();
    buffer.writeln('Encourage maintaining consistency without being pushy.');
    
    return buffer.toString();
  }

  /// Build milestone context
  String _buildMilestoneContext(Map<String, dynamic> context) {
    final milestone = context['milestone'] as Map<String, dynamic>? ?? {};
    
    final buffer = StringBuffer();
    buffer.writeln('TASK: Create a plan milestone message.');
    buffer.writeln();
    
    if (milestone.isNotEmpty) {
      buffer.writeln('Upcoming Milestone:');
      buffer.writeln('- Name: ${milestone['name'] ?? 'Plan Milestone'}');
      buffer.writeln('- Target Date: ${milestone['target_date'] ?? 'Soon'}');
      buffer.writeln('- Progress: ${milestone['progress'] ?? 0}%');
    }
    
    return buffer.toString();
  }

  /// Build user insights context for AI personalization
  String _buildUserInsightsContext(Map<String, dynamic> userInsights) {
    final buffer = StringBuffer();
    buffer.writeln('USER INSIGHTS (for personalization):');
    
    final facts = userInsights['facts'] as Map<String, dynamic>? ?? {};
    
    // Recent performance summary
    final totals30d = facts['totals_30d'] as Map<String, dynamic>? ?? {};
    final sessions30d = totals30d['sessions'] as num? ?? 0;
    final distance30d = totals30d['distance_km'] as num? ?? 0;
    
    if (sessions30d > 0) {
      final avgDistance = distance30d / sessions30d;
      final avgWeekly = sessions30d / 4.3;
      buffer.writeln('- Recent Activity: ${sessions30d.toInt()} sessions in 30 days (${avgWeekly.toStringAsFixed(1)}/week)');
      buffer.writeln('- Average Distance: ${avgDistance.toStringAsFixed(1)}km per session');
    }
    
    // Experience level
    final allTime = facts['all_time'] as Map<String, dynamic>? ?? {};
    final totalSessions = allTime['sessions'] as num? ?? 0;
    String experience = 'beginner';
    if (totalSessions >= 20) {
      experience = 'experienced';
    } else if (totalSessions >= 10) {
      experience = 'intermediate';
    }
    buffer.writeln('- Experience Level: $experience ($totalSessions total sessions)');
    
    // Recent performance trend
    final recentSplits = facts['recent_splits'] as List<dynamic>? ?? [];
    if (recentSplits.isNotEmpty && recentSplits.length >= 2) {
      buffer.writeln('- Recent Sessions: ${recentSplits.length} sessions analyzed for pacing patterns');
    }
    
    // Last session info
    final recency = facts['recency'] as Map<String, dynamic>? ?? {};
    final daysSince = recency['days_since_last'] as num?;
    if (daysSince != null) {
      if (daysSince < 1) {
        buffer.writeln('- Last Ruck: Today');
      } else if (daysSince < 2) {
        buffer.writeln('- Last Ruck: Yesterday');
      } else {
        buffer.writeln('- Last Ruck: ${daysSince.toInt()} days ago');
      }
    }
    
    // AI-generated insights if available
    final insights = userInsights['insights'] as Map<String, dynamic>? ?? {};
    final candidates = insights['candidates'] as List<dynamic>? ?? [];
    if (candidates.isNotEmpty) {
      buffer.writeln('- AI Insights Available: ${candidates.length} behavioral patterns identified');
      // Include top insight for context
      final topInsight = candidates.first as Map<String, dynamic>? ?? {};
      final insightText = topInsight['text'] as String? ?? '';
      if (insightText.isNotEmpty) {
        buffer.writeln('- Key Pattern: $insightText');
      }
    }
    
    return buffer.toString();
  }

  /// Get maximum message length for notification type
  int _getMaxLength(CoachingNotificationType type) {
    switch (type) {
      case CoachingNotificationType.sessionReminder:
        return 100;
      case CoachingNotificationType.motivational:
        return 120;
      case CoachingNotificationType.missedSession:
        return 90;
      case CoachingNotificationType.progressCelebration:
        return 110;
      case CoachingNotificationType.weatherSuggestion:
        return 130;
      case CoachingNotificationType.streakProtection:
        return 95;
      case CoachingNotificationType.planMilestone:
        return 105;
    }
  }

  /// Validate and clean generated message
  String _validateAndCleanMessage(String message) {
    // Remove extra whitespace and newlines
    String cleaned = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove quotes if the entire message is wrapped in them
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    
    // Ensure it ends with proper punctuation
    if (!cleaned.endsWith('.') && !cleaned.endsWith('!') && !cleaned.endsWith('?')) {
      cleaned += '.';
    }
    
    return cleaned;
  }

  /// Get fallback message when AI generation fails
  String _getFallbackMessage(
    CoachingNotificationType type,
    CoachingTone tone,
    Map<String, dynamic> context,
  ) {
    final fallbackMessages = _getFallbackMessages(tone);
    final typeMessages = fallbackMessages[type] ?? [tone.sampleMessage];
    
    return typeMessages[_random.nextInt(typeMessages.length)];
  }

  /// Get fallback message templates for each tone and type
  Map<CoachingNotificationType, List<String>> _getFallbackMessages(CoachingTone tone) {
    switch (tone) {
      case CoachingTone.drillSergeant:
        return {
          CoachingNotificationType.sessionReminder: [
            'Time to move out! Your ruck session starts soon!',
            'Gear up and get moving! Session incoming!',
            'No excuses! Your scheduled ruck awaits!',
          ],
          CoachingNotificationType.motivational: [
            'Push harder! Your goals won\'t achieve themselves!',
            'No backing down! Keep that momentum rolling!',
            'Show me what you\'re made of today!',
          ],
          CoachingNotificationType.missedSession: [
            'Get back in formation! Make up that missed session!',
            'No time for excuses! Recovery ruck time!',
            'Dust yourself off and get back out there!',
          ],
          CoachingNotificationType.progressCelebration: [
            'Outstanding work! You crushed that milestone!',
            'Excellent progress! Keep the fire burning!',
            'Mission accomplished! Now set the next target!',
          ],
          CoachingNotificationType.streakProtection: [
            'Your streak is on the line! Don\'t quit now!',
            'Maintain formation! Protect that streak!',
            'Stay strong! Your consistency is your strength!',
          ],
          CoachingNotificationType.weatherSuggestion: [
            'Weather conditions optimal for training!',
            'Perfect conditions - no excuses today!',
            'Mother Nature is on your side!',
          ],
          CoachingNotificationType.planMilestone: [
            'Next milestone approaching! Stay focused!',
            'Target acquired! Keep pushing forward!',
            'Mission progress on track! Maintain pace!',
          ],
        };
        
      case CoachingTone.supportiveFriend:
        return {
          CoachingNotificationType.sessionReminder: [
            'Hey there! Your ruck session is coming up. You\'ve got this!',
            'Friendly reminder: time to lace up and get moving!',
            'Your scheduled ruck is approaching. Ready to make it happen?',
          ],
          CoachingNotificationType.motivational: [
            'You\'re doing amazing! Keep up the great work!',
            'Every step forward is progress. Be proud of yourself!',
            'I believe in you! Let\'s make today count!',
          ],
          CoachingNotificationType.missedSession: [
            'Life happens! Don\'t worry about yesterday - let\'s focus on today.',
            'No worries about the missed session. Let\'s get back on track together!',
            'Every day is a fresh start. You\'ve got this!',
          ],
          CoachingNotificationType.progressCelebration: [
            'Incredible work! You should be so proud of your progress!',
            'Look how far you\'ve come! This is worth celebrating!',
            'Amazing achievement! Your hard work is really paying off!',
          ],
          CoachingNotificationType.streakProtection: [
            'You\'ve built an amazing streak! Let\'s keep it going strong!',
            'Your consistency is inspiring! One more day to keep it alive!',
            'That streak represents real dedication. Let\'s protect it!',
          ],
          CoachingNotificationType.weatherSuggestion: [
            'Beautiful day for a ruck! The weather is perfect for getting outside.',
            'Looks like great conditions for your session today!',
            'Mother Nature is smiling on your ruck plans today!',
          ],
          CoachingNotificationType.planMilestone: [
            'You\'re getting close to a big milestone! Excited to see you reach it!',
            'Great progress on your plan! A milestone is just around the corner!',
            'Your dedication is showing! Next milestone coming up!',
          ],
        };
        
      case CoachingTone.dataNerd:
        return {
          CoachingNotificationType.sessionReminder: [
            'Session alert: Your planned ruck is scheduled soon. Execute plan.',
            'Training window opening. Parameters loaded. Commence session.',
            'Scheduled session approaching. All systems ready.',
          ],
          CoachingNotificationType.motivational: [
            'Performance metrics trending positive. Maintain current trajectory.',
            'Consistency algorithms show optimal patterns. Continue execution.',
            'Data indicates strong performance. Sustain current protocols.',
          ],
          CoachingNotificationType.missedSession: [
            'Session adherence dip detected. Recommend immediate course correction.',
            'Missed session logged. Recalibrating schedule for optimal recovery.',
            'Performance gap identified. Initiating recovery sequence.',
          ],
          CoachingNotificationType.progressCelebration: [
            'Milestone achieved! Performance metrics exceed baseline.',
            'Target reached. Progress algorithms show significant improvement.',
            'Achievement unlocked. Data confirms substantial advancement.',
          ],
          CoachingNotificationType.streakProtection: [
            'Streak at critical threshold. Immediate action required.',
            'Consistency metric at risk. Recommend maintaining current pattern.',
            'Streak data valuable. Protect current sequence.',
          ],
          CoachingNotificationType.weatherSuggestion: [
            'Weather conditions analyzed. Optimal parameters for session execution.',
            'Environmental factors favorable. Proceed with planned session.',
            'Atmospheric conditions within acceptable training range.',
          ],
          CoachingNotificationType.planMilestone: [
            'Next milestone calculated. Progress indicators show proximity.',
            'Milestone approaching. Current trajectory suggests timely completion.',
            'Progress metrics indicate milestone achievement imminent.',
          ],
        };
        
      case CoachingTone.minimalist:
        return {
          CoachingNotificationType.sessionReminder: [
            'Ruck time.',
            'Session ready.',
            'Time to move.',
          ],
          CoachingNotificationType.motivational: [
            'Keep going.',
            'Progress made.',
            'Stay strong.',
          ],
          CoachingNotificationType.missedSession: [
            'Missed one. Next?',
            'Continue.',
            'Reset. Go.',
          ],
          CoachingNotificationType.progressCelebration: [
            'Milestone reached.',
            'Well done.',
            'Progress confirmed.',
          ],
          CoachingNotificationType.streakProtection: [
            'Streak active.',
            'Maintain.',
            'Keep it alive.',
          ],
          CoachingNotificationType.weatherSuggestion: [
            'Good conditions.',
            'Weather optimal.',
            'Perfect day.',
          ],
          CoachingNotificationType.planMilestone: [
            'Milestone near.',
            'Target close.',
            'Almost there.',
          ],
        };
    }
  }
}