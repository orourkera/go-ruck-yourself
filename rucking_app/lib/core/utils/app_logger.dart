import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// A utility class for handling logging throughout the app
/// Automatically disables detailed logs in production builds
class AppLogger {
  static const String _debugPrefix = '[DEBUG]';

  // Controls whether verbose debug/info logs should be printed. Defaults to false unless
  // a compile–time dart-define named `VERBOSE_LOGS` is supplied.
  // Usage when running/debugging the app:
  // flutter run --dart-define=VERBOSE_LOGS=true
  // In CI/release builds omit the flag to keep logs quiet.
  static const bool _verboseLogs = bool.fromEnvironment('VERBOSE_LOGS', defaultValue: false);
  static const String _infoPrefix = '[INFO]';
  static const String _warningPrefix = '[WARNING]';
  static const String _errorPrefix = '[ERROR]';

  /// Logs detailed debug messages only in debug mode
  /// These are more verbose than info messages and mainly used for development
  static void debug(String message) {
    if (_shouldSuppress(message)) return;
    if (kDebugMode && (_verboseLogs || _isAiDebug(message))) {
      debugPrint('$_debugPrefix $message');
    }
  }

  /// Logs information messages only in debug mode
  static void info(String message) {
    if (_shouldSuppress(message)) return;
    if (kDebugMode && (_verboseLogs || _isAiDebug(message))) {
      debugPrint('$_infoPrefix $message');
    }
  }

  /// Logs warning messages only in debug mode
  static void warning(String message) {
    if (_shouldSuppress(message)) return;
    if (kDebugMode && (_verboseLogs || _isAiDebug(message))) {
      debugPrint('$_warningPrefix $message');
    }
  }

  /// Logs error messages
  static void error(String message, {dynamic exception, StackTrace? stackTrace}) {
    if (_shouldSuppress(message)) return;
    // In both debug and release mode, we log to console
    debugPrint('$_errorPrefix $message');
    if (exception != null) {
      debugPrint('$_errorPrefix Exception: $exception');
    }
    if (stackTrace != null) {
      debugPrint('$_errorPrefix Stack trace: $stackTrace');
    }
  }

  /// Logs critical errors even in release mode
  /// Only use for critical issues that need immediate reporting
  static void critical(String message, {dynamic exception, StackTrace? stackTrace}) {
    // critical logs are always printed even if verbose logs disabled, unless suppressed
    if (_shouldSuppress(message)) return;
    // Always log to console in both debug and release modes
    debugPrint('$_errorPrefix [CRITICAL] $message');
    
    if (exception != null) {
      debugPrint('$_errorPrefix [CRITICAL] Exception: $exception');
    }
    
    // Log stack trace for critical errors to help with debugging
    final trace = stackTrace ?? StackTrace.current;
    debugPrint('$_errorPrefix [CRITICAL] Stack trace: $trace');
    
    // Send critical errors to Firebase Crashlytics for production tracking
    try {
      FirebaseCrashlytics.instance.log('[CRITICAL] $message');
      if (exception != null) {
        FirebaseCrashlytics.instance.recordError(
          exception,
          trace,
          fatal: false,
          information: [
            DiagnosticsProperty<String>('critical_message', message),
            DiagnosticsProperty<String>('app_state', 'critical_error'),
          ],
        );
      } else {
        // Log as a non-fatal error with context
        FirebaseCrashlytics.instance.recordError(
          message,
          trace,
          fatal: false,
          information: [
            DiagnosticsProperty<String>('critical_log', message),
            DiagnosticsProperty<String>('log_type', 'critical'),
          ],
        );
      }
    } catch (e) {
      debugPrint('$_errorPrefix Failed to send critical log to Crashlytics: $e');
    }
  }

