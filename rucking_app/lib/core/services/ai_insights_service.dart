import 'dart:convert';
import 'package:rucking_app/features/ai_cheerleader/services/openai_service.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/network/api_endpoints.dart';
import 'package:rucking_app/core/services/weather_service.dart';
import 'package:rucking_app/core/services/location_service.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/models/weather.dart';
import 'package:rucking_app/features/ai_cheerleader/services/location_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

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
      
      // Base context so we always have something meaningful for fallbacks
      Map<String, dynamic> context = {
        'username': username,
        'timeOfDay': timeOfDay,
        'dayOfWeek': dayOfWeek,
        'preferMetric': preferMetric,
        'sessionCount': 0,
        'totalDistance': 0.0,
        'averageDistance': 0.0,
        'achievementCount': 0,
        'hasRecentActivity': false,
        'allTimeSessions': 0,
      };

      // Fetch user insights snapshot (facts + triggers) from the new endpoint
      var insights = await _fetchUserInsights();
      // Retry once if empty (token ramp-up/network blip)
      if (insights.isEmpty) {
        AppLogger.info('[AI_INSIGHTS] user_insights empty on first attempt – retrying shortly');
        await Future.delayed(const Duration(milliseconds: 600));
        insights = await _fetchUserInsights();
      }
      
      context = _buildInsightContext(
        userInsights: insights,
        preferMetric: preferMetric,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        username: username,
      );

      // Optional: enrich with weather today vs last ruck day
      String weatherAddon = '';
      try {
        final recency = Map<String, dynamic>.from(insights['facts']?['recency'] ?? const {});
        final lastCompletedAtStr = recency['last_completed_at'] as String?;
        if (lastCompletedAtStr != null) {
          final lastCompletedAt = DateTime.tryParse(lastCompletedAtStr);
          final loc = await getIt<LocationService>().getCurrentLocation();
          if (loc != null && lastCompletedAt != null) {
            // Mirror AI Cheerleader path: use LocationContextService to fetch current weather for the same coords
            final lcs = getIt<LocationContextService>();
            final ctx = await lcs.getLocationContext(loc.latitude, loc.longitude);
            final CurrentWeather? today = ctx?.weather?.currentWeather;
            final WeatherService ws = WeatherService();
            final Weather? lastWxWrap = await ws.getWeatherForecast(
              latitude: loc.latitude,
              longitude: loc.longitude,
              date: lastCompletedAt,
              datasets: const ['currentWeather','dailyForecast'],
            );
            final CurrentWeather? last = lastWxWrap?.currentWeather;
            if (today != null && last != null) {
              weatherAddon = _buildWeatherDeltaSnippet(today, last, preferMetric);
            }
          }
        }
      } catch (e) {
        AppLogger.warning('[AI_INSIGHTS] Weather enrichment skipped: $e');
      }

      if (weatherAddon.isNotEmpty) {
        AppLogger.info('[AI_INSIGHTS] Weather addon for prompt: $weatherAddon');
      } else {
        AppLogger.info('[AI_INSIGHTS] Weather addon empty (no location/last ruck/weather data)');
      }
      final prompt = _buildInsightPrompt(context, weatherAddon: weatherAddon);
      final aiResponse = await _openAIService.generateMessage(
        context: {'prompt': prompt},
        personality: 'motivational',
      );
      AppLogger.info('[AI_INSIGHTS] Raw AI response: ${aiResponse != null ? aiResponse.substring(0, aiResponse.length > 200 ? 200 : aiResponse.length) : 'null'}');
      
      return _parseAIResponse(aiResponse ?? '', context);
      
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to generate insights: $e');
      return _getFallbackInsightFromContext({
        'timeOfDay': timeOfDay,
        'username': username,
        'preferMetric': preferMetric,
      });
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
      final insight = await generateHomepageInsights(
        preferMetric: preferMetric,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        username: username,
      );
      await _saveHomeCache(userId, insight);
      AppLogger.info('[AI_INSIGHTS] Prewarmed homepage insight cache for $userId');
    } catch (e) {
      AppLogger.warning('[AI_INSIGHTS] Failed to prewarm homepage insights: $e');
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
      final key = 'ai_home_cache_${userId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
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
      AppLogger.info('[AI_INSIGHTS] Fetching user insights from ${ApiEndpoints.userInsights}?fresh=1');
      final response = await _apiClient.get(
        ApiEndpoints.userInsights,
        queryParams: { 'fresh': 1 },
      );
      // Server returns { insights: {...} }
      final map = Map<String, dynamic>.from(response ?? {});
      return Map<String, dynamic>.from(map['insights'] ?? {});
    } catch (e) {
      AppLogger.error('[AI_INSIGHTS] Failed to fetch user insights: $e');
      return {};
    }
  }

  Map<String, dynamic> _buildInsightContext({
    required Map<String, dynamic> userInsights,
    required bool preferMetric,
    required String timeOfDay,
    required String dayOfWeek,
    required String username,
  }) {
    // Extract from user_insights snapshot
    final facts = Map<String, dynamic>.from(userInsights['facts'] ?? const {});
    final achievementsRecent = (facts['achievements_recent'] as List?) ?? const [];
    final totals30 = Map<String, dynamic>.from(facts['totals_30d'] ?? const {});
    final allTime = Map<String, dynamic>.from(facts['all_time'] ?? const {});
    final recency = Map<String, dynamic>.from(facts['recency'] ?? const {});
    final demographics = Map<String, dynamic>.from(facts['demographics'] ?? const {});
    final userBlock = Map<String, dynamic>.from(facts['user'] ?? const {});

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
      'gender': (demographics['gender'] ?? userBlock['gender'])?.toString().toLowerCase(),
    };
    
    // Add recent activity fields from facts.recency if available
    final lastDist = (recency['last_ruck_distance_km'] as num?)?.toDouble();
    if (lastDist != null) context['lastRuckDistance'] = lastDist;
    final dsl = recency['days_since_last'];
    if (dsl != null) context['daysSinceLastRuck'] = (dsl is num) ? dsl.round() : int.tryParse('$dsl');


    return context;
  }

  String _buildInsightPrompt(Map<String, dynamic> context, {String weatherAddon = ''}) {
    final distanceUnit = context['preferMetric'] ? 'km' : 'miles';
    final gender = (context['gender'] as String?) ?? '';
    final isFirstSession = ((context['allTimeSessions'] as int? ?? 0) == 0);

    String toneGuidance;
    if (gender == 'female') {
      toneGuidance = '- Tone: Empowering, supportive, and empathetic. Avoid macho language.';
    } else if (gender == 'male') {
      toneGuidance = '- Tone: Tough, playful, and motivating. Keep it respectful.';
    } else {
      toneGuidance = '- Tone: Balanced, encouraging, and inclusive.';
    }

    final firstSessionGuidance = isFirstSession
        ? '- First-time guidance: This is their first session. Thank them for joining and encourage a simple start: "Try 5 minutes, even without weight, to earn your first achievement." Keep it approachable.'
        : '';

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
${weatherAddon.isNotEmpty ? '- Weather: ' + weatherAddon : ''}

 Special Guidelines:
 $toneGuidance
 $firstSessionGuidance
 - If Weather is provided above, include one short weather observation in either the insight or recommendation (e.g., warmer/cooler, windier/calmer, clearer/rainier than last ruck).
 - Use the user's preferred units ($distanceUnit).
 - Be concise and concrete. One short idea per field.
 - Do not mention BPM, medical advice, or anything not present in context.

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

  String _buildWeatherDeltaSnippet(CurrentWeather current, CurrentWeather last, bool preferMetric) {
    double toUserTemp(double c) => preferMetric ? c : (c * 9 / 5 + 32);
    int t(double? c) => toUserTemp(c ?? 0).round();
    final tempUnit = preferMetric ? '°C' : '°F';
    final nowT = t(current.temperature);
    final lastT = t(last.temperature);
    final deltaT = nowT - lastT;
    final deltaStr = deltaT == 0 ? 'same temp' : (deltaT > 0 ? '+$deltaT$tempUnit warmer' : '${deltaT}$tempUnit cooler');
    double toUserWind(double kph) => preferMetric ? kph : (kph * 0.621371);
    final nowWind = toUserWind((current.windSpeed ?? 0).toDouble()).round();
    final lastWind = toUserWind((last.windSpeed ?? 0).toDouble()).round();
    final windUnit = preferMetric ? 'km/h' : 'mph';
    final windDiff = nowWind - lastWind;
    final windStr = windDiff == 0 ? 'similar wind' : (windDiff > 0 ? '+$windDiff $windUnit wind' : '${windDiff} $windUnit wind');
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
    final condDelta = todayCond == lastCond ? todayCond : '$todayCond vs $lastCond';
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
        greeting: parsed['greeting'] ?? _getDefaultGreeting(context['timeOfDay'], context['username']),
        insight: parsed['insight'] ?? _fallbackInsightLine(context),
        recommendation: parsed['recommendation'] ?? _fallbackRecommendationLine(context),
        motivation: parsed['motivation'] ?? _fallbackMotivationLine(context),
        emoji: parsed['emoji'] ?? '🎒',
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      AppLogger.warning('[AI_INSIGHTS] Failed to parse AI response, using fallback: $e');
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
    final double avg = toUser(((ctx['averageDistance'] as num?)?.toDouble() ?? 0.0));

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
    if (recent >= 4) return 'Consistency is your superpower. Keep stacking days.';
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
