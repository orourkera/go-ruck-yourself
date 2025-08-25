import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ai_cheerleader/services/simple_ai_logger.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/core/services/remote_config_service.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

/// Service for generating motivational text using OpenAI GPT-4o
class OpenAIService {
  static const String _model = 'gpt-4o';
  static const int _maxTokens = 60; // lower to help enforce brevity
  static const double _temperature = 0.7; // slightly lower to reduce repetitiveness
  static const Duration _timeout = Duration(seconds: 10);

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
      final prompt = _buildPrompt(
        personality,
        explicitContent,
        context['trigger'] ?? {},
        context['session'] ?? {},
        context['user'] ?? {},
        context['environment'] ?? {},
        context['history'] ?? context['userHistory'] ?? {},
      );
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 3: Prompt built successfully');
      
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

      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 4: OpenAI API call completed successfully');
      
      var message = completion.choices.first.message.content?.first.text?.trim();
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 5: Extracted message from response');
      AppLogger.info('[OPENAI_DEBUG] Extracted message: $message');
      
      if (message != null && message.isNotEmpty) {
        // Enforce hard 20-word cap and strip hashtags client-side
        final tokens = message.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
        if (tokens.length > 20) {
          message = tokens.take(20).join(' ');
        }
        // Remove any hashtags entirely
        message = message
            .split(RegExp(r"\s+"))
            .where((w) => !w.startsWith('#'))
            .join(' ')
            .trim();
        // Collapse multiple spaces
        message = message.replaceAll(RegExp(r"\s+"), ' ').trim();

        // Update local recent lines cache (dedupe, keep latest 6)
        final line = message.length > 120 ? message.substring(0, 120) : message;
        _localRecentLines.removeWhere((e) => e == line);
        _localRecentLines.insert(0, line);
        if (_localRecentLines.length > 6) {
          _localRecentLines.removeRange(6, _localRecentLines.length);
        }
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 6: Message is valid, about to log to database');
        AppLogger.info('[OPENAI_DEBUG] Generated message: "${message.substring(0, 50)}..."');
        AppLogger.info('[OPENAI_DEBUG] About to call _logSimpleResponse...');
        
        // Log simple response if logger is available
        _logSimpleResponse(
          context: context,
          personality: personality,
          response: message,
          isExplicit: explicitContent,
        );
        AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 7: _logSimpleResponse call completed');
        AppLogger.info('[OPENAI_DEBUG] _logSimpleResponse call completed');
        return message;
      } else {
        AppLogger.warning('[OPENAI_DEBUG] Empty response from OpenAI');
        return null;
      }
      
    } on TimeoutException {
      AppLogger.error('[OPENAI] Request timed out');
      return null;
    } on SocketException {
      AppLogger.error('[OPENAI] Network error - no internet connection');
      return null;
    } catch (e) {
      AppLogger.error('[OPENAI] Failed to generate message: $e');
      return null;
    }
  }

  /// Builds personality-specific prompt based on context
  String _buildPrompt(
    String personality,
    bool explicitContent,
    Map<String, dynamic> trigger,
    Map<String, dynamic> session,
    Map<String, dynamic> user,
    Map<String, dynamic> environment,
    Map<String, dynamic> history,
  ) {
    final personalityPrompt = _getPersonalityPrompt(personality, explicitContent);
    final baseContext = _buildBaseContext(trigger, session, user, environment, history);
    final contentGuidelines = explicitContent 
      ? 'Use colorful, explicit language and profanity when it fits the character. Adult language and edgy humor is encouraged'
      : 'Keep language family-friendly and appropriate for all ages';

    // Get Remote Config prompts (with fallback to current behavior)
    final remoteConfig = getIt<RemoteConfigService>();
    final systemPrompt = remoteConfig.getAICheerleaderSystemPrompt();
    final userName = _extractFirstName(user['username']) ?? 'athlete';
    
    // Pull last 3–4 prior AI responses to help prevent repetition
    final avoidLines = _recentAICheerleaderLines(history, max: 4);
    final avoidBlock = avoidLines.isEmpty
        ? ''
        : '\nRecent lines to avoid repeating:\n- ' + avoidLines.join('\n- ') + '\n';
    
    return '''
$systemPrompt

Personality: Act as a $personality character.
User: $userName
Content Guidelines: $contentGuidelines

Context:
$baseContext
$avoidBlock

Additional Instructions:
- Respond as the $personality character with FRESH, UNIQUE phrasing each time
- Keep message to 20 words or fewer. HARD CAP: 20 words.
- Be specific about their current situation
- ${_getCreativityBooster()}
- ${_getVariedInstructions()}
- If weather or location context is provided, reference it naturally (one short mention only)
- Sound natural and conversational
- Focus on encouragement and motivation
- NEVER repeat phrases you've used before - be inventive and original
- NEVER use hashtags like #RuckLife #BeastMode - absolutely no # symbols allowed
- NEVER use social media language or internet slang
- Get creative with the user's name: $userName - make up fun nicknames, rhymes, or playful variations that match your $personality character

Generate a motivational message:''';
  }

  String _buildBaseContext(
    Map<String, dynamic> trigger,
    Map<String, dynamic> session,
    Map<String, dynamic> user,
    Map<String, dynamic> environment,
    Map<String, dynamic> history,
  ) {
    final triggerType = trigger['type'];
    final triggerData = (trigger['data'] is Map<String, dynamic>)
        ? (trigger['data'] as Map<String, dynamic>)
        : <String, dynamic>{};
    
    String contextText = "Rucking session: ${session['elapsedTime']['formatted']} elapsed, ${session['distance']['formatted']} covered.";
    
    switch (triggerType) {
      case 'milestone':
        final milestone = triggerData['milestone'];
        final unit = session['distance']['unit'] ?? 'km';
        final userPreferMetric = user['preferMetric'] ?? true;
        final milestoneValue = userPreferMetric ? milestone : (milestone * 0.621371).toStringAsFixed(1);
        contextText += " Just hit ${milestoneValue}${unit} milestone!";
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
    
    // Add performance context
    if (session['performance']['heartRate'] != null) {
      contextText += " HR: ${session['performance']['heartRate']}bpm.";
    }
    
    // Add environmental context
    contextText += " Time: ${environment['timeOfDay']}, Phase: ${environment['sessionPhase']}.";
    
    // Add location context for humor and local references
    final location = environment['location'];
    AppLogger.info('[OPENAI_DEBUG] Location object type: ${location.runtimeType}');
    AppLogger.info('[OPENAI_DEBUG] Location contents: $location');
    
    // Pull user unit preference earlier for temp unit
    final preferMetric = (user['preferMetric'] as bool?) ?? true;

    if (location != null) {
      if (location is Map<String, dynamic>) {
        final city = (location['city'] ?? location['name'] ?? location['locality']) as String?;
        final terrain = location['terrain'] as String?;
        final landmark = location['landmark'] as String?;

        // Weather may live inside location or environment['weather']
        String? weatherCondition = location['weatherCondition'] as String?;
        num? tempF = location['temperature'] is num ? location['temperature'] as num : null;
        // Alternative nested weather structures
        final weather = environment['weather'];
        if (weather is Map<String, dynamic>) {
          weatherCondition = weatherCondition ?? (weather['condition'] ?? weather['summary']) as String?;
          tempF = tempF ?? (weather['tempF'] is num ? weather['tempF'] as num : null);
          final tempCAlt = weather['tempC'] is num ? weather['tempC'] as num : null;
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

    return contextText;
  }

  void _logSimpleResponse({
    required Map<String, dynamic> context,
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
    required Map<String, dynamic> session,
    required Map<String, dynamic> history,
    required bool preferMetric,
  }) {
    final recentRucks = (history['recent_rucks'] as List?) ?? const [];
    if (recentRucks.isEmpty) return null;
    final last = recentRucks.first;
    if (last is! Map<String, dynamic>) return null;

    // 1) Ruck weight delta (highest priority)
    final currentWeightKg = _readNum(session, ['gear', 'ruckWeightKg']) ?? _readNum(session, ['weightKg']);
    final lastWeightKg = _readNum(last, ['ruck_weight_kg']) ?? _readNum(last, ['weight_kg']);
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
    final currentPace = _readNum(session, ['performance', 'pace']); // seconds per unit
    final lastPace = _readNum(last, ['avg_pace_seconds_per_km']) ?? _readNum(last, ['avg_pace_seconds_per_mile']);
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
    final sessionSplits = (session['splits'] as List?) ?? const [];
    final lastSplits = (last['splits'] as List?) ?? const [];
    if (sessionSplits.isNotEmpty && lastSplits.isNotEmpty) {
      final curLast = sessionSplits.last;
      final prevLast = lastSplits.last;
      if (curLast is Map && prevLast is Map) {
        final curDur = _readNum(curLast.cast<String, dynamic>(), ['splitDurationSeconds']);
        final prevDur = _readNum(prevLast.cast<String, dynamic>(), ['splitDurationSeconds']);
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
        
      default:
        return '''You are a supportive fitness companion providing encouragement during their ruck.''';
    }
  }

  // Extract recent AI cheerleader responses to avoid repeating phrasing
  List<String> _recentAICheerleaderLines(Map<String, dynamic> history, {int max = 2}) {
    final items = (history['ai_cheerleader_history'] as List?) ?? const [];
    final lines = <String>[];
    for (final it in items) {
      if (it is Map && it['openai_response'] is String) {
        var t = (it['openai_response'] as String).trim();
        if (t.isEmpty) continue;
        // Collapse whitespace and limit length
        t = t.replaceAll(RegExp(r'\s+'), ' ');
        if (t.length > 120) t = t.substring(0, 120);
        lines.add(t);
        if (lines.length >= max) break;
      }
    }
    // If not enough history, supplement with local cache of recent lines
    if (lines.length < max && _localRecentLines.isNotEmpty) {
      for (final t in _localRecentLines) {
        if (lines.contains(t)) continue;
        lines.add(t);
        if (lines.length >= max) break;
      }
    }
    return lines;
  }
}
