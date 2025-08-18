import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for generating speech audio using ElevenLabs API
class ElevenLabsService {
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';
  static const Duration _timeout = Duration(seconds: 15);
  
  // Voice ID mapping for each personality
  static const Map<String, String> _personalityVoices = {
    // Original personalities
    'Motivational Coach': 'EXAVITQu4vr4xnSDxMaL', // Bella - energetic female
    'Supportive Friend': 'AZnzlk1XvdvUeBnXmlld', // Domi - warm female
    'Drill Sergeant': 'VR6AewLTigWG4xSOukaG', // Josh - strong male
    'Zen Guide': 'pNInz6obpgDQGcFmaJgB', // Adam - calm male
    'Southern Redneck': 'yoZ06aMxZJJ28mfd3POQ', // Sam - character male
    'Dwarven Warrior': 'pqHfZKP75CvOlQylNhV4', // Arnold - deep male
    
    // New personalities
    'Pirate Captain': 'yoZ06aMxZJJ28mfd3POQ', // Sam - character male (gruff)
    'Yoga Instructor': 'AZnzlk1XvdvUeBnXmlld', // Domi - warm female (soothing)
    'British Butler': 'pNInz6obpgDQGcFmaJgB', // Adam - calm male (distinguished)
    'Surfer Dude': 'yoZ06aMxZJJ28mfd3POQ', // Sam - character male (laid-back)
    'Wise Grandmother': 'AZnzlk1XvdvUeBnXmlld', // Domi - warm female (nurturing)
    'Sports Commentator': 'VR6AewLTigWG4xSOukaG', // Josh - strong male (energetic)
    'Robot Assistant': 'pNInz6obpgDQGcFmaJgB', // Adam - calm male (neutral)
    'Medieval Knight': 'pqHfZKP75CvOlQylNhV4', // Arnold - deep male (noble)
    'Cowboy/Cowgirl': 'yoZ06aMxZJJ28mfd3POQ', // Sam - character male (rugged)
    'Scientist': 'pNInz6obpgDQGcFmaJgB', // Adam - calm male (articulate)
    'Stand-up Comedian': 'yoZ06aMxZJJ28mfd3POQ', // Sam - character male (expressive)
    'Ninja Master': 'pqHfZKP75CvOlQylNhV4', // Arnold - deep male (mysterious)
    'Chef': 'EXAVITQu4vr4xnSDxMaL', // Bella - energetic female (enthusiastic)
    'Flight Attendant': 'AZnzlk1XvdvUeBnXmlld', // Domi - warm female (professional)
    'Game Show Host': 'VR6AewLTigWG4xSOukaG', // Josh - strong male (dramatic)
  };
  
  final String _apiKey;

  ElevenLabsService(this._apiKey);