  /// Logs session completion flow steps to Crashlytics for debugging hangs
  /// This helps track where session completion gets stuck
  static void sessionCompletion(String step, {Map<String, dynamic>? context}) {
    if (_shouldSuppress(step)) return;
    final message = '[SESSION_COMPLETION] $step';
    debugPrint('$_infoPrefix $message');
    
    // Send to Crashlytics with context for production debugging
    try {
      FirebaseCrashlytics.instance.log(message);
      
      // Set custom keys for this session completion attempt
      if (context != null) {
        context.forEach((key, value) {
          FirebaseCrashlytics.instance.setCustomKey(key, value.toString());
        });
      }
      
      // Add timestamp for tracking completion flow timing
      FirebaseCrashlytics.instance.setCustomKey('session_completion_step', step);
      FirebaseCrashlytics.instance.setCustomKey('session_completion_time', DateTime.now().toIso8601String());
      
    } catch (e) {
      debugPrint('$_errorPrefix Failed to send session completion log to Crashlytics: $e');
    }
  }

  /// Logs session timeout/hang issues with detailed context
  static void sessionTimeout(String message, {
    String? sessionId,
    int? duration,
    String? lastStep,
    Map<String, dynamic>? networkInfo,
  }) {
    if (_shouldSuppress(message)) return;
    final fullMessage = '[SESSION_TIMEOUT] $message';
    debugPrint('$_errorPrefix $fullMessage');
    
    // Send timeout issue to Crashlytics with full context
    try {
      FirebaseCrashlytics.instance.log(fullMessage);
      
      // Add detailed context about the timeout
      if (sessionId != null) {
        FirebaseCrashlytics.instance.setCustomKey('timeout_session_id', sessionId);
      }
      if (duration != null) {
        FirebaseCrashlytics.instance.setCustomKey('timeout_duration_seconds', duration);
      }
      if (lastStep != null) {
        FirebaseCrashlytics.instance.setCustomKey('timeout_last_step', lastStep);
      }
      if (networkInfo != null) {
        networkInfo.forEach((key, value) {
          FirebaseCrashlytics.instance.setCustomKey('timeout_$key', value.toString());
        });
      }
      
      FirebaseCrashlytics.instance.setCustomKey('timeout_timestamp', DateTime.now().toIso8601String());
      
      // Record as a non-fatal error
      FirebaseCrashlytics.instance.recordError(
        'Session completion timeout: $message',
        StackTrace.current,
        fatal: false,
        information: [
          DiagnosticsProperty<String>('timeout_type', 'session_completion'),
          DiagnosticsProperty<String>('session_id', sessionId ?? 'unknown'),
        ],
      );
      
    } catch (e) {
      debugPrint('$_errorPrefix Failed to send timeout log to Crashlytics: $e');
    }
  }

  /// Determine if the provided message is considered too noisy and should be suppressed.
  /// Filters out high-frequency coordinate/location messages unless verbose logs enabled.
  static bool _shouldSuppress(String message) {
    if (_verboseLogs) return false; // developer explicitly asked for logs
    if (_isAiDebug(message)) return false; // never suppress explicit AI debug logs

    final lower = message.toLowerCase();
    if (lower.startsWith('location update:') ||
        (lower.contains('latitude') && lower.contains('longitude'))) {
      return true;
    }
    return false;
  }

  /// Whitelist AI debug messages so they show up in Debug builds without requiring VERBOSE_LOGS
  static bool _isAiDebug(String message) {
    // Allow a set of diagnostic tags to bypass verbose gating in debug builds
    // This ensures important dev diagnostics are visible without --dart-define=VERBOSE_LOGS
    const tags = <String>[
      '[AI_DEBUG]',
      '[AI_CHEERLEADER_DEBUG]',
      '[AI_INSIGHTS]',
      '[AI_INSIGHTS_WIDGET]',
      '[OPENAI_SSE]',
      '[HR_CHART]',
      '[HR_DEBUG]',
      '[PACE DEBUG]',
      '[PACE SMOOTH]',
      '[STEPS DEBUG]',
      '[STEPS LIVE]',
      '[STEPS UI]',
    ];
    for (final t in tags) {
      if (message.contains(t)) return true;
    }
    return false;
  }
}
