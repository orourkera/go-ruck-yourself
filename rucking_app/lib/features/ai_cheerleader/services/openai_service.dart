import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ai_cheerleader/services/simple_ai_logger.dart';
import 'package:rucking_app/core/services/service_locator.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';

/// Service for generating motivational text using OpenAI GPT-4o
class OpenAIService {
  static const String _model = 'gpt-4o';
  static const int _maxTokens = 150;
  static const double _temperature = 0.8; // Increased from 0.8 for more creativity
  static const Duration _timeout = Duration(seconds: 10);

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
      
      final message = completion.choices.first.message.content?.first.text?.trim();
      AppLogger.error('[OPENAI_SERVICE_DEBUG] Step 5: Extracted message from response');
      AppLogger.info('[OPENAI_DEBUG] Extracted message: $message');
      
      if (message != null && message.isNotEmpty) {
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
  ) {
    final personalityPrompt = _getPersonalityPrompt(personality, explicitContent);
    final baseContext = _buildBaseContext(trigger, session, user, environment);
    final contentGuidelines = explicitContent 
      ? 'Use colorful, explicit language and profanity when it fits the character. Adult language and edgy humor is encouraged'
      : 'Keep language family-friendly and appropriate for all ages';

    return '''
$personalityPrompt

Context:
$baseContext

Guidelines:
- Respond as the $personality character with FRESH, UNIQUE phrasing each time
- Keep message under 25 words
- Be specific about their current situation
- ${_getCreativityBooster()}
- Make fun observations or jokes about their location when mentioned
- Reference local terrain, landmarks, or city personality if relevant
- Comment on weather conditions when relevant (temperature, conditions, etc.)
- ${_getVariedInstructions()}
- $contentGuidelines
- Sound natural and conversational
- Focus on encouragement and motivation
- NEVER repeat phrases you've used before - be inventive and original
- NEVER use hashtags like #RuckLife #BeastMode - absolutely no # symbols allowed
- NEVER use social media language or internet slang
- Address the user by name: ${_extractFirstName(user['username']) ?? 'athlete'}

Generate a motivational message:''';
  }

  String _buildBaseContext(
    Map<String, dynamic> trigger,
    Map<String, dynamic> session,
    Map<String, dynamic> user,
    Map<String, dynamic> environment,
  ) {
    final triggerType = trigger['type'];
    final triggerData = trigger['data'] as Map<String, dynamic>;
    
    String contextText = "Rucking session: ${session['elapsedTime']['formatted']} elapsed, ${session['distance']['formatted']} covered.";
    
    switch (triggerType) {
      case 'milestone':
        final milestone = triggerData['milestone'];
        contextText += " Just hit ${milestone}km milestone!";
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
    
    if (location != null && location is Map<String, dynamic>) {
      final city = location['city'] as String?;
      final terrain = location['terrain'] as String?; 
      final landmark = location['landmark'] as String?;
      final weatherCondition = location['weatherCondition'] as String?;
      final temperature = location['temperature'] as int?;
      
      AppLogger.info('[OPENAI_DEBUG] Parsed - city: $city, terrain: $terrain, landmark: $landmark, weather: $weatherCondition, temp: $temperature');
      
      if (city != null && city != 'Unknown Location') {
        contextText += " Location: $city";
        if (terrain != null && terrain.isNotEmpty) contextText += " ($terrain terrain)";
        if (landmark != null && landmark.isNotEmpty) contextText += " near $landmark";
        
        // Add weather context
        if (temperature != null || weatherCondition != null) {
          contextText += " - Weather: ";
          if (temperature != null) contextText += "${temperature}°F";
          if (weatherCondition != null) {
            if (temperature != null) contextText += ", ";
            contextText += weatherCondition;
          }
        }
        
        contextText += ".";
      }
    }
    
    return contextText;
  }

  /// Log simple response if logger is available
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
}
