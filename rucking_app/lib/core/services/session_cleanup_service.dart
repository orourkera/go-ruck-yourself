import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/active_session_storage.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Background service to periodically clean up stale session data
class SessionCleanupService {
  static const Duration _cleanupInterval = Duration(hours: 1);
  Timer? _cleanupTimer;
  final ActiveSessionStorage _activeSessionStorage;

  SessionCleanupService(this._activeSessionStorage);

  /// Start periodic cleanup
  void startPeriodicCleanup() {
    // Don't start multiple timers
    if (_cleanupTimer?.isActive == true) {
      AppLogger.info('[CLEANUP_SERVICE] Cleanup timer already active');
      return;
    }

    AppLogger.info('[CLEANUP_SERVICE] Starting periodic session cleanup (every ${_cleanupInterval.inHours} hours)');

    _cleanupTimer = Timer.periodic(_cleanupInterval, (timer) async {
      await _performCleanup();
    });

    // Also run cleanup immediately on startup
    _performCleanup();
  }

  /// Stop periodic cleanup
  void stopPeriodicCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    AppLogger.info('[CLEANUP_SERVICE] Stopped periodic session cleanup');
  }

  /// Perform cleanup of stale session data
  Future<void> _performCleanup() async {
    try {
      AppLogger.info('[CLEANUP_SERVICE] Starting cleanup check...');

      final lastSave = await _activeSessionStorage.getLastSaveTime();
      if (lastSave == null) {
        AppLogger.info('[CLEANUP_SERVICE] No session data to clean up');
        return;
      }

      final timeSinceLastSave = DateTime.now().difference(lastSave);
      AppLogger.info('[CLEANUP_SERVICE] Last save was ${timeSinceLastSave.inHours} hours ago');

      // Clean up if older than 12 hours
      if (timeSinceLastSave.inHours >= 12) {
        AppLogger.info('[CLEANUP_SERVICE] Cleaning up stale session data (${timeSinceLastSave.inHours} hours old)');
        await _activeSessionStorage.clearSessionData();
        AppLogger.info('[CLEANUP_SERVICE] Stale session data cleaned up successfully');
      } else {
        AppLogger.info('[CLEANUP_SERVICE] Session data is recent (${timeSinceLastSave.inHours} hours) - no cleanup needed');
      }
    } catch (e) {
      AppLogger.error('[CLEANUP_SERVICE] Error during cleanup: $e');
    }
  }

  /// Force cleanup now (for manual triggers)
  Future<void> forceCleanup() async {
    AppLogger.info('[CLEANUP_SERVICE] Force cleanup requested');
    await _performCleanup();
  }

  /// Check if cleanup service is running
  bool get isRunning => _cleanupTimer?.isActive == true;
}
