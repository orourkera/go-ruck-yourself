import 'dart:convert';
import 'dart:math' as math;
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/features/ai_cheerleader/services/openai_responses_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/models/weather.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// Service that analyzes user patterns and generates AI-powered insights for the homepage
class AIInsightsService {
  final OpenAIService _openAIService;
  final ApiClient _apiClient;
  final OpenAIResponsesService? _responsesService;

  AIInsightsService({
    required OpenAIService openAIService,
    required ApiClient apiClient,
    OpenAIResponsesService? responsesService,
  })  : _openAIService = openAIService,
        _apiClient = apiClient,
        _responsesService = responsesService ?? getIt<OpenAIResponsesService>();

  /// Stream homepage insights using the Responses API (o3 streaming).
  /// onDelta receives incremental text; onFinal receives the parsed AIInsight.
  Future<void> streamHomepageInsights({
    required bool preferMetric,
    required String username,
    required void Function(String delta) onDelta,
    required void Function(AIInsight insight) onFinal,
    void Function(Object error)? onError,
  }) async {
    try {
      final now = DateTime.now();
      final timeOfDay = _getTimeOfDay(now);
      final dayOfWeek = DateFormat('EEEE').format(now);

      // Fetch user insights and coaching plan data in parallel
      final futures = await Future.wait([
        _fetchUserInsights(),
        _fetchCoachingPlanData(),
        _fetchCoachingPlanProgress(),
      ]);

      var insights = futures[0];
      final coachingPlan = futures[1];
      final coachingProgress = futures[2];

      if (insights.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
        insights = await _fetchUserInsights();
      }
      final context = _buildInsightContext(
        userInsights: insights,
        preferMetric: preferMetric,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        username: username,
        coachingPlan: coachingPlan,
        coachingProgress: coachingProgress,
      );
      final instructions = _buildInsightInstructions(context);
      final userInput = _buildUserContextInput(context);
      final sb = StringBuffer();
      bool gotDelta = false;
      AppLogger.info(
          '[AI_INSIGHTS] Streaming homepage insight (GPT-5 reasoning model)…');
      await _responsesService!.stream(
        model: _getReasoningModel(),
        instructions: instructions,
        input: userInput,
        store: false, // Don't store insights for privacy
        maxOutputTokens: 300,
        // Remove structured output for now - just get plain text JSON
        onDelta: (d) {
          sb.write(d);
          gotDelta = true;
          onDelta(d);
        },
        onComplete: (full) {
          AppLogger.info(
              '[AI_INSIGHTS] Stream complete; attempting to parse JSON. Snippet: ' +
                  (full.length > 200 ? full.substring(0, 200) : full));
          final insight = _parseAIResponse(full, context);
          onFinal(insight);
        },
        onError: (e) {
          if (onError != null) onError(e);
        },
      );
      // If we never received a delta, provide a non-streaming fallback for better UX
      if (!gotDelta) {
        AppLogger.warning(
            '[AI_INSIGHTS] Stream produced no deltas; falling back to non-streaming');
        final combinedPrompt = instructions + '\n\n' + userInput;
        final aiResponse = await _openAIService.generateMessage(
          context: {'prompt': combinedPrompt},
          personality: 'motivational',
          modelOverride: 'o3-mini',
          temperatureOverride: null,
          maxTokensOverride: null,
          timeoutOverride: const Duration(seconds: 15), // Increased from 10s
        );
        final insight = _parseAIResponse(aiResponse ?? '', context);
        onFinal(insight);
      }
    } catch (e) {
      if (onError != null) onError(e);
    }
  }

  /// Pre-warm the daily homepage insight cache so the widget renders instantly.
  /// Safe to call on app start or right after login.
  Future<void> prewarmHomepageInsights({
    required String userId,
    required bool preferMetric,
    required String username,
  }) async {
    try {
      final now = DateTime.now();
      final timeOfDay = _getTimeOfDay(now);
      final dayOfWeek = DateFormat('EEEE').format(now);
      // Create a temporary insight for caching (prewarm functionality)
      final insight = AIInsight(
        greeting: _getDefaultGreeting(timeOfDay, username),
        insight: 'Building your rucking habit...',
        recommendation: 'Start with a short ruck today.',
        motivation: 'Every step builds strength.',
        emoji: '🎒',
        generatedAt: DateTime.now(),
      );
      await _saveHomeCache(userId, insight);
      AppLogger.info(
          '[AI_INSIGHTS] Prewarmed homepage insight cache for $userId');
    } catch (e) {
      AppLogger.warning(
          '[AI_INSIGHTS] Failed to prewarm homepage insights: $e');
    }
  }

  // --- Helpers for prewarming ---
  String _getTimeOfDay(DateTime time) {
    final hour = time.hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    if (hour < 21) return 'evening';
    return 'night';
  }

