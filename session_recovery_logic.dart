/// Add this method to SessionLifecycleManager for session recovery

/// Check for and recover active session on app startup
Future<void> checkForCrashedSession() async {
  try {
    final sessionData = await _storageService.getObject('active_session_data');
    
    if (sessionData == null) {
      AppLogger.info('[RECOVERY] No crashed session data found');
      return;
    }

    final sessionId = sessionData['sessionId'] as String?;
    final startTimeStr = sessionData['startTime'] as String?;
    final isActive = sessionData['isActive'] as bool? ?? false;
    
    if (!isActive || sessionId == null || startTimeStr == null) {
      AppLogger.info('[RECOVERY] Session data incomplete or inactive');
      await _storageService.removeObject('active_session_data');
      return;
    }

    final startTime = DateTime.parse(startTimeStr);
    final crashDuration = DateTime.now().difference(startTime);
    
    // If session was started more than 6 hours ago, probably abandon it
    if (crashDuration.inHours > 6) {
      AppLogger.info('[RECOVERY] Session too old (${crashDuration.inHours}h), abandoning');
      await _storageService.removeObject('active_session_data');
      return;
    }

    AppLogger.warning('🔥 CRASH RECOVERY: Found active session from ${crashDuration.inMinutes} minutes ago');

    // Restore session state
    _activeSessionId = sessionId;
    _sessionStartTime = startTime;
    
    final ruckWeight = (sessionData['ruckWeightKg'] as num?)?.toDouble() ?? 0.0;
    final userWeight = (sessionData['userWeightKg'] as num?)?.toDouble() ?? 70.0;
    final lastDuration = Duration(milliseconds: sessionData['duration'] ?? 0);
    
    _updateState(SessionLifecycleState(
      isActive: true,
      sessionId: sessionId,
      startTime: startTime,
      duration: lastDuration,
      ruckWeightKg: ruckWeight,
      userWeightKg: userWeight,
      errorMessage: '🔄 Session recovered from unexpected app closure',
      isLoading: false,
      isSaving: false,
      currentSession: null, // Will be loaded separately
      totalPausedDuration: Duration.zero,
      pausedAt: null,
    ));

    // Restart timers
    _startTimer();
    _startSessionPersistenceTimer();
    _startSophisticatedTimerSystem();
    _startConnectivityMonitoring();

    AppLogger.info('✅ Session recovery complete: $sessionId');
    
  } catch (e) {
    AppLogger.error('[RECOVERY] Failed to recover crashed session: $e');
    await _storageService.removeObject('active_session_data');
  }
}

/// Clear the crash recovery data when session completes normally
Future<void> clearCrashRecoveryData() async {
  try {
    await _storageService.removeObject('active_session_data');
    AppLogger.debug('[RECOVERY] Cleared crash recovery data');
  } catch (e) {
    AppLogger.error('[RECOVERY] Failed to clear recovery data: $e');
  }
}
