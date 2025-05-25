import 'package:flutter/foundation.dart';

/// A utility class for handling logging throughout the app
/// Automatically disables detailed logs in production builds
class AppLogger {
  static const String _debugPrefix = '[DEBUG]';
  static const String _infoPrefix = '[INFO]';
  static const String _warningPrefix = '[WARNING]';
  static const String _errorPrefix = '[ERROR]';

  /// Logs detailed debug messages only in debug mode
  /// These are more verbose than info messages and mainly used for development
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('$_debugPrefix $message');
    }
  }

  /// Logs information messages only in debug mode
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('$_infoPrefix $message');
    }
  }

  /// Logs warning messages only in debug mode
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('$_warningPrefix $message');
    }
  }

  /// Logs error messages
  static void error(String message, {dynamic exception, StackTrace? stackTrace}) {
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
    // Always log to console in both debug and release modes
    debugPrint('$_errorPrefix [CRITICAL] $message');
    
    if (exception != null) {
      debugPrint('$_errorPrefix [CRITICAL] Exception: $exception');
    }
    
    // Log stack trace for critical errors to help with debugging
    final trace = stackTrace ?? StackTrace.current;
    debugPrint('$_errorPrefix [CRITICAL] Stack trace: $trace');
  }
}
