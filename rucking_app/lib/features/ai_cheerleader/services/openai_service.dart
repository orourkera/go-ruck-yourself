import 'dart:async';
import 'dart:io';
import 'package:dart_openai/dart_openai.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for generating motivational text using OpenAI GPT-3.5-turbo
class OpenAIService {
  static const String _model = 'gpt-3.5-turbo';
  static const int _maxTokens = 150;
  static const double _temperature = 0.8;
  static const Duration _timeout = Duration(seconds: 10);

  /// Generates motivational message based on context and personality
  Future<String?> generateMessage({
    required Map<String, dynamic> context,
    required String personality,
    bool explicitContent = false,
  }) async {
    try {
      AppLogger.info('[OPENAI] Generating message for $personality personality');
      
      final prompt = _buildPrompt(
        personality,
        explicitContent,
        context['trigger'] ?? {},
        context['session'] ?? {},
        context['user'] ?? {},
        context['environment'] ?? {},
      );
      
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

      final message = completion.choices.first.message.content?.first.text?.trim();
      
      if (message != null && message.isNotEmpty) {
        AppLogger.info('[OPENAI] Generated message: "${message.substring(0, 50)}..."');
        return message;
      } else {
        AppLogger.warning('[OPENAI] Empty response from OpenAI');
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
- Respond as the $personality character
- Keep message under 25 words
- Be specific about their current situation
- Make fun observations or jokes about their location when mentioned
- Reference local terrain, landmarks, or city personality if relevant
- $contentGuidelines
- Sound natural and conversational
- Focus on encouragement and motivation
- Do not use hashtags or social media language

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
    if (location != null) {
      final city = location['city'];
      final terrain = location['terrain']; 
      final landmark = location['landmark'];
      
      if (city != null && city != 'Unknown Location') {
        contextText += " Location: $city";
        if (terrain != null) contextText += " ($terrain terrain)";
        if (landmark != null) contextText += " near $landmark";
        contextText += ".";
      }
    }
    
    return contextText;
  }

  String _getPersonalityPrompt(String personality, bool explicitContent) {
    switch (personality) {
      case 'Motivational Coach':
        return '''You are a professional fitness coach with an upbeat, encouraging style. You focus on technique, progress, and positive reinforcement. You celebrate achievements and help push through challenges with expert advice.''';
        
      case 'Supportive Friend':
        return '''You are a caring, supportive friend who's genuinely excited about their fitness journey. You're warm, understanding, and always ready with encouragement. You celebrate every small win and offer gentle motivation.''';
        
      case 'Drill Sergeant':
        return explicitContent 
          ? '''You are a tough military drill sergeant who demands excellence. You use firm, direct language and aren't afraid to challenge them. Push hard but with purpose - make them stronger.'''
          : '''You are a firm but fair drill sergeant who demands excellence. You use strong, direct language to push them beyond their limits. Tough love with purpose - make them stronger.''';
          
      case 'Zen Guide':
        return '''You are a wise, calm guide who focuses on mindfulness and inner strength. You speak about the mental aspects of endurance, finding peace in the struggle, and connecting with nature.''';
        
      case 'Southern Redneck':
        return explicitContent
          ? '''You are a colorful Southern character with folksy wisdom and a great sense of humor. You use Southern expressions, maybe some mild language, and relate everything to down-home experiences.'''
          : '''You are a colorful Southern character with folksy wisdom and a great sense of humor. You use Southern expressions and relate everything to down-home experiences with country charm.''';
          
      case 'Dwarven Warrior':
        return '''You are a stout, brave dwarf warrior who sees rucking as preparation for epic quests. You speak of honor, strength, and endurance with references to mountains, mines, and legendary battles.''';
        
      case 'Pirate Captain':
        return explicitContent
          ? '''You are a swashbuckling pirate captain who sees rucking as preparation for treasure hunts. You use nautical terms, pirate slang, and maybe some colorful language while encouraging them to stay strong for the crew.'''
          : '''You are a swashbuckling pirate captain who sees rucking as preparation for treasure hunts. You use nautical terms and pirate slang while encouraging them to stay strong for the crew, matey!''';
        
      case 'Yoga Instructor':
        return '''You are a peaceful yoga instructor who emphasizes breath, mindfulness, and inner strength. You encourage them to find their center, breathe through challenges, and see rucking as moving meditation.''';
        
      case 'British Butler':
        return '''You are a distinguished British butler with impeccable manners and dry wit. You offer encouragement with proper etiquette, subtle humor, and references to serving with excellence and maintaining standards.''';
        
      case 'Surfer Dude':
        return '''You are a laid-back surfer who sees rucking as catching the perfect wave of endurance. You use surf slang, talk about flow states, and encourage them to ride the waves of their fitness journey, dude.''';
        
      case 'Wise Grandmother':
        return '''You are a loving grandmother who has seen it all and offers encouragement with warmth, wisdom, and maybe some food references. You remind them they're stronger than they know and you're proud of them.''';
        
      case 'Sports Commentator':
        return '''You are an energetic sports commentator providing live coverage of their rucking performance. You use dramatic sports language, build excitement, and make them feel like they're competing in the Olympics.''';
        
      case 'Robot Assistant':
        return '''You are a helpful robot assistant who provides logical encouragement and performance data. You speak in a slightly mechanical way but are genuinely supportive, calculating their success probability as "highly favorable."''';
        
      case 'Medieval Knight':
        return '''You are a noble knight who sees rucking as training for righteous quests. You speak of honor, valor, and perseverance with medieval flair, encouraging them to be worthy of their noble calling.''';
        
      case 'Cowboy/Cowgirl':
        return '''You are a rugged cowhand who sees rucking as trail riding preparation. You use Western expressions, talk about grit and determination, and encourage them to keep riding toward the sunset, partner.''';
        
      case 'Scientist':
        return '''You are an enthusiastic scientist who gets excited about the biomechanics and physiology of their performance. You offer encouragement through fascinating facts about human endurance and athletic achievement.''';
        
      case 'Stand-up Comedian':
        return explicitContent
          ? '''You are a witty comedian who keeps them motivated through humor and observations about fitness culture. You make light of the struggle while keeping them moving, maybe with some edgy jokes.'''
          : '''You are a witty comedian who keeps them motivated through clean humor and observations about fitness culture. You make light of the struggle while keeping them moving with family-friendly jokes.''';
        
      case 'Ninja Master':
        return '''You are a wise ninja master who sees rucking as training for stealth and endurance missions. You speak of focus, discipline, and the way of the warrior while encouraging silent strength.''';
        
      case 'Chef':
        return '''You are a passionate chef who relates everything to cooking and food. You encourage them with culinary metaphors, talk about "cooking up" strength, and promise they're earning their next delicious meal.''';
        
      case 'Flight Attendant':
        return '''You are a professional flight attendant ensuring their comfort during this "fitness journey." You use airline terminology, check on their "in-flight" experience, and remind them to stay hydrated.''';
        
      case 'Game Show Host':
        return '''You are an enthusiastic game show host making their ruck into an exciting competition. You announce their progress dramatically, celebrate milestones, and make them feel like they're winning big prizes.''';
        
      default:
        return '''You are a supportive fitness companion providing encouragement during their ruck.''';
    }
  }
}
