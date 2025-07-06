import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:get_it/get_it.dart';

/// Error severity levels for better categorization
enum ErrorSeverity {
  debug,
  info,
  warning,
  error,
  fatal,
}

/// Centralized error handling for ALL critical app operations
class AppErrorHandler {
  static final _apiClient = GetIt.instance<ApiClient>();
  
  /// Handle ANY app error with comprehensive logging and monitoring
  static Future<void> handleError(
    String operation,
    dynamic error, {
    Map<String, dynamic>? context,
    String? userId,
    bool sendToBackend = false,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    // Always log locally first
    final logMessage = '$operation failed: $error';
    switch (severity) {
      case ErrorSeverity.debug:
        AppLogger.debug(logMessage);
        break;
      case ErrorSeverity.info:
        AppLogger.info(logMessage);
        break;
      case ErrorSeverity.warning:
        AppLogger.warning(logMessage);
        break;
      case ErrorSeverity.error:
      case ErrorSeverity.fatal:
        AppLogger.error(logMessage);
        break;
    }
    
    // Send to Sentry with rich context
    try {
      await Sentry.captureException(
        error,
        stackTrace: StackTrace.current,
        withScope: (scope) {
          // Add operation context
          scope.setTag('operation_category', _getOperationCategory(operation));
          scope.setTag('operation_name', operation);
          
          // Add user context if available
          if (userId != null) {
            scope.setUser(SentryUser(id: userId));
          }
          
          // Add custom context as tags
          if (context != null) {
            for (final entry in context.entries) {
              scope.setTag('context_${entry.key}', entry.value.toString());
            }
          }
          
          // Add breadcrumb for debugging
          scope.addBreadcrumb(Breadcrumb(
            message: 'Supabase $operation attempted',
            category: 'supabase',
            level: SentryLevel.info,
            data: context ?? {},
          ));
        },
      );
    } catch (sentryError) {
      AppLogger.error('Failed to send error to Sentry: $sentryError');
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
  
  /// Get operation category for better Sentry organization
  static String _getOperationCategory(String operation) {
    // Categorize operations for better filtering in Sentry
    if (operation.contains('avatar') || operation.contains('photo')) {
      return 'media';
    } else if (operation.contains('session') || operation.contains('ruck')) {
      return 'fitness';
    } else if (operation.contains('auth') || operation.contains('login') || operation.contains('logout')) {
      return 'authentication';
    } else if (operation.contains('social') || operation.contains('like') || operation.contains('comment')) {
      return 'social';
    } else if (operation.contains('notification')) {
      return 'notifications';
    } else if (operation.contains('club') || operation.contains('buddy')) {
      return 'community';
    } else if (operation.contains('stats') || operation.contains('history')) {
      return 'analytics';
    } else if (operation.contains('api_') || operation.contains('network')) {
      return 'api';
    } else if (operation.contains('home') || operation.contains('ui')) {
      return 'user_interface';
    } else {
      return 'general';
    }
  }
  
  
  /// Quick error handling for critical operations (fatal severity)
  static Future<void> handleCriticalError(
    String operation,
    dynamic error, {
    Map<String, dynamic>? context,
    String? userId,
  }) async {
    await handleError(
      operation,
      error,
      context: context,
      userId: userId,
      severity: ErrorSeverity.fatal,
      sendToBackend: true,
    );
  }
  
  /// Quick error handling for warnings (non-fatal issues)
  static Future<void> handleWarning(
    String operation,
    dynamic error, {
    Map<String, dynamic>? context,
    String? userId,
  }) async {
    await handleError(
      operation,
      error,
      context: context,
      userId: userId,
      severity: ErrorSeverity.warning,
      sendToBackend: false, // Warnings don't need backend logging
    );
  }
}
