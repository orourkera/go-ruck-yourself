import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing voice messages during active rucks
class VoiceMessagePlayer {
  static final VoiceMessagePlayer _instance = VoiceMessagePlayer._internal();
  factory VoiceMessagePlayer() => _instance;
  VoiceMessagePlayer._internal() {
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      AppLogger.info('[VOICE_MESSAGE] Audio playback completed');
      _isPlaying = false;
      Future.microtask(() => _playNext());
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final List<String> _queue = <String>[];
  StreamSubscription<void>? _completionSubscription;
  bool _isPlaying = false;

  /// Queue a voice message for playback. Messages play sequentially in arrival order.
  Future<void> playMessageAudio(String audioUrl) async {
    if (audioUrl.isEmpty) {
      AppLogger.warning('[VOICE_MESSAGE] Ignoring empty audio URL');
      return;
    }

    _queue.add(audioUrl);
    AppLogger.info('[VOICE_MESSAGE] Queued audio (${_queue.length} in queue)');

    if (_isPlaying) {
      AppLogger.debug(
          '[VOICE_MESSAGE] Playback in progress, will play queued audio next');
      return;
    }

    await _playNext();
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      return;
    }

    final nextUrl = _queue.removeAt(0);

    try {
      _isPlaying = true;
      AppLogger.info('[VOICE_MESSAGE] Playing audio from: $nextUrl');

      await _player.setVolume(1.0);
      await _player.play(UrlSource(nextUrl));
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Failed to play audio: $e');
      _isPlaying = false;

      if (_queue.isNotEmpty) {
        await _playNext();
      }
    }
  }

  /// Stop current playback and clear queued messages.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Error stopping playback: $e');
    } finally {
      _queue.clear();
      _isPlaying = false;
    }
  }

  /// Dispose player resources.
  Future<void> dispose() async {
    try {
      await _completionSubscription?.cancel();
      await _player.dispose();
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Error disposing player: $e');
    }
  }
}
