import 'package:audioplayers/audioplayers.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing voice messages during active rucks
class VoiceMessagePlayer {
  static final VoiceMessagePlayer _instance = VoiceMessagePlayer._internal();
  factory VoiceMessagePlayer() => _instance;
  VoiceMessagePlayer._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  /// Play a voice message from URL
  Future<void> playMessageAudio(String audioUrl) async {
    if (_isPlaying) {
      AppLogger.warning('[VOICE_MESSAGE] Already playing, skipping new message');
      return;
    }

    try {
      _isPlaying = true;
      AppLogger.info('[VOICE_MESSAGE] Playing audio from: $audioUrl');

      // Set volume to 100%
      await _player.setVolume(1.0);

      // Play the audio from URL
      await _player.play(UrlSource(audioUrl));

      // Wait for completion
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        AppLogger.info('[VOICE_MESSAGE] Audio playback completed');
      });

    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Failed to play audio: $e');
      _isPlaying = false;
    }
  }

  /// Stop current playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Error stopping playback: $e');
    }
  }

  /// Dispose player
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Error disposing player: $e');
    }
  }
}
