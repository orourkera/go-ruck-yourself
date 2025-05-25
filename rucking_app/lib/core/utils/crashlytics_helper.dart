import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Helper class to log errors and exceptions to Firebase Crashlytics
class CrashlyticsHelper {
  /// Log a non-fatal error with a custom message and optional stack trace
  static Future<void> logError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? customKeys,
  }) async {
    // Set any custom keys that might help with debugging
    if (customKeys != null) {
      for (final entry in customKeys.entries) {
        FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value.toString());
      }
    }

    // Record the error with Crashlytics
    await FirebaseCrashlytics.instance.recordError(
      error ?? message,
      stackTrace,
      reason: message,
      fatal: false,
    );
  }

  /// Log a fatal crash with a custom message
  static Future<void> logFatalError(
    String message, {
    required dynamic error,
    required StackTrace stackTrace,
    Map<String, dynamic>? customKeys,
  }) async {
    // Set any custom keys that might help with debugging
    if (customKeys != null) {
      for (final entry in customKeys.entries) {
        FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value.toString());
      }
    }

    // Record the error with Crashlytics
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: message,
      fatal: true,
    );
  }

  /// Set user identifier to associate logs with a specific user
  static Future<void> setUserIdentifier(String userId) async {
    await FirebaseCrashlytics.instance.setUserIdentifier(userId);
  }

  /// Log a custom message without reporting it as an error or exception
  static Future<void> log(String message) async {
    await FirebaseCrashlytics.instance.log(message);
  }
}
