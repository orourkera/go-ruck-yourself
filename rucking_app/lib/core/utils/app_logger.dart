import 'package:flutter/foundation.dart';

/// A utility class for handling logging throughout the app
/// Automatically disables detailed logs in production builds
class AppLogger {
  static const String _infoPrefix = '[INFO]';
  static const String _warningPrefix = '[WARNING]';
  static const String _errorPrefix = '[ERROR]';

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

  /// Logs error messages only in debug mode
  static void error(String message) {
    if (kDebugMode) {
      debugPrint('$_errorPrefix $message');
    }
  }

  /// Logs critical errors even in release mode
  /// Only use for critical issues that need reporting
  static void critical(String message) {
    // This could be integrated with a crash reporting service later
    debugPrint('$_errorPrefix [CRITICAL] $message');
  }
}
