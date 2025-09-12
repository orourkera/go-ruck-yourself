import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing AI cheerleader audio with fallback to TTS
class AIAudioService {
  static const Duration _fadeOutDuration = Duration(milliseconds: 500);
  static const Duration _fadeInDuration = Duration(milliseconds: 500);

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  bool _isPlaying = false;

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

      _isInitialized = true;
      AppLogger.info('[AI_AUDIO] Service initialized');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Initialization failed: $e');
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
      // Prevent overlapping playbacks
      if (_isPlaying) {
        AppLogger.warning(
            '[AI_AUDIO] Playback in progress, stopping previous playback to avoid overlap');
        await stop();
      }
      _isPlaying = true;

      AppLogger.info(
          '[AI_AUDIO] Playing cheerleader audio (${audioBytes.length} bytes)');

      // If no audio bytes provided, skip playback (no TTS fallback)
      if (audioBytes.isEmpty) {
        AppLogger.info(
            '[AI_AUDIO] No audio bytes provided, skipping playback (TTS disabled)');
        return false;
      }

      // Try to play the synthesized audio first
      AppLogger.info('[AI_AUDIO] Attempting to play ElevenLabs audio...');
      final success = await _playAudioBytes(audioBytes);
      if (success) {
        AppLogger.info('[AI_AUDIO] ElevenLabs audio played successfully');
        return true;
      }

      AppLogger.warning(
          '[AI_AUDIO] ElevenLabs audio playback failed, no fallback (TTS disabled)');
      return false;
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Playback failed: $e');
      return false;
    } finally {
      _isPlaying = false;
    }
  }

  /// Play raw audio bytes through audio player
  Future<bool> _playAudioBytes(Uint8List audioBytes) async {
    try {
      // Create temporary file for audio playback
      final tempDir = await getTemporaryDirectory();
      final audioFile = File(
          '${tempDir.path}/ai_cheerleader_${DateTime.now().millisecondsSinceEpoch}.mp3');

      // Write audio bytes to temporary file
      await audioFile.writeAsBytes(audioBytes);

      // Set up completion listener BEFORE starting playback
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

      // Play the audio file AFTER setting up listeners
      await _audioPlayer.play(DeviceFileSource(audioFile.path));

      return await completer.future;
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Audio bytes playback failed: $e');
      return false;
    }
  }

  /// Check if audio service is ready
  bool get isReady => _isInitialized;

  /// Stop any currently playing audio
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      AppLogger.info('[AI_AUDIO] Playback stopped');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Stop failed: $e');
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      _isInitialized = false;
      AppLogger.info('[AI_AUDIO] Service disposed');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Dispose failed: $e');
    }
  }
}
