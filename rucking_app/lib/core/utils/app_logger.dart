import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/utils/crashlytics_helper.dart';

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

  /// Logs error messages and reports to Crashlytics in release mode
  static void error(String message, {dynamic exception, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('$_errorPrefix $message');
    }
    
    // Always report errors to Crashlytics in release mode
    if (!kDebugMode) {
      CrashlyticsHelper.logError(message, error: exception, stackTrace: stackTrace);
    }
  }

  /// Logs critical errors even in release mode and always reports to Crashlytics
  /// Only use for critical issues that need immediate reporting
  static void critical(String message, {dynamic exception, StackTrace? stackTrace}) {
    // Always log to console in both debug and release modes
    debugPrint('$_errorPrefix [CRITICAL] $message');
    
    // Always report critical errors to Crashlytics
    CrashlyticsHelper.logError(
      message, 
      error: exception ?? 'CRITICAL: $message', 
      stackTrace: stackTrace ?? StackTrace.current,
      customKeys: {'severity': 'critical'},
    );
  }
}
