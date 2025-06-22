import 'dart:async';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service responsible for triggering backend duel completion checks
class DuelCompletionService {
  final ApiClient _apiClient;
  Timer? _completionCheckTimer;
  bool _isStarted = false;
  
  DuelCompletionService(this._apiClient);

  /// Start periodic checking for duel completion (every 2 minutes)
  void startCompletionChecking() {
    if (_isStarted) return; // Prevent multiple starts
    
    _completionCheckTimer?.cancel();
    _completionCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _triggerBackendCompletionCheck(),
    );
    _isStarted = true;
    AppLogger.info('Duel completion checking started');
  }

  /// Stop periodic checking
  void stopCompletionChecking() {
    _completionCheckTimer?.cancel();
    _completionCheckTimer = null;
    _isStarted = false;
    AppLogger.info('Duel completion checking stopped');
  }

  /// Trigger backend to check for completed duels
  Future<void> _triggerBackendCompletionCheck() async {
    try {
      final response = await _apiClient.post('/duels/completion-check', {});
      
      final completedCount = response['completed_duels']?.length ?? 0;
      if (completedCount > 0) {
        AppLogger.info('Backend completed $completedCount expired duels');
      }
    } catch (e) {
      AppLogger.warning('Failed to trigger duel completion check: $e');
      // Don't log as error since this is background and non-critical
    }
  }

  /// Manually trigger completion check (for immediate completion after progress update)
  Future<void> checkDuelCompletion(String duelId) async {
    AppLogger.info('Manually triggering duel completion check for duel $duelId');
    await _triggerBackendCompletionCheck();
  }

  void dispose() {
    stopCompletionChecking();
  }
}
