import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/core/config/app_config.dart';
import 'package:rucking_app/features/ai_cheerleader/services/simple_ai_logger.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/remote_config_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

/// Service for generating motivational text using OpenAI GPT-4o
class OpenAIService {
  static const String _model = 'gpt-4o-mini'; // Faster, lower-latency model
  static const int _maxTokens = 120; // Allow for 2-3 sentences
  static const double _temperature = 0.7; // Slightly lower for tighter responses
  static const Duration _timeout = Duration(seconds: 6);

  // Local in-memory cache of recent AI lines to avoid repetition even if history isn't provided
  static final List<String> _localRecentLines = <String>[]; // stores last few AI outputs (trimmed)

  final SimpleAILogger? _logger;

  OpenAIService({SimpleAILogger? logger}) : _logger = logger;

  /// Generates motivational message based on context and personality
  Future<String?> generateMessage({
    required Map<String, dynamic> context,
    required String personality,
    bool explicitContent = false,
  }) async {
    AppLogger.error('[OPENAI_SERVICE_DEBUG] ===== GENERATE MESSAGE METHOD CALLED =====');
    AppLogger.error('[OPENAI_SERVICE_DEBUG] This proves the OpenAIService.generateMessage is being called');
    try {
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 1: Starting generateMessage try block');
      AppLogger.info('[OPENAI] Generating message for $personality personality');
      
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 2: About to build prompt');
      String prompt;
      try {
        prompt = _buildPrompt(
          personality,
          explicitContent,
          context['trigger'] ?? <String, dynamic>{},
          context['session'] ?? <String, dynamic>{},
          context['user'] ?? <String, dynamic>{},
          context['environment'] ?? <String, dynamic>{},
          context['history'] ?? context['userHistory'] ?? <String, dynamic>{},
        );
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 3: Prompt built successfully');
      } catch (e, stackTrace) {
        AppLogger.error('[OPENAI_SERVICE_DEBUG] FATAL: _buildPrompt failed with error: $e');
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Stack trace: $stackTrace');
        return null;
      }
      
      // Debug logging: Show full prompt being sent to OpenAI
      AppLogger.info('[OPENAI_DEBUG] Full prompt being sent to OpenAI:');
      AppLogger.info('[OPENAI_DEBUG] ===== START PROMPT =====');
      AppLogger.info('[OPENAI_DEBUG] $prompt');
      AppLogger.info('[OPENAI_DEBUG] ===== END PROMPT =====');
      
      // Debug logging: Show context components
      AppLogger.info('[OPENAI_DEBUG] Context components:');
      AppLogger.info('[OPENAI_DEBUG] - Trigger: ${context['trigger']}');
      AppLogger.info('[OPENAI_DEBUG] - Session: ${context['session']}');
      AppLogger.info('[OPENAI_DEBUG] - User: ${context['user']}');
      AppLogger.info('[OPENAI_DEBUG] - Environment: ${context['environment']}');
      
      // Make OpenAI API call with timeout
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 4: About to call OpenAI.instance.chat.create...');
      AppLogger.info('[OPENAI_DEBUG] About to call OpenAI.instance.chat.create...');
      
      final completion = await OpenAI.instance.chat.create(
        model: _model,
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            content: [
              OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt),
            ],
            role: OpenAIChatMessageRole.user,
          ),
        ],
        maxTokens: _maxTokens,
        temperature: _temperature,
      ).timeout(_timeout);
      
      AppLogger.info('[OPENAI_DEBUG] OpenAI API call completed successfully');
      AppLogger.info('[OPENAI_DEBUG] Response choices count: ${completion.choices.length}');

      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 5: OpenAI API call completed successfully');
      
      var message = completion.choices.first.message.content?.first.text?.trim();
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 6: Extracted message from response');
      AppLogger.info('[OPENAI_DEBUG] Extracted message: $message');
      
      if (message != null && message.isNotEmpty) {
        // 1) Strip hashtags
        message = message
            .split(RegExp(r"\s+"))
            .where((w) => !w.startsWith('#'))
            .join(' ')
            .trim();
        // 2) Remove emojis and pictographs (common ranges)
        final emojiRegex = RegExp(r"[\u{1F300}-\u{1FAFF}\u{1F600}-\u{1F64F}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]", unicode: true);
        message = message.replaceAll(emojiRegex, '');
        // 3) Replace newlines with spaces and collapse whitespace
        message = message.replaceAll('\n', ' ').replaceAll(RegExp(r"\s+"), ' ').trim();
        // 4) Allow up to 3 sentences, cap at 75 words
        final split = message.split(RegExp(r"(?<=[.!?])\s+"));
        if (split.length > 3) {  // Increased from 2 to 3 sentences
          message = split.take(3).join(' ').trim();
        }
        // Cap length to ~75 words and add period if needed
        final words = message.split(' ');
        if (words.length > 75) {  // Increased from 50 to 75 words
          message = words.take(75).join(' ');
        }
        if (!RegExp(r"[.!?]$").hasMatch(message)) {
          message = message + '.';
        }

        // Update local recent lines cache (dedupe, keep latest 6)
        final line = message.length > 120 ? message.substring(0, 120) : message;
        _localRecentLines.removeWhere((e) => e == line);
        _localRecentLines.insert(0, line);
        if (_localRecentLines.length > 6) {
          _localRecentLines.removeRange(6, _localRecentLines.length);
        }
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 7: Message is valid, about to log to database');
        AppLogger.info('[OPENAI_DEBUG] Generated message: "${message.substring(0, 50)}..."');
        AppLogger.info('[OPENAI_DEBUG] About to call _logSimpleResponse...');
        
        // Log simple response if logger is available
        _logSimpleResponse(
          context: context,
          personality: personality,
          response: message,
          isExplicit: explicitContent,
        );
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 8: _logSimpleResponse call completed');
        AppLogger.info('[OPENAI_DEBUG] _logSimpleResponse call completed');
        return message;
      } else {
        AppLogger.warning('[OPENAI_DEBUG] Empty response from OpenAI');
        return null;
      }
      
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.error('[OPENAI_SERVICE_DEBUG] FATAL: Request timed out after ${_timeout.inSeconds}s: $e');
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Timeout stack trace: $stackTrace');
      AppLogger.error('[OPENAI] Request timed out');
      return null;
    } on SocketException catch (e, stackTrace) {
      AppLogger.error('[OPENAI_SERVICE_DEBUG] FATAL: Network error - no internet connection: $e');
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Socket error stack trace: $stackTrace');
      AppLogger.error('[OPENAI] Network error - no internet connection');
      return null;
    } catch (e, stackTrace) {
      AppLogger.error('[OPENAI_SERVICE_DEBUG] FATAL: Unexpected error in generateMessage: $e');
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Full stack trace: $stackTrace');
      AppLogger.error('[OPENAI] Failed to generate message: $e');
      return null;
    }
  }

  /// Generate a concise Strava activity title (8-12 words, emojis allowed)
  /// Returns null on failure/timeout so callers can fallback.
  Future<String?> generateStravaTitle({
    required double distanceKm,
    required Duration duration,
    required double ruckWeightKg,
    required bool preferMetric,
    String? city,
    DateTime? startTime,
  }) async {
    try {
      final distance = preferMetric
          ? '${distanceKm.toStringAsFixed(distanceKm >= 10 ? 0 : 2)} km'
          : '${(distanceKm * 0.621371).toStringAsFixed(distanceKm >= 10 ? 0 : 2)} mi';
      final weight = preferMetric
          ? '${ruckWeightKg.round()} kg'
          : '${(ruckWeightKg * 2.20462).round()} lb';
      final mins = duration.inMinutes;
      final timeOfDay = startTime != null ? DateFormat('EEEE').format(startTime) : '';

      final prompt = [
        'You are naming a Strava activity for a weighted ruck workout.',
        'Write ONE catchy, creative title, 8-12 words. Emojis encouraged. No hashtags.',
        'Be imaginative and fun - avoid generic words like "Workout" or "Activity".',
        'Use wordplay, alliteration, or cultural references when appropriate.',
        'Context:',
        'distance=$distance, duration=${mins}m, ruck_weight=$weight, city=${city ?? 'Unknown'}, day=$timeOfDay.',
        'Output just the title text.'
      ].join('\n');

      final completion = await OpenAI.instance.chat.create(
        model: _model,
        messages: [
          OpenAIChatCompletionChoiceMessageModel(
            content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)],
            role: OpenAIChatMessageRole.user,
          ),
        ],
        maxTokens: 32,
        temperature: 0.9, // Increased for more creative titles
      ).timeout(const Duration(seconds: 4));

      var title = completion.choices.first.message.content?.first.text?.trim();
      if (title == null || title.isEmpty) return null;
      // Sanitize: single line, clamp length (keep emojis)
      title = title.replaceAll('\n', ' ').trim();
      // Remove enclosing quotes if any
      if (title.startsWith('"') && title.endsWith('"') && title.length > 2) {
        title = title.substring(1, title.length - 1).trim();
      }
      // Hard cap ~70 chars
      if (title.length > 70) {
        title = title.substring(0, 70).trimRight();
      }
      return title.isEmpty ? null : title;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Generates a concise post-session summary message focused on metrics and insights.
  /// This uses a dedicated system prompt separate from the cheerleader prompt.
  Future<String?> generateSessionSummary({
    required Map<String, dynamic> context,
  }) async {
    try {
      // Build session-summary-specific prompt
      final prompt = _buildSessionSummaryPrompt(context);

      // Debug logging: Show full prompt being sent to OpenAI
      AppLogger.info('[OPENAI_DEBUG][SUMMARY] ===== START PROMPT =====');
      AppLogger.info('[OPENAI_DEBUG][SUMMARY] $prompt');
      AppLogger.info('[OPENAI_DEBUG][SUMMARY] ===== END PROMPT =====');

      final completion = await OpenAI.instance.chat
          .create(
            model: _model,
            messages: [
              OpenAIChatCompletionChoiceMessageModel(
                content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)],
                role: OpenAIChatMessageRole.user,
              ),
            ],
            maxTokens: _maxTokens,
            temperature: 0.5, // slightly tighter for summaries
          )
          .timeout(_timeout);

      var message = completion.choices.first.message.content?.first.text?.trim();

      if (message == null || message.isEmpty) return null;

      // Reuse sanitization rules from generateMessage
      message = message
          .split(RegExp(r"\s+"))
          .where((w) => !w.startsWith('#'))
          .join(' ')
          .trim();
      final emojiRegex = RegExp(r"[\u{1F300}-\u{1FAFF}\u{1F600}-\u{1F64F}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]", unicode: true);
      message = message.replaceAll(emojiRegex, '');
      message = message.replaceAll('\n', ' ').replaceAll(RegExp(r"\s+"), ' ').trim();
      final split = message.split(RegExp(r"(?<=[.!?])\s+"));
      if (split.length > 3) {
        message = split.take(3).join(' ').trim();
      }
      final words = message.split(' ');
      if (words.length > 75) {
        message = words.take(75).join(' ');
      }
      if (!RegExp(r"[.!?]$").hasMatch(message)) {
        message = message + '.';
      }

      return message;
    } on TimeoutException {
      AppLogger.error('[OPENAI][SUMMARY] Request timed out');
      return null;
    } on SocketException {
      AppLogger.error('[OPENAI][SUMMARY] Network error - no internet connection');
      return null;
    } catch (e, st) {
      AppLogger.error('[OPENAI][SUMMARY] Unexpected error: $e', stackTrace: st);
      return null;
    }
  }

  /// Build a focused session summary prompt separate from the cheerleader system prompt.
  String _buildSessionSummaryPrompt(Map<String, dynamic> context) {
    // Get dedicated system prompt from Remote Config if present, else fallback
    String systemPrompt;
    try {
      final remoteConfig = RemoteConfigService.instance;
      // Use generic getString to allow shipping without adding new keys remotely yet
      systemPrompt = remoteConfig.getString('ai_session_summary_system_prompt', fallback: '''You are an expert fitness analyst generating a concise post-ruck session summary.
Focus on factual metrics, notable achievements, and one meaningful insight. Keep it clear and encouraging without hype.''');
    } catch (_) {
      systemPrompt = '''You are an expert fitness analyst generating a concise post-ruck session summary.
Focus on factual metrics, notable achievements, and one meaningful insight. Keep it clear and encouraging without hype.''';
    }

    // Extract common fields (null-safe)
    final distanceKm = (context['distance_km'] as num?)?.toDouble();
    final distanceMi = (context['distance_miles'] as num?)?.toDouble();
    final durationMin = (context['duration_minutes'] as num?)?.toInt();
    final calories = (context['calories_burned'] as num?)?.toInt();
    final elevGain = (context['elevation_gain_m'] as num?)?.toDouble();
    final elevLoss = (context['elevation_loss_m'] as num?)?.toDouble();
    final ruckWeightKg = (context['ruck_weight_kg'] as num?)?.toDouble();
    final preferMetric = (context['prefer_metric'] as bool?) ?? true;
    final avgHr = (context['avg_hr'] as num?)?.toInt();
    final maxHr = (context['max_hr'] as num?)?.toInt();
    final steps = (context['steps'] as num?)?.toInt();

    // Assemble a compact JSON-like context block for determinism
    final sb = StringBuffer();
    sb.writeln('{');
    if (preferMetric) {
      if (distanceKm != null) sb.writeln('  "distance_km": ${distanceKm.toStringAsFixed(distanceKm >= 10 ? 0 : 2)},');
    } else {
      if (distanceMi != null) sb.writeln('  "distance_miles": ${distanceMi.toStringAsFixed(distanceMi >= 10 ? 0 : 2)},');
    }
    if (durationMin != null) sb.writeln('  "duration_min": $durationMin,');
    if (ruckWeightKg != null) {
      if (preferMetric) {
        sb.writeln('  "ruck_weight_kg": ${ruckWeightKg.toStringAsFixed(1)},');
      } else {
        // Use AppConfig constant for consistent conversion
        final ruckWeightLb = ruckWeightKg * AppConfig.kgToLbs;
        sb.writeln('  "ruck_weight_lb": ${ruckWeightLb.toStringAsFixed(1)},');
      }
    }
    if (calories != null) sb.writeln('  "calories": $calories,');
    if (preferMetric) {
      if (elevGain != null) sb.writeln('  "elev_gain_m": ${elevGain.toStringAsFixed(0)},');
      if (elevLoss != null) sb.writeln('  "elev_loss_m": ${elevLoss.toStringAsFixed(0)},');
    } else {
      if (elevGain != null) {
        final elevGainFt = elevGain * 3.28084; // MeasurementUtils doesn't have direct elevation conversion method
        sb.writeln('  "elev_gain_ft": ${elevGainFt.toStringAsFixed(0)},');
      }
      if (elevLoss != null) {
        final elevLossFt = elevLoss * 3.28084; // MeasurementUtils doesn't have direct elevation conversion method
        sb.writeln('  "elev_loss_ft": ${elevLossFt.toStringAsFixed(0)},');
      }
    }
    if (avgHr != null) sb.writeln('  "avg_hr": $avgHr,');
    if (maxHr != null) sb.writeln('  "max_hr": $maxHr,');
    if (steps != null) sb.writeln('  "steps": $steps,');
    // split pace and heart rate zones if provided
    if (context['splits'] is List) sb.writeln('  "has_splits": true,');
    if (context['heart_rate_zones'] is Map) sb.writeln('  "has_hr_zones": true,');
    sb.writeln('}');

    final guidelines = [
      '- 2-3 sentences, max 75 words. No hashtags.',
      '- Reference at least one concrete metric (distance, duration, pace, HR, elevation, weight).',
      '- If available, note one standout: best split, higher ruck weight, elevation challenge, or HR control.',
      '- Keep tone concise and confident; avoid generic hype.',
      preferMetric 
        ? '- Use metric units (km, kg, meters) when referencing measurements.'
        : '- Use imperial units (miles, lb, feet) when referencing measurements.',
    ].join('\n');

    return [
      systemPrompt,
      '',
      'Context:',
      sb.toString(),
      '',
      'Response Requirements:',
      guidelines,
      '',
      'Respond with the post-session summary text only:'
    ].join('\n');
  }

  /// Builds personality-specific prompt based on context
  String _buildPrompt(
    String personality,
    bool explicitContent,
    dynamic trigger,
    dynamic session,
    dynamic user,
    dynamic environment,
    dynamic history,
  ) {
    final personalityPrompt = _getPersonalityPrompt(personality, explicitContent);
    final baseContext = _buildBaseContext(trigger, session, user, environment, history);
    final contentGuidelines = explicitContent 
      ? 'Use colorful, explicit language and profanity when it fits the character. Adult language and edgy humor is encouraged'
      : 'Keep language family-friendly and appropriate for all ages';

    // Get Remote Config prompts (with fallback to current behavior)
    String systemPrompt;
    try {
      final remoteConfig = getIt<RemoteConfigService>();
      systemPrompt = remoteConfig.getAICheerleaderSystemPrompt();
    } catch (e) {
      // Fallback to default system prompt if RemoteConfigService is not available
      systemPrompt = '''You are an enthusiastic AI cheerleader for rucking workouts.
Analyze the provided context and generate personalized, motivational messages.
Focus on current performance, progress, and achievements.
Be encouraging, positive, and action-oriented.
Reference historical trends and achievements when relevant.''';
    }
    final userName = _extractFirstName(user['username']) ?? 'athlete';
    
    // Pull last 3–4 prior AI responses to help prevent repetition
    final avoidLines = _recentAICheerleaderLines(history, max: 4);
    AppLogger.info('[OPENAI_DEBUG] Found ${avoidLines.length} previous AI responses to avoid');
    AppLogger.info('[OPENAI_DEBUG] Previous responses: $avoidLines');
    final avoidBlock = avoidLines.isEmpty
        ? ''
        : '\n\nVariety Guidelines:\nAvoid repeating these exact phrases from recent responses:\n- ' + avoidLines.join('\n- ') + '\n\nFor variety, try referencing different aspects of their performance each time.\n';
    
    return '''
$systemPrompt

Personality: $personality
User: $userName
Guidelines: $contentGuidelines

Context:
$baseContext
$avoidBlock

Response Requirements:
- Output 2-3 sentences, maximum 75 words total, no emojis, no hashtags.
- Reference at least one specific, relevant data point from the context/history.
- Vary your approach and focus different aspects of their performance for variety.

Respond with your motivational message:''';
  }

  String _buildBaseContext(
    dynamic trigger,
    dynamic session,
    dynamic user,
    dynamic environment,
    dynamic history,
  ) {
    final triggerType = trigger is Map ? trigger['type'] : null;
    final triggerData = (trigger is Map && trigger['data'] is Map)
        ? Map<String, dynamic>.from(trigger['data'] as Map)
        : <String, dynamic>{};
    
    // Safe access to session data with fallbacks
    final elapsedTime = session is Map 
        ? (session['elapsedTime'] is Map 
            ? session['elapsedTime']['formatted']?.toString() ?? '0' 
            : session['duration_seconds']?.toString() ?? '0') 
        : '0';
    final distance = session is Map 
        ? (session['distance'] is Map 
            ? session['distance']['formatted']?.toString() ?? '0' 
            : session['distance_km']?.toString() ?? '0') 
        : '0';
    
    String contextText = "Rucking session: ${elapsedTime} elapsed, ${distance} covered.";
    
    switch (triggerType) {
      case 'milestone':
        final milestone = triggerData['milestone'];
        final distanceObj = session is Map ? session['distance'] : null;
        final unit = distanceObj is Map && distanceObj['unit'] != null ? distanceObj['unit'] : 'km';
        final userPreferMetric = (user is Map && user['preferMetric'] is bool) ? user['preferMetric'] as bool : true;
        if (milestone is num) {
          final milestoneValue = userPreferMetric ? milestone : (milestone * 0.621371).toStringAsFixed(1);
          contextText += " Just hit ${milestoneValue}${unit} milestone!";
        }
        break;
      case 'paceDrop':
        final slowdown = triggerData['slowdownPercent'];
        contextText += " Pace dropped by $slowdown% - needs encouragement.";
        break;
      case 'heartRateSpike':
        final hr = triggerData['heartRate'];
        final baseline = triggerData['baseline'];
        contextText += " Heart rate spike: ${hr}bpm (baseline ~${baseline}bpm). Encourage breathing rhythm and steady form.";
        break;
      case 'timeCheckIn':
        final minutes = triggerData['elapsedMinutes'];
        contextText += " Regular $minutes-minute check-in.";
        break;
      case 'manualRequest':
        contextText += " User requested motivational message.";
        break;
    }
    
    // Add performance context (null-safe)
    final performance = session is Map ? session['performance'] : null;
    if (performance is Map && performance['heartRate'] != null) {
      contextText += " HR: ${performance['heartRate']}bpm.";
    }
    
    // Add environmental context
    final timeOfDay = environment is Map ? environment['timeOfDay'] : 'Unknown';
    final sessionPhase = environment is Map ? environment['sessionPhase'] : 'Unknown';
    contextText += " Time: ${timeOfDay}, Phase: ${sessionPhase}.";
    
    // Add location context for humor and local references
    final location = environment is Map ? environment['location'] : null;
    AppLogger.info('[OPENAI_DEBUG] Location object type: ${location.runtimeType}');
    AppLogger.info('[OPENAI_DEBUG] Location contents: $location');
    
    // Pull user unit preference earlier for temp unit
    final preferMetric = (user is Map && user['preferMetric'] is bool) ? user['preferMetric'] as bool : true;

    if (location != null) {
      if (location is Map) {
        final locationMap = Map<String, dynamic>.from(location);
        final city = (locationMap['city'] ?? locationMap['name'] ?? locationMap['locality']) as String?;
        final terrain = locationMap['terrain'] as String?;
        final landmark = locationMap['landmark'] as String?;

        // Weather may live inside location or environment['weather']
        String? weatherCondition = locationMap['weatherCondition'] as String?;
        num? tempF = locationMap['temperature'] is num ? locationMap['temperature'] as num : null;
        // Alternative nested weather structures
        final weather = environment is Map ? environment['weather'] : null;
        if (weather is Map) {
          final weatherMap = Map<String, dynamic>.from(weather);
          weatherCondition = weatherCondition ?? (weatherMap['condition'] ?? weatherMap['summary']) as String?;
          tempF = tempF ?? (weatherMap['tempF'] is num ? weatherMap['tempF'] as num : null);
          final tempCAlt = weatherMap['tempC'] is num ? weatherMap['tempC'] as num : null;
          if (preferMetric && tempF == null && tempCAlt != null) {
            // keep as C, convert later during render
            tempF = (tempCAlt * 9 / 5) + 32; // store F for unified handling
          }
        }

        AppLogger.info('[OPENAI_DEBUG] Parsed - city: $city, terrain: $terrain, landmark: $landmark, weather: $weatherCondition, tempF: $tempF');

        if (city != null && city.isNotEmpty && city != 'Unknown Location') {
          contextText += " Location: $city";
          if (terrain != null && terrain.isNotEmpty) contextText += " ($terrain terrain)";
          if (landmark != null && landmark.isNotEmpty) contextText += " near $landmark";

          // Add weather context (respect unit preference)
          if (tempF != null || weatherCondition != null) {
            contextText += " - Weather: ";
            if (tempF != null) {
              if (preferMetric) {
                final tempC = ((tempF - 32) * 5 / 9).round();
                contextText += "${tempC}°C";
              } else {
                contextText += "${tempF.round()}°F";
              }
            }
            if (weatherCondition != null && weatherCondition.isNotEmpty) {
              if (tempF != null) contextText += ", ";
              contextText += weatherCondition;
            }
          }
        }
      } else if (location is String && location.isNotEmpty && location != 'Unknown Location') {
        contextText += " Location: $location";
      }
    }

    // Add exactly one concise history insight if available
    final insight = _deriveOneHistoryInsight(session: session, history: history, preferMetric: preferMetric);
    if (insight != null && insight.isNotEmpty) {
      contextText += " $insight";
    }

    // Add rich history context for AI to reference
    final recentRucks = (history is Map && history['recent_rucks'] is List) ? history['recent_rucks'] as List : <dynamic>[];
    final achievements = (history is Map && history['achievements'] is List) ? history['achievements'] as List : <dynamic>[];
    
    if (recentRucks.isNotEmpty) {
      contextText += "\n\nUser History:";
      // Add recent ruck summary
      final recentRuck = recentRucks.first;
      if (recentRuck is Map<String, dynamic>) {
        final distance = recentRuck['distance_km'] as num?;
        final duration = recentRuck['duration_seconds'] as num?;
        final ruckWeight = recentRuck['ruck_weight_kg'] as num?;
        final calories = recentRuck['calories_burned'] as num?;
        
        contextText += "\nRecent ruck: ";
        if (distance != null && distance > 0) {
          contextText += "${distance.toStringAsFixed(2)}km";
        }
        if (duration != null) {
          final mins = duration ~/ 60;
          contextText += " in ${mins}min";
        }
        if (ruckWeight != null && ruckWeight > 0) {
          contextText += " with ${ruckWeight.toStringAsFixed(1)}kg ruck";
        }
        if (calories != null) {
          contextText += ", ${calories.round()} calories";
        }
      }
      
      // Add ruck weight history
      final heavyRucks = recentRucks.where((r) => 
        r is Map<String, dynamic> && 
        (r['ruck_weight_kg'] as num? ?? 0) > 10
      ).length;
      if (heavyRucks > 0) {
        contextText += "\nHeavy ruck experience: $heavyRucks sessions with 10kg+ weight";
      }
    }
    
    if (achievements.isNotEmpty) {
      contextText += "\nRecent achievements: ${achievements.length} unlocked";
    }

    return contextText;
  }

  void _logSimpleResponse({
    required dynamic context,
    required String personality,
    required String response,
    required bool isExplicit,
  }) {
    AppLogger.info('[AI_LOG] _logSimpleResponse called - logger is null: ${_logger == null}');
    if (_logger == null) {
      AppLogger.warning('[AI_LOG] Logger is null, cannot log response');
      return;
    }

    try {
      // Get sessionId directly from ActiveSessionBloc
      final activeSessionBloc = getIt<ActiveSessionBloc>();
      final activeState = activeSessionBloc.state;
      
      String? sessionId;
      if (activeState is ActiveSessionRunning) {
        sessionId = activeState.sessionId;
      }
      
      AppLogger.error('[AI_LOG_DEBUG] Got sessionId from ActiveSessionBloc: $sessionId');

      if (sessionId == null || sessionId.isEmpty) {
        AppLogger.error('[AI_LOG_DEBUG] ❌ BLOCKING ISSUE: No active session ID available');
        AppLogger.error('[AI_LOG_DEBUG] ActiveSessionBloc state: ${activeState.runtimeType}');
        return;
      }

      AppLogger.info('[AI_LOG] About to log response - sessionId: $sessionId, personality: $personality');
      _logger!.logResponse(
        sessionId: sessionId,
        personality: personality,
        openaiResponse: response,
        isExplicit: isExplicit,
      );
      AppLogger.info('[AI_LOG] Log response call completed');
    } catch (e) {
      AppLogger.error('[AI_LOG] Error logging response: $e');
    }
  }

  /// Gets a random creativity booster instruction
  String _getCreativityBooster() {
    final boosters = [
      'Use unexpected metaphors or comparisons in your encouragement',
      'Include a surprising fact or observation about their performance',
      'Make a clever wordplay or double meaning with their situation',
      'Reference something unexpected about the time of day or weather',
      'Use an unusual but fitting analogy from movies, sports, or nature',
      'Make a witty observation about human psychology or motivation',
      'Reference current events, pop culture, or seasonal themes creatively',
      'Use reverse psychology or an unexpected motivational angle',
    ];
    
    final now = DateTime.now();
    final index = (now.millisecondsSinceEpoch ~/ 10000) % boosters.length;
    return boosters[index];
  }

  /// Gets varied instruction to prevent repetitive phrasing
  String _getVariedInstructions() {
    final instructions = [
      'Use only ONE creative ruck-related pun per message like "you\'ve rucking got this", "way to go mother rucker", or "ruck and roll"',
      'Include one playful ruck pun but make it different each time - avoid repeating "rucking" or "ruck and roll" patterns',
      'If using a ruck pun, make it unique and unexpected - mix up the wordplay creatively',
      'Optional: include one subtle ruck wordplay, but only if it feels natural and original',
      'Vary your ruck puns - try "rucktastic", "rucking awesome", or create entirely new combinations',
    ];
    
    final now = DateTime.now();
    final index = (now.millisecondsSinceEpoch ~/ 15000) % instructions.length;
    return instructions[index];
  }

  /// Extract first name from username (before @, spaces, or dots)
  String? _extractFirstName(String? username) {
    if (username == null || username.isEmpty) return null;
    
    // Remove @ and everything after it (email-style usernames)
    username = username.split('@').first;
    
    // Take first word (before spaces)
    username = username.split(' ').first;
    
    // Take first part (before dots)
    username = username.split('.').first;
    
    return username.isEmpty ? null : username;
  }

  // Safely read a numeric value from a nested map path
  num? _readNum(Map<String, dynamic>? obj, List<String> path) {
    if (obj == null) return null;
    dynamic cur = obj;
    for (final key in path) {
      if (cur is Map<String, dynamic> && cur.containsKey(key)) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    if (cur == null) return null;
    if (cur is num) return cur;
    if (cur is String) return num.tryParse(cur);
    return null;
  }

  // Derive exactly one concise history insight comparing current session vs most recent past ruck
  String? _deriveOneHistoryInsight({
    required dynamic session,
    required dynamic history,
    required bool preferMetric,
  }) {
    final recentRucks = (history is Map && history['recent_rucks'] is List) ? history['recent_rucks'] as List : <dynamic>[];
    if (recentRucks.isEmpty) return null;
    final last = recentRucks.first;
    if (last is! Map) return null;
    final lastMap = Map<String, dynamic>.from(last);

    // 1) Ruck weight delta (highest priority)
    final currentWeightKg = _readNum(session is Map ? Map<String, dynamic>.from(session) : null, ['gear', 'ruckWeightKg']) ?? _readNum(session is Map ? Map<String, dynamic>.from(session) : null, ['weightKg']);
    final lastWeightKg = _readNum(lastMap, ['ruck_weight_kg']) ?? _readNum(lastMap, ['weight_kg']);
    if (currentWeightKg != null && lastWeightKg != null) {
      final deltaKg = currentWeightKg - lastWeightKg;
      if (deltaKg.abs() >= 0.5) {
        if (preferMetric) {
          return "Noticed your ruck weight is ${deltaKg > 0 ? 'up' : 'down'} ${deltaKg.abs().toStringAsFixed(1)} kg from last time.";
        } else {
          final deltaLb = deltaKg * 2.20462;
          return "Noticed your ruck weight is ${deltaKg > 0 ? 'up' : 'down'} ${deltaLb.abs().toStringAsFixed(0)} lb from last time.";
        }
      }
    }

    // 2) Distance pacing (current pace vs last pace at similar distance)
    final currentPace = _readNum(session is Map ? Map<String, dynamic>.from(session) : null, ['performance', 'pace']); // seconds per unit
    final lastPace = _readNum(lastMap, ['avg_pace_seconds_per_km']) ?? _readNum(lastMap, ['avg_pace_seconds_per_mile']);
    if (currentPace != null && lastPace != null) {
      final diffSec = currentPace - lastPace;
      if (diffSec.abs() >= 5) { // meaningful difference >= 5s
        final unit = preferMetric ? 'km' : 'mi';
        return diffSec < 0
          ? "You're pacing faster than your last ${unit} splits."
          : "You're pacing a bit slower than your last ${unit} splits—keep steady.";
      }
    }

    // 3) Split comparison (current latest split vs last latest split)
    final sessionSplits = (session is Map && session['splits'] is List) ? session['splits'] as List : <dynamic>[];
    final lastSplits = (lastMap['splits'] is List) ? lastMap['splits'] as List : <dynamic>[];
    if (sessionSplits.isNotEmpty && lastSplits.isNotEmpty) {
      final curLast = sessionSplits.last;
      final prevLast = lastSplits.last;
      if (curLast is Map && prevLast is Map) {
        final curDur = _readNum(Map<String, dynamic>.from(curLast), ['splitDurationSeconds']);
        final prevDur = _readNum(Map<String, dynamic>.from(prevLast), ['splitDurationSeconds']);
        if (curDur != null && prevDur != null) {
          final delta = curDur - prevDur;
          if (delta.abs() >= 5) {
            final unit = preferMetric ? 'km' : 'mi';
            return delta < 0
              ? "Latest $unit split quicker than your last session."
              : "Latest $unit split a touch slower than your last session—stay smooth.";
          }
        }
      }
    }

    return null;
  }

  String _getPersonalityPrompt(String personality, bool explicitContent) {
    switch (personality) {
      case 'Supportive Friend':
        return '''You are a caring, supportive friend who's genuinely excited about their fitness journey. You're warm, understanding, and always ready with encouragement. You celebrate every small win and offer gentle motivation.''';
        
      case 'Drill Sergeant':
        return explicitContent 
          ? '''You are a tough military drill sergeant who demands excellence. You use firm, direct language and aren't afraid to challenge them. Push hard but with purpose - make them stronger.'''
          : '''You are a firm but fair drill sergeant who demands excellence. You use strong, direct language to push them beyond their limits. Tough love with purpose - make them stronger.''';
          
      case 'Southern Redneck':
        return explicitContent
          ? '''You are a colorful Southern character with folksy wisdom and a great sense of humor. You use Southern expressions, maybe some mild language, and relate everything to down-home experiences.'''
          : '''You are a colorful Southern character with folksy wisdom and a great sense of humor. You use Southern expressions and relate everything to down-home experiences with country charm.''';
          
      case 'Yoga Instructor':
        return '''You are a peaceful yoga instructor who emphasizes breath, mindfulness, and inner strength. You encourage them to find their center, breathe through challenges, and see rucking as moving meditation.''';
        
      case 'British Butler':
        return '''You are a distinguished British butler with impeccable manners and dry wit. You offer encouragement with proper etiquette, subtle humor, and references to serving with excellence and maintaining standards.''';
        
      case 'Sports Commentator':
        return '''You are an energetic sports commentator providing live coverage of their rucking performance. You use dramatic sports language, build excitement, and make them feel like they're competing in the Olympics.''';
        
      case 'Cowboy/Cowgirl':
        return '''You are a rugged cowhand who sees rucking as trail riding preparation. You use Western expressions, talk about grit and determination, and encourage them to keep riding toward the sunset, partner.''';
        
      case 'Nature Lover':
        if (explicitContent) {
          return '''You are a passionate nature lover who finds deep, sensual connection with the natural world. You speak with sultry warmth and appreciation for physical pleasure in nature, using double entendres about "feeling the earth move," "getting your heart pumping," "working up a sweat," and "reaching your peak." Your voice is seductive yet encouraging, finding sexual metaphors in the rhythm of movement and natural beauty.''';
        } else {
          return '''You are a passionate nature lover who finds deep connection and sensuality in the natural world. You speak with warmth and appreciation for the beauty around them, encouraging them to feel the earth beneath their feet and breathe in the natural energy. Your voice is gentle yet inspiring.''';
        }
        
      case 'Session Analyst':
        return '''You are an expert fitness analyst providing insightful post-session analysis. Focus on performance metrics, achievements, and meaningful observations about their ruck. Be encouraging but analytical, highlighting specific accomplishments and interesting patterns in their data. Reference their historical performance when relevant.''';
      default:
        return '''You are a supportive fitness companion providing encouragement during their ruck.''';
    }
  }

  // Extract recent AI cheerleader responses to avoid repeating phrasing
  List<String> _recentAICheerleaderLines(Map<dynamic, dynamic> history, {int max = 2}) {
    AppLogger.error('[ANTI_REPEAT_DEBUG] _recentAICheerleaderLines called with max=$max');
    AppLogger.error('[ANTI_REPEAT_DEBUG] History keys: ${history.keys.toList()}');
    AppLogger.error('[ANTI_REPEAT_DEBUG] ai_cheerleader_history type: ${history['ai_cheerleader_history'].runtimeType}');
    
    final items = (history['ai_cheerleader_history'] as List?) ?? const [];
    AppLogger.error('[ANTI_REPEAT_DEBUG] Found ${items.length} items in ai_cheerleader_history');
    
    final lines = <String>[];
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      AppLogger.error('[ANTI_REPEAT_DEBUG] Item $i: ${it.runtimeType} - ${it is Map ? (it as Map).keys.toList() : 'not a map'}');
      if (it is Map && it['openai_response'] is String) {
        var t = (it['openai_response'] as String).trim();
        AppLogger.error('[ANTI_REPEAT_DEBUG] Found AI response: "${t.substring(0, math.min(50, t.length))}..."');
        if (t.isEmpty) continue;
        // Collapse whitespace and limit length
        t = t.replaceAll(RegExp(r'\s+'), ' ');
        if (t.length > 120) t = t.substring(0, 120);
        lines.add(t);
        if (lines.length >= max) break;
      }
    }
    AppLogger.error('[ANTI_REPEAT_DEBUG] Extracted ${lines.length} previous responses from history');
    
    // If not enough history, supplement with local cache of recent lines
    if (lines.length < max && _localRecentLines.isNotEmpty) {
      AppLogger.error('[ANTI_REPEAT_DEBUG] Supplementing with ${_localRecentLines.length} local cached lines');
      for (final t in _localRecentLines) {
        if (lines.contains(t)) continue;
        lines.add(t);
        if (lines.length >= max) break;
      }
    }
    AppLogger.error('[ANTI_REPEAT_DEBUG] Final avoid lines (${lines.length}): $lines');
    return lines;
  }
}
