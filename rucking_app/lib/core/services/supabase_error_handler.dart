import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/network/api_client.dart';
import 'package:get_it/get_it.dart';

/// Centralized error handling for all Supabase operations
class SupabaseErrorHandler {
  static final _apiClient = GetIt.instance<ApiClient>();
  
  /// Handle Supabase errors with comprehensive logging
  static Future<void> handleError(
    String operation,
    dynamic error, {
    Map<String, dynamic>? context,
    bool sendToBackend = false,
  }) async {
    // Always log locally first
    AppLogger.error('Supabase $operation failed: $error', context: context);
    
    // Send to Crashlytics for monitoring
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        null,
        fatal: false,
        information: [
          DiagnosticsProperty('supabase_operation', operation),
          DiagnosticsProperty('context', context?.toString() ?? 'none'),
          DiagnosticsProperty('timestamp', DateTime.now().toIso8601String()),
        ],
      );
    } catch (crashlyticsError) {
      AppLogger.error('Failed to send error to Crashlytics: $crashlyticsError');
    }
    
    // Optionally send to backend for Papertrail (for critical operations)
    if (sendToBackend) {
      try {
        await _sendToBackend(operation, error, context);
      } catch (backendError) {
        AppLogger.error('Failed to send error to backend: $backendError');
      }
    }
  }
  
  /// Send error to backend for Papertrail logging
  static Future<void> _sendToBackend(
    String operation,
    dynamic error,
    Map<String, dynamic>? context,
  ) async {
    try {
      await _apiClient.post('/errors/supabase', {
        'operation': operation,
        'error': error.toString(),
        'context': context ?? {},
        'timestamp': DateTime.now().toIso8601String(),
        'platform': 'flutter',
      });
    } catch (e) {
      // Don't throw - just log failure
      AppLogger.error('Backend error logging failed: $e');
    }
  }
}
