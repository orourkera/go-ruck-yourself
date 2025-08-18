import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing AI cheerleader audio with fallback to TTS
class AIAudioService {
  static const Duration _fadeOutDuration = Duration(milliseconds: 500);
  static const Duration _fadeInDuration = Duration(milliseconds: 500);
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  
  /// Initialize the audio service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Configure audio player
      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.assistanceNavigationGuidance,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      
      // Configure TTS as fallback
      await _configureTTS();
      
      _isInitialized = true;
      AppLogger.info('[AI_AUDIO] Service initialized');
      
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Initialization failed: $e');
    }
  }

  /// Configure TTS settings based on personality
  Future<void> _configureTTS() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5); // Slightly slower for clarity
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);
    
    // Set voice based on availability
    if (Platform.isIOS) {
      await _flutterTts.setVoice({'name': 'Samantha', 'locale': 'en-US'});
    } else if (Platform.isAndroid) {
      await _flutterTts.setVoice({'name': 'en-us-x-sfg#female_2-local', 'locale': 'en-US'});
    }
  }

  /// Play AI cheerleader audio with music ducking
  Future<bool> playCheerleaderAudio({
    required Uint8List audioBytes,
    required String fallbackText,
    String personality = 'Supportive Friend',
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      AppLogger.info('[AI_AUDIO] Playing cheerleader audio (${audioBytes.length} bytes)');
      
      // Try to play the synthesized audio first
      final success = await _playAudioBytes(audioBytes);
      if (success) {
        return true;
      }
      
      AppLogger.warning('[AI_AUDIO] Audio playback failed, falling back to TTS');
      return await _playFallbackTTS(fallbackText, personality);
      
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Playback failed: $e');
      // Final fallback to TTS
      return await _playFallbackTTS(fallbackText, personality);
    }
  }

  /// Play raw audio bytes through audio player
  Future<bool> _playAudioBytes(Uint8List audioBytes) async {
    try {
      // Create temporary file for audio playback
      final tempDir = await getTemporaryDirectory();
      final audioFile = File('${tempDir.path}/ai_cheerleader_${DateTime.now().millisecondsSinceEpoch}.mp3');
      
      // Write audio bytes to temporary file
      await audioFile.writeAsBytes(audioBytes);
      
      // Play the audio file
      await _audioPlayer.play(DeviceFileSource(audioFile.path));
      
      // Wait for playback to complete
      final completer = Completer<bool>();
      late StreamSubscription subscription;
      
      subscription = _audioPlayer.onPlayerComplete.listen((_) {
        subscription.cancel();
        // Clean up temporary file
        audioFile.deleteSync();
        completer.complete(true);
      });
      
      // Set timeout for playback
      Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          subscription.cancel();
          audioFile.deleteSync();
          completer.complete(false);
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Audio bytes playback failed: $e');
      return false;
    }
  }

  /// Fallback to device TTS
  Future<bool> _playFallbackTTS(String text, String personality) async {
    try {
      AppLogger.info('[AI_AUDIO] Using TTS fallback for: "$text"');
      
      // Adjust TTS settings based on personality
      await _adjustTTSForPersonality(personality);
      
      // Play the text
      await _flutterTts.speak(text);
      
      return true;
      
    } catch (e) {
      AppLogger.error('[AI_AUDIO] TTS fallback failed: $e');
      return false;
    }
  }

  /// Adjust TTS settings based on personality
  Future<void> _adjustTTSForPersonality(String personality) async {
    switch (personality) {
      case 'Cowboy/Cowgirl':
        await _flutterTts.setSpeechRate(0.45);
        await _flutterTts.setPitch(0.85);
        await _flutterTts.setVolume(0.9);
        break;
        
      case 'Stand-up Comedian':
        await _flutterTts.setSpeechRate(0.55);
        await _flutterTts.setPitch(1.05);
        await _flutterTts.setVolume(0.9);
        break;
        
      case 'Game Show Host':
        await _flutterTts.setSpeechRate(0.6);
        await _flutterTts.setPitch(1.1);
        await _flutterTts.setVolume(1.0);
        break;
        
      case 'Nature Lover':
        await _flutterTts.setSpeechRate(0.45);
        await _flutterTts.setPitch(1.1);
        await _flutterTts.setVolume(0.8);
        break;
        
      default:
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.setVolume(0.8);
        break;
    }
  }

  /// Check if audio service is ready
  bool get isReady => _isInitialized;

  /// Stop any currently playing audio
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      await _flutterTts.stop();
      AppLogger.info('[AI_AUDIO] Playback stopped');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Stop failed: $e');
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      await _flutterTts.stop();
      _isInitialized = false;
      AppLogger.info('[AI_AUDIO] Service disposed');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Dispose failed: $e');
    }
  }

  /// Test TTS functionality
  Future<void> testTTS(String text) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      await _flutterTts.speak(text);
      AppLogger.info('[AI_AUDIO] TTS test completed');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] TTS test failed: $e');
    }
  }
}
