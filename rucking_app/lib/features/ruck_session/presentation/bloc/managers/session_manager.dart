import 'dart:async';
import '../events/session_events.dart';
import '../models/manager_states.dart';

/// Base interface for all session managers
abstract class SessionManager {
  /// Stream of manager-specific state changes
  Stream<SessionManagerState> get stateStream;

  /// Current state of the manager
  SessionManagerState get currentState;

  /// Handle an event that might be relevant to this manager
  Future<void> handleEvent(ActiveSessionEvent event);

  /// Clean up resources when the manager is disposed
  Future<void> dispose();

  /// Check for and recover active session on app startup
  Future<void> checkForCrashedSession();

  /// Clear crash recovery data when session completes normally
  Future<void> clearCrashRecoveryData();
}
