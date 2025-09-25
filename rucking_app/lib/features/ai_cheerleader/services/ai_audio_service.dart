import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:path_provider/path_provider.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing AI cheerleader audio with fallback to TTS
class AIAudioService {
  static const Duration _fadeOutDuration = Duration(milliseconds: 500);
  static const Duration _fadeInDuration = Duration(milliseconds: 500);

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  bool _isPlaying = false;
  audio_session.AudioSession? _session;

  /// Initialize the audio service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get audio session instance
      _session = await audio_session.AudioSession.instance;

      // Configure for speech with ducking that properly restores
      await _session!.configure(audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.duckOthers |
                                       audio_session.AVAudioSessionCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        avAudioSessionMode: audio_session.AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy: audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: audio_session.AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.speech,
          usage: audio_session.AndroidAudioUsage.assistanceNavigationGuidance,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      // Configure audio player without AudioContext (let audio_session handle it)
      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

      _isInitialized = true;
      AppLogger.info('[AI_AUDIO] Service initialized with audio_session for proper ducking');
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
    File? audioFile; // Track file for cleanup in finally/catch blocks
    try {
      // Activate session for ducking BEFORE playing
      await _session?.setActive(true);
      AppLogger.info('[AI_AUDIO] Audio session activated for ducking');

      // Create temporary file for audio playback
      final tempDir = await getTemporaryDirectory();
      audioFile = File(
          '${tempDir.path}/ai_cheerleader_${DateTime.now().millisecondsSinceEpoch}.mp3');

      // Write audio bytes to temporary file
      await audioFile.writeAsBytes(audioBytes);

      // Set up completion listener BEFORE starting playback
      final completer = Completer<bool>();
      late StreamSubscription subscription;

      subscription = _audioPlayer.onPlayerComplete.listen((_) async {
        subscription.cancel();

        // CRITICAL: Deactivate session to restore other audio volume
        await _session?.setActive(false);
        AppLogger.info('[AI_AUDIO] Audio session deactivated - music volume restored');

        // Clean up temporary file
        try {
          audioFile?.deleteSync();
        } catch (_) {
          // Silent fail on delete - file might already be gone
        }
        completer.complete(true);
      });

      // Set timeout for playback
      Timer(const Duration(seconds: 30), () async {
        if (!completer.isCompleted) {
          subscription.cancel();

          // Deactivate on timeout too
          await _session?.setActive(false);
          AppLogger.info('[AI_AUDIO] Audio session deactivated on timeout');

          try {
            audioFile?.deleteSync();
          } catch (_) {
            // Silent fail on delete
          }
          completer.complete(false);
        }
      });

      // Play the audio file AFTER setting up listeners
      await _audioPlayer.play(DeviceFileSource(audioFile.path));

      return await completer.future;
    } catch (e) {
      // Deactivate session on error
      await _session?.setActive(false);
      AppLogger.info('[AI_AUDIO] Audio session deactivated on error');

      // CRITICAL: Clean up temp file on ANY error to prevent memory leaks
      if (audioFile != null && audioFile.existsSync()) {
        try {
          audioFile.deleteSync();
          AppLogger.info('[AI_AUDIO] Cleaned up temp file after error');
        } catch (deleteError) {
          AppLogger.warning('[AI_AUDIO] Failed to delete temp file: $deleteError');
        }
      }
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
      // Deactivate session when stopping to restore other audio
      await _session?.setActive(false);
      AppLogger.info('[AI_AUDIO] Playback stopped and session deactivated');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Stop failed: $e');
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    try {
      // Stop any currently playing audio
      await _audioPlayer.stop();

      // Deactivate session to ensure other audio is restored
      await _session?.setActive(false);

      // Clean up any remaining temp files from crashed/interrupted sessions
      try {
        final tempDir = await getTemporaryDirectory();
        final files = tempDir.listSync();
        for (var file in files) {
          if (file is File && file.path.contains('ai_cheerleader_')) {
            try {
              file.deleteSync();
              AppLogger.info('[AI_AUDIO] Cleaned up orphaned temp file: ${file.path}');
            } catch (_) {
              // Silent fail - file might be in use or already deleted
            }
          }
        }
      } catch (cleanupError) {
        AppLogger.warning('[AI_AUDIO] Temp file cleanup failed: $cleanupError');
      }

      await _audioPlayer.dispose();
      _isInitialized = false;
      _isPlaying = false;
      AppLogger.info('[AI_AUDIO] Service disposed and session deactivated');
    } catch (e) {
      AppLogger.error('[AI_AUDIO] Dispose failed: $e');
    }
  }
}