  Future<void> _saveHomeCache(String userId, AIInsight insight) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          'ai_home_cache_${userId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
      final map = {
        'greeting': insight.greeting,
        'insight': insight.insight,
        'recommendation': insight.recommendation,
        'motivation': insight.motivation,
        'emoji': insight.emoji,
        'generatedAt': insight.generatedAt.toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  /// Fetch user insights snapshot from the API
  Future<Map<String, dynamic>> _fetchUserInsights() async {
    try {
      AppLogger.info(
          '[AI_INSIGHTS] Fetching user insights from ${ApiEndpoints.userInsights}?fresh=1');
      final response = await _apiClient.get(
        ApiEndpoints.userInsights,
        queryParams: {'fresh': 1},
      );
      // Server returns { insights: {...} }
      final map = Map<String, dynamic>.from(response ?? {});
      return Map<String, dynamic>.from(map['insights'] ?? {});
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to fetch user insights: $e');
      return {};
    }
  }

  /// Fetch user's active coaching plan data
  Future<Map<String, dynamic>> _fetchCoachingPlanData() async {
    try {
      AppLogger.info('[AI_INSIGHTS] Fetching coaching plan data');
      final response = await _apiClient.get(ApiEndpoints.userCoachingPlans);
      return Map<String, dynamic>.from(response ?? {});
    } catch (e) {
      AppLogger.info(
          '[AI_INSIGHTS] No active coaching plan or error fetching: $e');
      return {};
    }
  }

  /// Fetch detailed coaching plan progress
  Future<Map<String, dynamic>> _fetchCoachingPlanProgress() async {
    try {
      final response =
          await _apiClient.get(ApiEndpoints.userCoachingPlanProgress);
      return Map<String, dynamic>.from(response ?? {});
    } catch (e) {
      AppLogger.info('[AI_INSIGHTS] No coaching plan progress available: $e');
      return {};
    }
  }

  Map<String, dynamic> _buildInsightContext({
    required Map<String, dynamic> userInsights,
    required bool preferMetric,
    required String timeOfDay,
    required String dayOfWeek,
    required String username,
    Map<String, dynamic>? coachingPlan,
    Map<String, dynamic>? coachingProgress,
  }) {
    // Extract from user_insights snapshot
    final facts = Map<String, dynamic>.from(userInsights['facts'] ?? const {});
    final achievementsRecent =
        (facts['achievements_recent'] as List?) ?? const [];
    final totals30 = Map<String, dynamic>.from(facts['totals_30d'] ?? const {});
    final allTime = Map<String, dynamic>.from(facts['all_time'] ?? const {});
    final recency = Map<String, dynamic>.from(facts['recency'] ?? const {});
    final demographics =
        Map<String, dynamic>.from(facts['demographics'] ?? const {});
    final userBlock = Map<String, dynamic>.from(facts['user'] ?? const {});
    final profile = Map<String, dynamic>.from(facts['profile'] ?? userBlock);
    final integrations =
        Map<String, dynamic>.from(facts['integrations'] ?? const {});
    final streak = Map<String, dynamic>.from(facts['streak'] ?? const {});

    // Extract rich behavioral patterns from full user insights
    final triggers = _safeList(userInsights['triggers']);
    final achievements = _safeList(userInsights['achievements']);
    final activity =
        Map<String, dynamic>.from(userInsights['activity'] ?? const {});

    final context = <String, dynamic>{
      'username': username,
      'timeOfDay': timeOfDay,
      'dayOfWeek': dayOfWeek,
      'preferMetric': preferMetric,
      'sessionCount': (totals30['sessions'] as int?) ?? 0,
      'totalDistance': (allTime['distance_km'] as num?)?.toDouble() ?? 0.0,
      'averageDistance': (() {
        final dist = (totals30['distance_km'] as num?)?.toDouble() ?? 0.0;
        final sessions = (totals30['sessions'] as int?) ?? 0;
        return sessions > 0 ? dist / sessions : 0.0;
      })(),
      'achievementCount': achievementsRecent.length,
      'hasRecentActivity': recency['last_completed_at'] != null,
      // Personalization helpers
      'allTimeSessions': (allTime['sessions'] as int?) ?? 0,
      'gender': (demographics['gender'] ?? userBlock['gender'])
          ?.toString()
          .toLowerCase(),
      // Profile/integrations
      'hasProfilePhoto': _coerceBool(profile['has_avatar']) ??
          ((profile['avatar_url'] ?? userBlock['avatar_url'])
                  ?.toString()
                  .isNotEmpty ==
              true),
      'isStravaConnected': _coerceBool(integrations['strava_connected']) ??
          _coerceBool(facts['strava_connected']) ??
          false,
      'streakDays': (streak['days'] as num?)?.toInt(),

      // Rich behavioral patterns - with error handling
      'behavioralTriggers':
          _safeExtractPatterns(() => _extractBehavioralTriggers(triggers)),
      'achievementPatterns':
          _safeExtractPatterns(() => _extractAchievementPatterns(achievements)),
      'timingPatterns':
          _safeExtractPatterns(() => _extractTimingPatterns(activity)),
      'weatherPatterns':
          _safeExtractPatterns(() => _extractWeatherPatterns(activity)),
      'progressionTrends': _safeExtractPatterns(
          () => _extractProgressionTrends(activity, allTime)),
      'personalityMarkers': _safeExtractPatterns(
          () => _extractPersonalityMarkers(achievements, triggers, recency)),
    };

    // Add recent activity fields from facts.recency if available
    final lastDist = (recency['last_ruck_distance_km'] as num?)?.toDouble();
    if (lastDist != null) context['lastRuckDistance'] = lastDist;
    final dsl = recency['days_since_last'];
    if (dsl != null)
      context['daysSinceLastRuck'] =
          (dsl is num) ? dsl.round() : int.tryParse('$dsl');

    // Simple milestone helpers
    final totalSessions = (allTime['sessions'] as num?)?.toInt() ?? 0;
    context['sessionsTo100'] = (100 - totalSessions).clamp(0, 100);

    // Add coaching plan context if available
    if (coachingPlan != null && coachingPlan.isNotEmpty) {
      context['hasCoachingPlan'] = true;
      context['coachingPlan'] = {
        'name': coachingPlan['plan_name'] ?? 'Training Plan',
        'duration': coachingPlan['duration_weeks'] ?? 0,
        'difficulty': coachingPlan['difficulty_level'] ?? 'beginner',
        'goal': coachingPlan['goal'] ?? '',
        'phase': coachingPlan['current_phase'] ?? 'preparation',
        'weekNumber': coachingPlan['current_week'] ?? 1,
      };
    } else {
      context['hasCoachingPlan'] = false;
    }

    // Add coaching progress context if available
    if (coachingProgress != null && coachingProgress.isNotEmpty) {
      context['coachingProgress'] = {
        'adherence': coachingProgress['adherence_percentage'] ?? 0,
        'completedSessions': coachingProgress['completed_sessions'] ?? 0,
        'totalSessions': coachingProgress['total_sessions'] ?? 0,
        'nextSession': coachingProgress['next_session'],
        'isOnTrack': (coachingProgress['adherence_percentage'] ?? 0) >= 70,
        'daysInPlan': coachingProgress['days_in_plan'] ?? 0,
        'recommendations': coachingProgress['recommendations'] ?? [],
      };
    }

    return context;
  }

  String _buildInsightInstructions(Map<String, dynamic> context) {
    final distanceUnit = context['preferMetric'] ? 'km' : 'miles';
    final gender = (context['gender'] as String?) ?? '';
    final isFirstSession = ((context['allTimeSessions'] as int? ?? 0) == 0);

    String toneGuidance;
    if (gender == 'female') {
      toneGuidance =
          '- Tone: Empowering, supportive, and empathetic. Avoid macho language.';
    } else if (gender == 'male') {
      toneGuidance =
          '- Tone: Tough, playful, and motivating. Keep it respectful.';
    } else {
      toneGuidance = '- Tone: Balanced, encouraging, and inclusive.';
    }

    final firstSessionGuidance = isFirstSession
        ? '- First-time guidance: This is their first session. Thank them for joining and encourage a simple start: "Try 5 minutes, even without weight, to earn your first achievement." Keep it approachable.\n'
            '- First-time primer: Append ONE factual sentence on what rucking is and why it helps (e.g., "Rucking = brisk walking with a backpack; burns ~2–3× walking calories and builds leg/core strength with low impact.")'
        : '';

    // Extract rich behavioral patterns for more creative insights
    final behavioralTriggers =
        context['behavioralTriggers'] as Map<String, dynamic>? ?? {};
    final achievementPatterns =
        context['achievementPatterns'] as Map<String, dynamic>? ?? {};
    final timingPatterns =
        context['timingPatterns'] as Map<String, dynamic>? ?? {};
    final weatherPatterns =
        context['weatherPatterns'] as Map<String, dynamic>? ?? {};
    final progressionTrends =
        context['progressionTrends'] as Map<String, dynamic>? ?? {};
    final personalityMarkers =
        context['personalityMarkers'] as Map<String, dynamic>? ?? {};

    return '''
Generate a personalized, motivational homepage insight for a rucking app user.

Basic Context:
- Username: ${context['username']}
- Current time: ${context['timeOfDay']} on ${context['dayOfWeek']}
- Recent sessions: ${context['sessionCount']}
- Total distance: ${context['totalDistance']} $distanceUnit
- Average distance: ${context['averageDistance']} $distanceUnit
- Total achievements: ${context['achievementCount']}
- Has recent activity: ${context['hasRecentActivity']}
${context['daysSinceLastRuck'] != null ? '- Days since last ruck: ${context['daysSinceLastRuck']}' : ''}
${context['lastRuckDistance'] != null ? '- Last ruck distance: ${context['lastRuckDistance']} $distanceUnit' : ''}
- Profile: ${context['hasProfilePhoto'] == true ? 'has photo' : 'no photo'}; Strava: ${context['isStravaConnected'] == true ? 'connected' : 'not connected'}
${context['streakDays'] != null ? '- Streak days: ${context['streakDays']}' : ''}
- Sessions to 100: ${context['sessionsTo100']}

Rich Behavioral Patterns (USE THESE FOR CREATIVE INSIGHTS):
- Personality Type: ${personalityMarkers['personalityType']} (motivation: ${personalityMarkers['motivationStyle']})
- Behavioral Focus: ${achievementPatterns['focusAreas']?.join(', ') ?? 'balanced'}
- Timing Preferences: ${timingPatterns['preferredTimeSlots']?.join(', ') ?? 'flexible'}${timingPatterns['isEarlyMorningRucker'] == true ? ' (early bird!)' : ''}
- Weather Tolerance: ${weatherPatterns['weatherTolerance']}${weatherPatterns['coldWeatherWarrior'] == true ? ' (cold warrior)' : ''}
- Progression Style: ${progressionTrends['improvementTrend']} trend, ${achievementPatterns['progressionStyle']} achiever
- Challenge Elements: ${behavioralTriggers['hasPersonalChallenge'] == true ? 'self-challenger' : 'steady builder'}
- Motivation Themes: ${behavioralTriggers['motivationThemes']?.join(', ') ?? 'general fitness'}

Coaching Plan Context:
${context['hasCoachingPlan'] == true ? '''- Active Plan: "${context['coachingPlan']?['name']}" (Week ${context['coachingPlan']?['weekNumber']} of ${context['coachingPlan']?['duration']}, ${context['coachingPlan']?['phase']} phase)
- Plan Goal: ${context['coachingPlan']?['goal'] ?? 'fitness improvement'}
- Difficulty: ${context['coachingPlan']?['difficulty']} level
${context['coachingProgress'] != null ? '''- Progress: ${context['coachingProgress']?['adherence']}% adherence (${context['coachingProgress']?['completedSessions']}/${context['coachingProgress']?['totalSessions']} sessions)
- Status: ${context['coachingProgress']?['isOnTrack'] == true ? 'ON TRACK' : 'NEEDS FOCUS'}
- Next Session: ${context['coachingProgress']?['nextSession']?['type'] ?? 'TBD'} ${context['coachingProgress']?['nextSession']?['distance_km'] != null ? '(${(context['coachingProgress']?['nextSession']?['distance_km'] * (context['preferMetric'] ? 1 : 0.621371)).toStringAsFixed(1)} $distanceUnit)' : ''}
${context['coachingProgress']?['recommendations']?.isNotEmpty == true ? '- Coach Recommendations: ${(context['coachingProgress']?['recommendations'] as List).join(', ')}' : ''}''' : ''}''' : '- No active coaching plan'}

CRITICAL: Combine behavioral insights WITH concrete stats. Use both the rich behavioral patterns AND the basic numbers to create insights that are both personal and grounded in data. For example: "Your 5:30am habit + 2 sessions this month shows real commitment" rather than just "you're consistent."

Special Guidelines:
$toneGuidance
$firstSessionGuidance
- Data-driven insights: ALWAYS include at least one concrete stat (sessions, distance, streak, achievements, etc.) combined with behavioral context
- Pattern + Numbers: Merge behavioral patterns with actual numbers ("Your distance-focused 15.2 miles total shows...")
- Personality-driven tone: Match tone to their personality type (${personalityMarkers['personalityType']}) and motivation style (${personalityMarkers['motivationStyle']})
- Concrete recommendations: Include specific distance/time targets based on their history and patterns
- Weather: If provided, make it qualitative: compare to last ruck (warmer/cooler, windier/calmer), note likely rain window later today if relevant, or suggest a best 1–2 hour start window.
- Balance insights: Use BOTH behavioral patterns AND hard numbers - never ignore the basic stats
- Account nudges: At most ONE gentle nudge if applicable: if no profile photo, suggest adding one; if Strava not connected and they seem social/competitive, suggest connecting. Keep it brief and optional; do not scold.
- Use the user's preferred units ($distanceUnit).
- Be concise and concrete. One distinct idea per field.
- Do not mention BPM, medical advice, or anything not present in context.

COACHING PLAN INTEGRATION:
${context['hasCoachingPlan'] == true ? '''- PRIORITIZE coaching plan context: The user has an active plan - focus insights and recommendations around their plan progress
- Plan-driven insights: Reference their current phase, week, and adherence when relevant
- Next session focus: If next session details available, tailor recommendation to that specific workout
- Progress acknowledgment: Acknowledge their plan adherence and progress (${context['coachingProgress']?['isOnTrack'] == true ? 'on track' : 'needing encouragement'})
- Coach recommendations: Incorporate any coach recommendations into your advice''' : '''- No coaching plan: Focus on general rucking habits and suggest considering a structured plan if they seem goal-oriented'''}

Generate a JSON response with:
{
  "greeting": "Time-appropriate greeting with name that reflects their personality/timing patterns",
  "insight": "Behavioral insight that INCLUDES concrete stats (sessions, distance, achievements, streak) combined with personality patterns${context['hasCoachingPlan'] == true ? ' and coaching plan progress' : ''}",
  "recommendation": "Specific action with target distance/time based on their history, patterns, and behavioral style${context['hasCoachingPlan'] == true ? ', prioritizing their coaching plan next session' : ''}",
  "motivation": "Encouraging line that combines their achievements/progress with their motivation style${context['hasCoachingPlan'] == true ? ' and plan adherence' : ''}",
  "emoji": "Single relevant emoji that matches their personality/focus area"
}

Respond with ONLY the JSON object. Do not include any other text or formatting.
Keep it concise, personal, and behaviorally-informed. Use their preferred units.
''';
  }

  String _buildUserContextInput(Map<String, dynamic> context) {
    final distanceUnit = context['preferMetric'] ? 'km' : 'miles';

    // Extract behavioral patterns
    final behavioralTriggers =
        context['behavioralTriggers'] as Map<String, dynamic>? ?? {};
    final achievementPatterns =
        context['achievementPatterns'] as Map<String, dynamic>? ?? {};
    final timingPatterns =
        context['timingPatterns'] as Map<String, dynamic>? ?? {};
    final weatherPatterns =
        context['weatherPatterns'] as Map<String, dynamic>? ?? {};
    final progressionTrends =
        context['progressionTrends'] as Map<String, dynamic>? ?? {};
    final personalityMarkers =
        context['personalityMarkers'] as Map<String, dynamic>? ?? {};

    return '''
User Context:
- Username: ${context['username']}
- Current time: ${context['timeOfDay']} on ${context['dayOfWeek']}
- Recent sessions: ${context['sessionCount']}
- Total distance: ${context['totalDistance']} $distanceUnit
- Average distance: ${context['averageDistance']} $distanceUnit
- Total achievements: ${context['achievementCount']}
- Has recent activity: ${context['hasRecentActivity']}
${context['daysSinceLastRuck'] != null ? '- Days since last ruck: ${context['daysSinceLastRuck']}' : ''}
${context['lastRuckDistance'] != null ? '- Last ruck distance: ${context['lastRuckDistance']} $distanceUnit' : ''}
- Profile: ${context['hasProfilePhoto'] == true ? 'has photo' : 'no photo'}; Strava: ${context['isStravaConnected'] == true ? 'connected' : 'not connected'}
${context['streakDays'] != null ? '- Streak days: ${context['streakDays']}' : ''}
- Sessions to 100: ${context['sessionsTo100']}

Behavioral Profile:
- Personality: ${personalityMarkers['personalityType']} type, ${personalityMarkers['motivationStyle']} motivation
- Achievement Focus: ${achievementPatterns['focusAreas']?.join(', ') ?? 'balanced approach'}
- Timing Style: ${timingPatterns['preferredTimeSlots']?.join(' or ') ?? 'flexible timing'}${timingPatterns['isEarlyMorningRucker'] == true ? ' (5:30am early bird)' : ''}
- Weather Profile: ${weatherPatterns['weatherTolerance']} tolerance${weatherPatterns['coldWeatherWarrior'] == true ? ', cold weather warrior' : ''}${weatherPatterns['rainTolerance'] == true ? ', rain-ready' : ''}
- Progress Pattern: ${progressionTrends['improvementTrend']} improvement, ${achievementPatterns['progressionStyle']} achievement pace
- Challenge Mindset: ${behavioralTriggers['hasPersonalChallenge'] == true ? 'self-challenger who pushes limits' : 'steady consistent builder'}
- Motivation Drivers: ${behavioralTriggers['motivationThemes']?.join(', ') ?? 'fitness and wellness'}

Active Coaching Plan:
${context['hasCoachingPlan'] == true ? '''- Plan: "${context['coachingPlan']?['name']}" (${context['coachingPlan']?['difficulty']} level)
- Current Status: Week ${context['coachingPlan']?['weekNumber']} of ${context['coachingPlan']?['duration']} (${context['coachingPlan']?['phase']} phase)
- Plan Goal: ${context['coachingPlan']?['goal']}
- Progress: ${context['coachingProgress']?['adherence']}% adherence (${context['coachingProgress']?['completedSessions']}/${context['coachingProgress']?['totalSessions']} sessions completed)
- Status: ${context['coachingProgress']?['isOnTrack'] == true ? 'ON TRACK with plan' : 'BEHIND SCHEDULE - needs encouragement'}
${context['coachingProgress']?['nextSession'] != null ? '''- Next Planned Session: ${context['coachingProgress']?['nextSession']?['type'] ?? 'workout'} ${context['coachingProgress']?['nextSession']?['distance_km'] != null ? 'at ${(context['coachingProgress']?['nextSession']?['distance_km'] * (context['preferMetric'] ? 1 : 0.621371)).toStringAsFixed(1)} $distanceUnit' : ''}
${context['coachingProgress']?['nextSession']?['notes'] != null ? '- Session Notes: ${context['coachingProgress']?['nextSession']?['notes']}' : ''}''' : ''}
${context['coachingProgress']?['recommendations']?.isNotEmpty == true ? '- Coach Recommendations: ${(context['coachingProgress']?['recommendations'] as List).join('; ')}' : ''}''' : '''- No active coaching plan (suggest structured training if user seems goal-oriented)'''}''';
  }

  /// Get the best available reasoning model for insights generation
  String _getReasoningModel() {
    // Use GPT-4.1 for better reasoning capabilities than GPT-4o
    return 'gpt-4.1-2025-04-14';
  }

  bool? _coerceBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  /// Extract behavioral triggers and motivation patterns
  Map<String, dynamic> _extractBehavioralTriggers(List<dynamic> triggers) {
    final patterns = <String, dynamic>{
      'hasGoalMilestone': false,
      'hasCompetitiveElement': false,
      'hasPersonalChallenge': false,
      'motivationThemes': <String>[],
    };

    for (final trigger in triggers) {
      if (trigger is Map<String, dynamic>) {
        final description =
            (trigger['description'] ?? '').toString().toLowerCase();
        final triggerType =
            (trigger['trigger_type'] ?? '').toString().toLowerCase();

        // Detect goal-oriented behavior
        if (description.contains('milestone') ||
            description.contains('goal') ||
            description.contains('target') ||
            triggerType.contains('milestone')) {
          patterns['hasGoalMilestone'] = true;
        }

        // Detect competitive elements
        if (description.contains('beat') ||
            description.contains('faster') ||
            description.contains('compete') ||
            description.contains('challenge others')) {
          patterns['hasCompetitiveElement'] = true;
        }

        // Detect personal challenge mindset
        if (description.contains('push') ||
            description.contains('test') ||
            description.contains('prove') ||
            description.contains('overcome')) {
          patterns['hasPersonalChallenge'] = true;
        }

        // Extract motivation themes
        final themes = patterns['motivationThemes'] as List<String>;
        if (description.contains('consistency') &&
            !themes.contains('consistency')) themes.add('consistency');
        if (description.contains('strength') && !themes.contains('strength'))
          themes.add('strength');
        if (description.contains('endurance') && !themes.contains('endurance'))
          themes.add('endurance');
        if (description.contains('mental') && !themes.contains('mental'))
          themes.add('mental');
      }
    }

    return patterns;
  }

  /// Extract achievement clustering and progression patterns
  Map<String, dynamic> _extractAchievementPatterns(List<dynamic> achievements) {
    final patterns = <String, dynamic>{
      'achievementClusters': <String>[],
      'recentAchievementTypes': <String>[],
      'progressionStyle': 'steady', // steady, burst, sporadic
      'focusAreas': <String>[],
    };

    if (achievements.isEmpty) return patterns;

    final clusters = patterns['achievementClusters'] as List<String>;
    final recentTypes = patterns['recentAchievementTypes'] as List<String>;
    final focusAreas = patterns['focusAreas'] as List<String>;

    final now = DateTime.now();
    var recentAchievements = 0;
    var distanceAchievements = 0;
    var frequencyAchievements = 0;
    var challengeAchievements = 0;

    for (final achievement in achievements) {
      if (achievement is Map<String, dynamic>) {
        final name = (achievement['name'] ?? '').toString().toLowerCase();
        final dateStr =
            achievement['date_achieved'] ?? achievement['created_at'];

        // Check if recent (last 30 days)
        if (dateStr != null) {
          final achievedDate = DateTime.tryParse(dateStr.toString());
          if (achievedDate != null &&
              now.difference(achievedDate).inDays <= 30) {
            recentAchievements++;
          }
        }

        // Categorize achievements
        if (name.contains('distance') ||
            name.contains('mile') ||
            name.contains('km')) {
          distanceAchievements++;
          if (!focusAreas.contains('distance')) focusAreas.add('distance');
        }
        if (name.contains('streak') ||
            name.contains('consistent') ||
            name.contains('daily')) {
          frequencyAchievements++;
          if (!focusAreas.contains('consistency'))
            focusAreas.add('consistency');
        }
        if (name.contains('challenge') ||
            name.contains('tough') ||
            name.contains('endurance')) {
          challengeAchievements++;
          if (!focusAreas.contains('endurance')) focusAreas.add('endurance');
        }
      }
    }

    // Determine progression style
    if (recentAchievements >= 3) {
      patterns['progressionStyle'] = 'burst';
    } else if (recentAchievements >= 1) {
      patterns['progressionStyle'] = 'steady';
    } else {
      patterns['progressionStyle'] = 'sporadic';
    }

    // Build clusters
    if (distanceAchievements > frequencyAchievements &&
        distanceAchievements > challengeAchievements) {
      clusters.add('distance-focused');
    }
    if (frequencyAchievements > distanceAchievements &&
        frequencyAchievements > challengeAchievements) {
      clusters.add('consistency-focused');
    }
    if (challengeAchievements > 0) {
      clusters.add('challenge-seeker');
    }

    return patterns;
  }

  /// Extract timing preferences and patterns
  Map<String, dynamic> _extractTimingPatterns(Map<String, dynamic> activity) {
    final patterns = <String, dynamic>{
      'preferredTimeSlots': <String>[],
      'isEarlyMorningRucker': false,
      'weekdayPreference': 'mixed', // weekend, weekday, mixed
      'consistentTiming': false,
    };

    final sessions = _safeList(activity['sessions']);
    final timeSlots = <String, int>{};
    var weekdayCount = 0;
    var weekendCount = 0;

    for (final session in sessions) {
      if (session is Map<String, dynamic>) {
        final startTime = session['start_time'];
        if (startTime != null) {
          final dateTime = DateTime.tryParse(startTime.toString());
          if (dateTime != null) {
            final hour = dateTime.hour;
            final dayOfWeek = dateTime.weekday;

            // Categorize time slots
            String timeSlot;
            if (hour >= 5 && hour < 8) {
              timeSlot = 'early-morning';
              patterns['isEarlyMorningRucker'] = true;
            } else if (hour >= 8 && hour < 12) {
              timeSlot = 'morning';
            } else if (hour >= 12 && hour < 17) {
              timeSlot = 'afternoon';
            } else if (hour >= 17 && hour < 20) {
              timeSlot = 'evening';
            } else {
              timeSlot = 'night';
            }

            timeSlots[timeSlot] = (timeSlots[timeSlot] ?? 0) + 1;

            // Track weekday vs weekend
            if (dayOfWeek <= 5) {
              weekdayCount++;
            } else {
              weekendCount++;
            }
          }
        }
      }
    }

    // Determine preferred time slots
    final sortedSlots = timeSlots.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final preferredSlots = patterns['preferredTimeSlots'] as List<String>;
    for (final entry in sortedSlots.take(2)) {
      if (entry.value >= 2) {
        // At least 2 sessions in this time slot
        preferredSlots.add(entry.key);
      }
    }

    // Determine weekday preference
    if (weekendCount > weekdayCount * 1.5) {
      patterns['weekdayPreference'] = 'weekend';
    } else if (weekdayCount > weekendCount * 1.5) {
      patterns['weekdayPreference'] = 'weekday';
    } else {
      patterns['weekdayPreference'] = 'mixed';
    }

    // Check timing consistency
    patterns['consistentTiming'] = preferredSlots.isNotEmpty &&
        timeSlots.values.any((count) => count >= 3);

    return patterns;
  }

  /// Extract weather tolerance and preferences
  Map<String, dynamic> _extractWeatherPatterns(Map<String, dynamic> activity) {
    final patterns = <String, dynamic>{
      'weatherTolerance': 'moderate', // high, moderate, low
      'coldWeatherWarrior': false,
      'rainTolerance': false,
      'temperatureRange': <String, num>{},
    };

    final sessions = _safeList(activity['sessions']);
    var coldSessions = 0; // Below 40F/4C
    var hotSessions = 0; // Above 80F/27C
    var rainSessions = 0;
    var totalWithWeather = 0;
    final temps = <double>[];

    for (final session in sessions) {
      if (session is Map<String, dynamic>) {
        final weather = session['weather'];
        if (weather is Map<String, dynamic>) {
          totalWithWeather++;

          final tempC = (weather['temperature_c'] as num?)?.toDouble();
          if (tempC != null) {
            temps.add(tempC);

            if (tempC <= 4) coldSessions++; // 40F or below
            if (tempC >= 27) hotSessions++; // 80F or above
          }

          final conditions =
              (weather['conditions'] ?? '').toString().toLowerCase();
          if (conditions.contains('rain') ||
              conditions.contains('drizzle') ||
              conditions.contains('shower')) {
            rainSessions++;
          }
        }
      }
    }

    if (totalWithWeather > 0) {
      // Weather tolerance assessment
      final coldTolerance = coldSessions / totalWithWeather;
      final rainTolerance = rainSessions / totalWithWeather;

      patterns['coldWeatherWarrior'] =
          coldTolerance >= 0.3; // 30% or more in cold
      patterns['rainTolerance'] = rainTolerance >= 0.2; // 20% or more in rain

      if (coldTolerance >= 0.3 || rainTolerance >= 0.2) {
        patterns['weatherTolerance'] = 'high';
      } else if (coldTolerance >= 0.1 || rainTolerance >= 0.1) {
        patterns['weatherTolerance'] = 'moderate';
      } else {
        patterns['weatherTolerance'] = 'low';
      }

      // Temperature range
      if (temps.isNotEmpty) {
        temps.sort();
        patterns['temperatureRange'] = {
          'min': temps.first,
          'max': temps.last,
          'median': temps[temps.length ~/ 2],
        };
      }
    }

    return patterns;
  }

  /// Extract progression trends and improvement patterns
  Map<String, dynamic> _extractProgressionTrends(
      Map<String, dynamic> activity, Map<String, dynamic> allTime) {
    final patterns = <String, dynamic>{
      'improvementTrend': 'stable', // improving, stable, declining
      'distanceProgression': 'consistent', // increasing, consistent, varied
      'hasLongBreaks': false,
      'seasonalPattern': null,
    };

    final sessions = _safeList(activity['sessions']);
    if (sessions.length < 3) return patterns;

    // Sort sessions by date
    final sortedSessions = sessions
        .where((s) => s is Map<String, dynamic> && s['start_time'] != null)
        .toList();
    sortedSessions.sort((a, b) {
      final aTime = DateTime.tryParse(a['start_time'].toString());
      final bTime = DateTime.tryParse(b['start_time'].toString());
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });

    if (sortedSessions.length < 3) return patterns;

    // Analyze distance progression
    final distances = <double>[];
    final dates = <DateTime>[];
    DateTime? lastDate;
    var hasLongGap = false;

    for (final session in sortedSessions) {
      final distanceKm = (session['distance_km'] as num?)?.toDouble();
      final dateTime = DateTime.tryParse(session['start_time'].toString());

      if (distanceKm != null && dateTime != null) {
        distances.add(distanceKm);
        dates.add(dateTime);

        // Check for long breaks (>14 days)
        if (lastDate != null && dateTime.difference(lastDate).inDays > 14) {
          hasLongGap = true;
        }
        lastDate = dateTime;
      }
    }

    patterns['hasLongBreaks'] = hasLongGap;

    if (distances.length >= 3) {
      // Analyze distance trends (compare first third to last third)
      final firstThird = distances.take(distances.length ~/ 3).toList();
      final lastThird = distances.skip(distances.length * 2 ~/ 3).toList();

      final avgFirst = firstThird.reduce((a, b) => a + b) / firstThird.length;
      final avgLast = lastThird.reduce((a, b) => a + b) / lastThird.length;

      if (avgLast > avgFirst * 1.1) {
        patterns['distanceProgression'] = 'increasing';
        patterns['improvementTrend'] = 'improving';
      } else if (avgLast < avgFirst * 0.9) {
        patterns['distanceProgression'] = 'decreasing';
        patterns['improvementTrend'] = 'declining';
      } else {
        // Check for consistency vs variation
        final stdDev = _calculateStdDev(distances);
        final avgDistance =
            distances.reduce((a, b) => a + b) / distances.length;
        final coefficientOfVariation = stdDev / avgDistance;

        if (coefficientOfVariation < 0.3) {
          patterns['distanceProgression'] = 'consistent';
        } else {
          patterns['distanceProgression'] = 'varied';
        }
      }
    }

    return patterns;
  }

  /// Extract personality markers from behavior
  Map<String, dynamic> _extractPersonalityMarkers(List<dynamic> achievements,
      List<dynamic> triggers, Map<String, dynamic> recency) {
    final markers = <String, dynamic>{
      'personalityType': 'balanced', // consistent, challenger, explorer, social
      'motivationStyle': 'intrinsic', // intrinsic, extrinsic, mixed
      'riskTolerance': 'moderate', // high, moderate, low
      'goalOrientation': 'process', // outcome, process, mixed
    };

    // Analyze achievement types for personality indicators
    var challengeCount = 0;
    var consistencyCount = 0;
    var explorationCount = 0;

    for (final achievement in achievements) {
      if (achievement is Map<String, dynamic>) {
        final name = (achievement['name'] ?? '').toString().toLowerCase();

        if (name.contains('challenge') ||
            name.contains('tough') ||
            name.contains('endurance')) {
          challengeCount++;
        }
        if (name.contains('streak') ||
            name.contains('consistent') ||
            name.contains('regular')) {
          consistencyCount++;
        }
        if (name.contains('explore') ||
            name.contains('distance') ||
            name.contains('new')) {
          explorationCount++;
        }
      }
    }

    // Determine personality type
    final maxCount = [challengeCount, consistencyCount, explorationCount]
        .reduce((a, b) => a > b ? a : b);
    if (maxCount > 0) {
      if (challengeCount == maxCount) {
        markers['personalityType'] = 'challenger';
        markers['riskTolerance'] = 'high';
      } else if (consistencyCount == maxCount) {
        markers['personalityType'] = 'consistent';
        markers['goalOrientation'] = 'process';
      } else if (explorationCount == maxCount) {
        markers['personalityType'] = 'explorer';
        markers['goalOrientation'] = 'mixed';
      }
    }

    // Analyze triggers for motivation style
    var intrinsicCount = 0;
    var extrinsicCount = 0;

    for (final trigger in triggers) {
      if (trigger is Map<String, dynamic>) {
        final description =
            (trigger['description'] ?? '').toString().toLowerCase();

        if (description.contains('personal') ||
            description.contains('self') ||
            description.contains('feel') ||
            description.contains('health')) {
          intrinsicCount++;
        }
        if (description.contains('beat') ||
            description.contains('compare') ||
            description.contains('show') ||
            description.contains('prove to others')) {
          extrinsicCount++;
        }
      }
    }

    if (intrinsicCount > extrinsicCount) {
      markers['motivationStyle'] = 'intrinsic';
    } else if (extrinsicCount > intrinsicCount) {
      markers['motivationStyle'] = 'extrinsic';
    } else {
      markers['motivationStyle'] = 'mixed';
    }

    return markers;
  }

  double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sumOfSquaredDiffs =
        values.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b);
    return math.sqrt(sumOfSquaredDiffs / values.length);
  }

  /// Safely extract a list from dynamic data, handling various data types
  List<dynamic> _safeList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    if (value is Map<String, dynamic>) {
      // If it's a map, try to extract values or convert to list
      final values = value.values.toList();
      return values.where((v) => v != null).toList();
    }
    return const [];
  }

  /// Safely extract behavioral patterns with error handling
  Map<String, dynamic> _safeExtractPatterns(
      Map<String, dynamic> Function() extractor) {
    try {
      return extractor();
    } catch (e) {
      AppLogger.warning('[AI_INSIGHTS] Pattern extraction error: $e');
      return <String, dynamic>{};
    }
  }

  String _buildWeatherDeltaSnippet(
      CurrentWeather current, CurrentWeather last, bool preferMetric) {
    double toUserTemp(double c) => preferMetric ? c : (c * 9 / 5 + 32);
    int t(double? c) => toUserTemp(c ?? 0).round();
    final tempUnit = preferMetric ? '°C' : '°F';
    final nowT = t(current.temperature);
    final lastT = t(last.temperature);
    final deltaT = nowT - lastT;
    final deltaStr = deltaT == 0
        ? 'same temp'
        : (deltaT > 0
            ? '+$deltaT$tempUnit warmer'
            : '${deltaT}$tempUnit cooler');
    double toUserWind(double kph) => preferMetric ? kph : (kph * 0.621371);
    final nowWind = toUserWind((current.windSpeed ?? 0).toDouble()).round();
    final lastWind = toUserWind((last.windSpeed ?? 0).toDouble()).round();
    final windUnit = preferMetric ? 'km/h' : 'mph';
    final windDiff = nowWind - lastWind;
    final windStr = windDiff == 0
        ? 'similar wind'
        : (windDiff > 0
            ? '+$windDiff $windUnit wind'
            : '${windDiff} $windUnit wind');
    String cond(int? code) {
      final c = code ?? 800;
      if (c >= 200 && c <= 232) return 'thunderstorms';
      if ((c >= 300 && c <= 321) || (c >= 500 && c <= 519)) return 'rain';
      if (c >= 520 && c <= 531) return 'heavy rain';
      if (c >= 600 && c <= 622) return 'snow';
      if (c >= 700 && c <= 781) return 'low visibility';
      if (c == 800) return 'clear';
      if (c >= 801 && c <= 804) return 'clouds';
      return 'mixed';
    }

    final todayCond = cond(current.conditionCode);
    final lastCond = cond(last.conditionCode);
    final condDelta =
        todayCond == lastCond ? todayCond : '$todayCond vs $lastCond';
    return 'today $nowT$tempUnit, $todayCond, $nowWind $windUnit; last ruck $lastT$tempUnit, $lastCond → $deltaStr, $windStr';
  }

  AIInsight _parseAIResponse(String response, Map<String, dynamic> context) {
    try {
      // Normalize common wrappers like fenced code blocks
      String cleaned = response.trim();
      if (cleaned.startsWith('```')) {
        // Remove optional language identifier and closing fence
        final firstNewline = cleaned.indexOf('\n');
        if (firstNewline != -1) {
          cleaned = cleaned.substring(firstNewline + 1);
        }
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3).trim();
        }
      }

      Map<String, dynamic> parsed;
      try {
        parsed = Map<String, dynamic>.from(jsonDecode(cleaned));
      } catch (_) {
        // Try to extract the first JSON object from the text (fallback)
        final extracted = _extractJsonObjectFromText(cleaned);
        if (extracted != null) {
          parsed = extracted;
        } else {
          throw FormatException('No JSON object found in AI response');
        }
      }
      return AIInsight(
        greeting: parsed['greeting'] ??
            _getDefaultGreeting(context['timeOfDay'], context['username']),
        insight: parsed['insight'] ?? _fallbackInsightLine(context),
        recommendation:
            parsed['recommendation'] ?? _fallbackRecommendationLine(context),
        motivation: parsed['motivation'] ?? _fallbackMotivationLine(context),
        emoji: parsed['emoji'] ?? '🎒',
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      AppLogger.warning(
          '[AI_INSIGHTS] Failed to parse AI response, using fallback: $e');
      return _getFallbackInsightFromContext(context);
    }
  }

  /// Extracts the first top-level JSON object from text, tolerating extra prose.
  Map<String, dynamic>? _extractJsonObjectFromText(String text) {
    final start = text.indexOf('{');
    if (start == -1) return null;
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          final candidate = text.substring(start, i + 1);
          try {
            final obj = jsonDecode(candidate);
            if (obj is Map<String, dynamic>) return obj;
          } catch (_) {
            // continue scanning in case of nested braces in strings
          }
        }
      }
    }
    return null;
  }

  AIInsight _getFallbackInsightFromContext(Map<String, dynamic> ctx) {
    final String timeOfDay = (ctx['timeOfDay'] ?? 'morning').toString();
    final String username = (ctx['username'] ?? 'Rucker').toString();
    final bool preferMetric = (ctx['preferMetric'] as bool?) ?? true;

    final greeting = _getDefaultGreeting(timeOfDay, username);

    final insight = _fallbackInsightLine(ctx);
    final recommendation = _fallbackRecommendationLine(ctx);
    final motivation = _fallbackMotivationLine(ctx);

    return AIInsight(
      greeting: greeting,
      insight: insight,
      recommendation: recommendation,
      motivation: motivation,
      emoji: '🎒',
      generatedAt: DateTime.now(),
    );
  }

  String _fallbackInsightLine(Map<String, dynamic> ctx) {
    final bool preferMetric = (ctx['preferMetric'] as bool?) ?? true;
    final unit = preferMetric ? 'km' : 'mi';
    double toUser(double km) => preferMetric ? km : (km * 0.621371);

    final int? dsl = (ctx['daysSinceLastRuck'] as int?);
    final double? last = (ctx['lastRuckDistance'] as num?)?.toDouble();
    final int recent = (ctx['sessionCount'] as int?) ?? 0;
    final double avg =
        toUser(((ctx['averageDistance'] as num?)?.toDouble() ?? 0.0));

    if (dsl != null && dsl == 0) {
      return 'You got a ruck in today—nice work.';
    }
    if (dsl != null && dsl == 1) {
      return 'Yesterday’s ruck logged. Keep the streak alive.';
    }
    if (dsl != null && dsl > 1 && last != null) {
      final lastUser = toUser(last).toStringAsFixed(1);
      return 'Last ruck ${dsl}d ago at ${lastUser} $unit.';
    }
    if (recent > 0 && avg > 0) {
      return 'Past 30d: ~${avg.toStringAsFixed(1)} $unit per ruck.';
    }
    return 'Let’s build a simple, steady habit.';
  }

  String _fallbackRecommendationLine(Map<String, dynamic> ctx) {
    final bool preferMetric = (ctx['preferMetric'] as bool?) ?? true;
    final unit = preferMetric ? 'km' : 'mi';
    double toUser(double km) => preferMetric ? km : (km * 0.621371);

    final int? dsl = (ctx['daysSinceLastRuck'] as int?);
    final double avgKm = ((ctx['averageDistance'] as num?)?.toDouble() ?? 0.0);
    final double base = avgKm > 0 ? avgKm : 3.0; // sensible default
    final double goalUser = toUser(base.clamp(2.0, 5.0));

    if (dsl != null && dsl >= 3) {
      return 'Reset with a short ${goalUser.toStringAsFixed(1)} $unit easy loop.';
    }
    return 'Aim for about ${goalUser.toStringAsFixed(1)} $unit today—easy pace.';
  }

  String _fallbackMotivationLine(Map<String, dynamic> ctx) {
    final int recent = (ctx['sessionCount'] as int?) ?? 0;
    if (recent >= 4)
      return 'Consistency is your superpower. Keep stacking days.';
    if (recent >= 1) return 'Small steps compound. Lace up and go.';
    return 'Start light, stay steady. You’ve got this.';
  }

  String _getDefaultGreeting(String timeOfDay, String username) {
    final greetings = {
      'morning': 'Good morning',
      'afternoon': 'Good afternoon',
      'evening': 'Good evening',
      'night': 'Good evening',
    };
    return '${greetings[timeOfDay] ?? 'Hello'}, $username!';
  }
}

/// AI-generated insight for homepage
class AIInsight {
  final String greeting;
  final String insight;
  final String recommendation;
  final String motivation;
  final String emoji;
  final DateTime generatedAt;

  AIInsight({
    required this.greeting,
    required this.insight,
    required this.recommendation,
    required this.motivation,
    required this.emoji,
    required this.generatedAt,
  });

  /// Check if insight is stale (older than 4 hours)
  bool get isStale {
    return DateTime.now().difference(generatedAt).inHours > 4;
  }
}
