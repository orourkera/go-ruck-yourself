import 'dart:convert';
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';

/// Service that analyzes user patterns and generates AI-powered insights for the homepage
class AIInsightsService {
  final OpenAIService _openAIService;
  final ApiClient _apiClient;
  
  AIInsightsService({
    required OpenAIService openAIService,
    required ApiClient apiClient,
  }) : _openAIService = openAIService,
       _apiClient = apiClient;

  /// Generate personalized homepage insights based on user data from the API
  Future<AIInsight> generateHomepageInsights({
    required bool preferMetric,
    required String timeOfDay,
    required String dayOfWeek,
    required String username,
  }) async {
    try {
      AppLogger.info('[AI_INSIGHTS] Generating homepage insights for user');
      
      // Fetch user history data from the same endpoint used by AI cheerleader
      var userHistory = await _fetchUserHistory();
      // If history is empty (e.g., token not ready or slow network), retry once after a short delay
      if ((userHistory.isEmpty || (userHistory['recent_rucks'] as List?)?.isEmpty == true) &&
          (userHistory['aggregates'] == null)) {
        AppLogger.info('[AI_INSIGHTS] User history empty on first attempt – retrying shortly');
        await Future.delayed(const Duration(milliseconds: 600));
        userHistory = await _fetchUserHistory();
      }
      
      final context = _buildInsightContext(
        userHistory: userHistory,
        preferMetric: preferMetric,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        username: username,
      );

      final prompt = _buildInsightPrompt(context);
      final aiResponse = await _openAIService.generateMessage(
        context: {'prompt': prompt},
        personality: 'motivational',
      );
      AppLogger.info('[AI_INSIGHTS] Raw AI response: ${aiResponse != null ? aiResponse.substring(0, aiResponse.length > 200 ? 200 : aiResponse.length) : 'null'}');
      
      return _parseAIResponse(aiResponse ?? '', context);
      
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to generate insights: $e');
      return _getFallbackInsight(timeOfDay, username, preferMetric);
    }
  }

  /// Fetch user history from the API
  Future<Map<String, dynamic>> _fetchUserHistory() async {
    try {
      AppLogger.info('[AI_INSIGHTS] Fetching user history from ${ApiEndpoints.aiCheerleaderUserHistory}');
      final response = await _apiClient.get(ApiEndpoints.aiCheerleaderUserHistory, queryParams: {
        'rucks_limit': 20,  // Recent sessions for insights
        'achievements_limit': 20,  // Recent achievements
      });
      
      return Map<String, dynamic>.from(response ?? {});
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to fetch user history: $e');
      return {};
    }
  }

  Map<String, dynamic> _buildInsightContext({
    required Map<String, dynamic> userHistory,
    required bool preferMetric,
    required String timeOfDay,
    required String dayOfWeek,
    required String username,
  }) {
    // Extract data directly from API response
    final recentRucks = userHistory['recent_rucks'] as List<dynamic>? ?? [];
    final achievements = userHistory['recent_achievements'] as List<dynamic>? ?? [];
    final aggregates = userHistory['aggregates'] as Map<String, dynamic>? ?? {};
    
    final context = {
      'username': username,
      'timeOfDay': timeOfDay,
      'dayOfWeek': dayOfWeek,
      'preferMetric': preferMetric,
      'sessionCount': recentRucks.length,
      'totalDistance': aggregates['total_distance'] ?? 0.0,
      'totalCalories': aggregates['total_calories'] ?? 0,
      'averageDistance': aggregates['avg_distance'] ?? 0.0,
      'averageCalories': aggregates['avg_calories'] ?? 0,
      'achievementCount': achievements.length,
      'hasRecentActivity': recentRucks.isNotEmpty,
    };
    
    // Add recent activity insights if we have data
    if (recentRucks.isNotEmpty) {
      final recentRuck = recentRucks.first;
      context['lastRuckDistance'] = recentRuck['distance'] ?? 0.0;
      context['lastRuckCalories'] = recentRuck['calories_burned'] ?? 0;
      context['daysSinceLastRuck'] = recentRuck['completed_at'] != null 
          ? DateTime.now().difference(DateTime.parse(recentRuck['completed_at'])).inDays 
          : null;
    }


    return context;
  }

  String _buildInsightPrompt(Map<String, dynamic> context) {
    final distanceUnit = context['preferMetric'] ? 'km' : 'miles';
    
    return '''
Generate a personalized, motivational homepage insight for a rucking app user.

Context:
- Username: ${context['username']}
- Current time: ${context['timeOfDay']} on ${context['dayOfWeek']}
- Recent sessions: ${context['sessionCount']}
- Total distance: ${context['totalDistance']} $distanceUnit
- Average distance: ${context['averageDistance']} $distanceUnit
- Total achievements: ${context['achievementCount']}
- Has recent activity: ${context['hasRecentActivity']}
${context['daysSinceLastRuck'] != null ? '- Days since last ruck: ${context['daysSinceLastRuck']}' : ''}
${context['lastRuckDistance'] != null ? '- Last ruck distance: ${context['lastRuckDistance']} $distanceUnit' : ''}

Generate a JSON response with:
{
  "greeting": "Time-appropriate greeting with name",
  "insight": "Data-driven observation about their patterns/progress",
  "recommendation": "Specific, actionable suggestion for today",
  "motivation": "Encouraging message about their progress",
  "emoji": "Single relevant emoji"
}

Respond with ONLY the JSON object. Do not include any other text or formatting.
Keep it concise, personal, and motivating. Use their preferred units.
''';
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
        greeting: parsed['greeting'] ?? _getDefaultGreeting(context['timeOfDay'], context['username']),
        insight: parsed['insight'] ?? 'You\'re building great consistency!',
        recommendation: parsed['recommendation'] ?? 'Ready for your next ruck?',
        motivation: parsed['motivation'] ?? 'Keep up the great work!',
        emoji: parsed['emoji'] ?? '💪',
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      AppLogger.warning('[AI_INSIGHTS] Failed to parse AI response, using fallback: $e');
      return _getFallbackInsight(context['timeOfDay'], context['username'], context['preferMetric']);
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

  AIInsight _getFallbackInsight(String timeOfDay, String username, bool preferMetric) {
    final greetings = {
      'morning': 'Good morning',
      'afternoon': 'Good afternoon', 
      'evening': 'Good evening',
      'night': 'Ready for tomorrow',
    };
    
    final greeting = greetings[timeOfDay] ?? 'Hello';
    
    return AIInsight(
      greeting: '$greeting, $username!',
      insight: 'Your rucking journey is building momentum',
      recommendation: 'Ready to get after it today?',
      motivation: 'Every ruck makes you stronger! 💪',
      emoji: '🎯',
      generatedAt: DateTime.now(),
    );
  }

  String _getDefaultGreeting(String timeOfDay, String username) {
    final greetings = {
      'morning': 'Good morning',
      'afternoon': 'Good afternoon',
      'evening': 'Good evening', 
      'night': 'Hello',
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
