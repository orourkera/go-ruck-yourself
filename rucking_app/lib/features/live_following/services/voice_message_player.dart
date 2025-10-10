import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:audioplayers/audioplayers.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service for playing voice messages during active rucks
class VoiceMessagePlayer {
  static final VoiceMessagePlayer _instance = VoiceMessagePlayer._internal();
  factory VoiceMessagePlayer() => _instance;
  VoiceMessagePlayer._internal() {
    _initializePlayer();
  }

  late AudioPlayer _player;

  void _initializePlayer() {
    _player = AudioPlayer();

    _completionSubscription = _player.onPlayerComplete.listen((_) {
      AppLogger.info('[VOICE_MESSAGE] Audio playback completed');
      _isPlaying = false;
      if (_queue.isEmpty) {
        unawaited(_deactivateAudioSession());
      }
      Future.microtask(() => _playNext());
    });

    // Add error listener for debugging
    _player.onPlayerStateChanged.listen((state) {
      AppLogger.info('[VOICE_MESSAGE] Player state changed: $state');
    });

    _player.onLog.listen((msg) {
      AppLogger.debug('[VOICE_MESSAGE][AudioPlayer] $msg');
    });

    _configureAudioPlayer();
  }
  final List<String> _queue = <String>[];
  StreamSubscription<void>? _completionSubscription;
  bool _isPlaying = false;
  audio_session.AudioSession? _audioSession;
  bool _audioSessionConfigured = false;

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
      await _deactivateAudioSession();
      return;
    }

    final nextUrl = _queue.removeAt(0);

    try {
      _isPlaying = true;
      AppLogger.info('[VOICE_MESSAGE] Playing audio from: $nextUrl');
      AppLogger.info('[VOICE_MESSAGE] Queue size: ${_queue.length} remaining');
      AppLogger.info('[VOICE_MESSAGE] Platform: ${Platform.operatingSystem}');

      // Ensure audio session is configured
      await _ensureAudioSession();

      // Android-specific: Add delay to ensure audio system is ready
      if (Platform.isAndroid) {
        AppLogger.info('[VOICE_MESSAGE] Android detected - adding initialization delay');
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Extra logging for Android debugging
      AppLogger.info('[VOICE_MESSAGE] Setting audio session active...');
      await _audioSession?.setActive(true);

      // Reset player before playing
      await _player.stop();
      await _player.release();

      AppLogger.info('[VOICE_MESSAGE] Setting volume to 1.0...');
      await _player.setVolume(1.0);

      // Set release mode to stop to ensure proper cleanup
      await _player.setReleaseMode(ReleaseMode.stop);

      // Try different source types for better compatibility
      AppLogger.info('[VOICE_MESSAGE] Creating UrlSource...');
      final source = UrlSource(nextUrl);

      AppLogger.info('[VOICE_MESSAGE] Starting playback...');
      await _player.play(source, mode: PlayerMode.mediaPlayer);
      AppLogger.info('[VOICE_MESSAGE] Playback started successfully');
    } catch (e, stackTrace) {
      AppLogger.error('[VOICE_MESSAGE] Failed to play audio: $e');
      AppLogger.error('[VOICE_MESSAGE] Stack trace: $stackTrace');
      AppLogger.error('[VOICE_MESSAGE] URL was: $nextUrl');

      _isPlaying = false;

      // Try alternative playback method for Android
      if (Platform.isAndroid && e.toString().contains('(-19)')) {
        AppLogger.info('[VOICE_MESSAGE] Attempting Android fallback playback');
        await _androidFallbackPlay(nextUrl);
      } else {
        await _deactivateAudioSession();
      }

      if (_queue.isNotEmpty) {
        AppLogger.info('[VOICE_MESSAGE] Retrying with next item in queue');
        await _playNext();
      }
    }
  }

  Future<void> _androidFallbackPlay(String url) async {
    try {
      AppLogger.info('[VOICE_MESSAGE] Android fallback: Recreating player');

      // Dispose old player
      await _player.dispose();
      await _completionSubscription?.cancel();

      // Create fresh player
      _initializePlayer();

      // Try to play with LOW_LATENCY mode
      await _player.setVolume(1.0);
      await _player.play(UrlSource(url), mode: PlayerMode.lowLatency);

      AppLogger.info('[VOICE_MESSAGE] Android fallback playback started');
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Android fallback also failed: $e');
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
      await _deactivateAudioSession();
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

  Future<void> _configureAudioPlayer() async {
    try {
      // Use media player mode for better Android compatibility
      await _player.setPlayerMode(PlayerMode.mediaPlayer);

      // Set audio context to ensure Android plays properly
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
    } catch (e) {
      AppLogger.warning('[VOICE_MESSAGE] Failed to configure audio player: $e');
    }
  }

  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured) return;

    try {
      _audioSession = await audio_session.AudioSession.instance;
      await _audioSession?.configure(audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker |
                audio_session.AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: audio_session.AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            audio_session.AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const audio_session.AndroidAudioAttributes(
          usage: audio_session.AndroidAudioUsage.media,
          contentType: audio_session.AndroidAudioContentType.speech,
          flags: audio_session.AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType:
            audio_session.AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      _audioSessionConfigured = true;
      AppLogger.info('[VOICE_MESSAGE] Audio session configured for playback');
    } catch (e) {
      AppLogger.error('[VOICE_MESSAGE] Failed to configure audio session: $e');
    }
  }

  Future<void> _deactivateAudioSession() async {
    if (!_audioSessionConfigured) return;
    try {
      await _audioSession?.setActive(false);
    } catch (e) {
      AppLogger.warning(
          '[VOICE_MESSAGE] Failed to deactivate audio session: $e');
    }
  }
}