  /// Synthesizes text to speech audio using personality-specific voice
  Future<Uint8List?> synthesizeSpeech({
    required String text,
    required String personality,
  }) async {
    try {
      final voiceId = _getVoiceId(personality);
      if (voiceId == null) {
        AppLogger.error('[ELEVENLABS] No voice ID found for personality: $personality');
        return null;
      }

      AppLogger.info('[ELEVENLABS] Synthesizing speech for $personality: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');

      final url = '$_baseUrl/text-to-speech/$voiceId';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': _apiKey,
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_monolingual_v1',
          'voice_settings': {
            'stability': _getStabilityForPersonality(personality),
            'similarity_boost': _getSimilarityForPersonality(personality),
            'style': _getStyleForPersonality(personality),
            'use_speaker_boost': true,
          },
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        AppLogger.info('[ELEVENLABS] Successfully synthesized ${response.bodyBytes.length} bytes of audio');
        return response.bodyBytes;
      } else {
        AppLogger.error('[ELEVENLABS] API error: ${response.statusCode} - ${response.body}');
        return null;
      }

    } on TimeoutException {
      AppLogger.error('[ELEVENLABS] Request timed out');
      return null;
    } on SocketException {
      AppLogger.error('[ELEVENLABS] Network error - no internet connection');
      return null;
    } catch (e) {
      AppLogger.error('[ELEVENLABS] Failed to synthesize speech: $e');
      return null;
    }
  }

  /// Gets voice ID for personality, with fallback
  String? _getVoiceId(String personality) {
    return _personalityVoices[personality] ?? _personalityVoices['Supportive Friend'];
  }

  /// Gets stability setting based on personality (0.0 to 1.0)
  double _getStabilityForPersonality(String personality) {
    switch (personality) {
      case 'Drill Sergeant':
        return 0.8; // Very stable, authoritative
      case 'Zen Guide':
        return 0.9; // Extremely stable, calm
      case 'Motivational Coach':
        return 0.6; // Somewhat stable but energetic
      case 'Dwarven Warrior':
        return 0.7; // Stable but with character
      case 'Southern Redneck':
        return 0.5; // Less stable for character variation
      case 'Pirate Captain':
        return 0.6; // Moderate stability for character
      case 'Yoga Instructor':
        return 0.85; // Very stable, peaceful
      case 'British Butler':
        return 0.8; // High stability, proper
      case 'Surfer Dude':
        return 0.5; // Relaxed, variable
      case 'Wise Grandmother':
        return 0.8; // Stable, nurturing
      case 'Sports Commentator':
        return 0.4; // Dynamic, expressive
      case 'Robot Assistant':
        return 0.9; // Maximum stability, mechanical
      case 'Medieval Knight':
        return 0.75; // Noble, steady
      case 'Cowboy/Cowgirl':
        return 0.6; // Steady but rugged
      case 'Scientist':
        return 0.8; // Precise, controlled
      case 'Stand-up Comedian':
        return 0.3; // Highly variable for comedy
      case 'Ninja Master':
        return 0.8; // Controlled, disciplined
      case 'Chef':
        return 0.5; // Passionate, expressive
      case 'Flight Attendant':
        return 0.75; // Professional, clear
      case 'Game Show Host':
        return 0.4; // Dramatic, variable
      default:
        return 0.65; // Default balanced stability
    }
  }

  /// Gets similarity boost based on personality (0.0 to 1.0)
  double _getSimilarityForPersonality(String personality) {
    switch (personality) {
      case 'Drill Sergeant':
        return 0.8; // High similarity for consistency
      case 'Zen Guide':
        return 0.85; // Very high for smooth delivery
      case 'Dwarven Warrior':
        return 0.7; // Good similarity with character
      case 'Southern Redneck':
        return 0.6; // Lower for more variation
      case 'Pirate Captain':
        return 0.65; // Character variation
      case 'Yoga Instructor':
        return 0.85; // Smooth, consistent
      case 'British Butler':
        return 0.8; // Proper, consistent
      case 'Surfer Dude':
        return 0.6; // Relaxed variation
      case 'Wise Grandmother':
        return 0.8; // Warm consistency
      case 'Sports Commentator':
        return 0.7; // Clear but dynamic
      case 'Robot Assistant':
        return 0.9; // Maximum consistency
      case 'Medieval Knight':
        return 0.75; // Noble consistency
      case 'Cowboy/Cowgirl':
        return 0.65; // Rugged character
      case 'Scientist':
        return 0.8; // Precise delivery
      case 'Stand-up Comedian':
        return 0.5; // High variation for comedy
      case 'Ninja Master':
        return 0.75; // Controlled consistency
      case 'Chef':
        return 0.6; // Expressive variation
      case 'Flight Attendant':
        return 0.8; // Professional consistency
      case 'Game Show Host':
        return 0.65; // Dramatic but clear
      default:
        return 0.75; // Default good similarity
    }
  }

  /// Gets style setting based on personality (0.0 to 1.0)
  double _getStyleForPersonality(String personality) {
    switch (personality) {
      case 'Motivational Coach':
        return 0.6; // Energetic style
      case 'Drill Sergeant':
        return 0.8; // Strong, commanding style
      case 'Zen Guide':
        return 0.3; // Calm, minimal style
      case 'Dwarven Warrior':
        return 0.7; // Characterful style
      case 'Southern Redneck':
        return 0.8; // High character style
      case 'Pirate Captain':
        return 0.8; // Swashbuckling character
      case 'Yoga Instructor':
        return 0.2; // Peaceful, minimal
      case 'British Butler':
        return 0.4; // Refined, proper
      case 'Surfer Dude':
        return 0.6; // Laid-back character
      case 'Wise Grandmother':
        return 0.4; // Warm, gentle
      case 'Sports Commentator':
        return 0.9; // Maximum dramatic style
      case 'Robot Assistant':
        return 0.1; // Minimal, mechanical
      case 'Medieval Knight':
        return 0.6; // Noble, heroic
      case 'Cowboy/Cowgirl':
        return 0.7; // Western character
      case 'Scientist':
        return 0.3; // Analytical, precise
      case 'Stand-up Comedian':
        return 0.9; // Maximum expressive style
      case 'Ninja Master':
        return 0.5; // Mysterious, controlled
      case 'Chef':
        return 0.7; // Passionate, enthusiastic
      case 'Flight Attendant':
        return 0.4; // Professional, clear
      case 'Game Show Host':
        return 0.9; // Maximum theatrical style
      default:
        return 0.5; // Default balanced style
    }
  }

  /// Checks if API key is configured
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Gets available voices for testing
  Future<List<Map<String, dynamic>>?> getAvailableVoices() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/voices'),
        headers: {
          'xi-api-key': _apiKey,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['voices']);
      }
      return null;
    } catch (e) {
      AppLogger.error('[ELEVENLABS] Failed to get voices: $e');
      return null;
    }
  }

  /// Gets user's subscription info for usage monitoring
  Future<Map<String, dynamic>?> getSubscriptionInfo() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/subscription'),
        headers: {
          'xi-api-key': _apiKey,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      AppLogger.error('[ELEVENLABS] Failed to get subscription info: $e');
      return null;
    }
  }

  /// Validates API key by making a test request
  Future<bool> validateApiKey() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user'),
        headers: {
          'xi-api-key': _apiKey,
        },
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.error('[ELEVENLABS] API key validation failed: $e');
      return false;
    }
  }
}
