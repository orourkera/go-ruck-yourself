import 'dart:async';
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
  
  // Simple rate limiting for Sentry to prevent quota exhaustion
  static DateTime? _lastSentryError;
  static int _sentryErrorCount = 0;
  static const int _maxSentryErrorsPerHour = 50;
  static const Duration _sentryRateLimitWindow = Duration(hours: 1);
  
  /// Handle ANY app error with comprehensive logging and monitoring
  static Future<void> handleError(
    String operation,
    dynamic error, {
    Map<String, dynamic>? context,
    String? userId,
    bool sendToBackend = false,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    // Skip reporting timeout errors from analytics services to prevent cascading failures
    if (error is TimeoutException && 
        (error.toString().contains('app-analytics-services') || 
         error.toString().contains('sdk-exp') ||
         error.toString().contains('analytics'))) {
      AppLogger.warning('Analytics service timeout ignored: $error');
      return;
    }
    
    // Skip reporting iOS location permission denials as they're user choice, not app errors
    if (error.toString().contains('kCLErrorDomain error 1') ||
        error.toString().contains('Location permission required')) {
      AppLogger.info('Location permission denied - not reporting as error: $error');
      return;
    }
    
    // Skip reporting 403/Forbidden errors as they're expected authorization failures, not bugs
    if (error.toString().contains('403') ||
        error.toString().contains('Forbidden') ||
        error.toString().contains('forbidden')) {
      AppLogger.info('Authorization error (403) - not reporting to Sentry: $error');
      return;
    }
    
    // Skip reporting offline mode transitions as they're normal app behavior, not errors
    if (error.toString().contains('offline mode') ||
        error.toString().contains('No network connection')) {
      AppLogger.info('Offline mode transition - not reporting as error: $error');
      return;
    }
    
    // Handle GPU memory issues more gracefully
    if (error.toString().contains('loss of GPU access') ||
        error.toString().contains('Image upload failed due to loss of GPU access')) {
      AppLogger.warning('GPU memory issue detected - reducing image processing load: $error');
      // Still report these as they indicate memory pressure, but with lower severity
      severity = ErrorSeverity.warning;
    }
    
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
    
    // Check Sentry rate limiting before sending
    final now = DateTime.now();
    if (_lastSentryError == null || now.difference(_lastSentryError!) > _sentryRateLimitWindow) {
      // Reset counter after time window
      _sentryErrorCount = 0;
      _lastSentryError = now;
    }
    
    if (_sentryErrorCount >= _maxSentryErrorsPerHour) {
      AppLogger.warning('Sentry rate limit reached ($_maxSentryErrorsPerHour errors/hour) - skipping error report for: $operation');
      return;
    }
    
    // Send to Sentry with appropriate level based on severity
    try {
      _sentryErrorCount++; // Increment counter before sending
      // Only send exceptions for error/fatal levels, use messages for warnings/info/debug
      if (severity == ErrorSeverity.error || severity == ErrorSeverity.fatal) {
        await Sentry.captureException(
          error,
          stackTrace: StackTrace.current,
          withScope: (scope) {
            // Add operation context
            scope.setTag('operation_category', _getOperationCategory(operation));
            scope.setTag('operation_name', operation);
            scope.setTag('severity', severity.toString());
            
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
      } else {
        // Send warnings/info/debug as messages, not exceptions
        final sentryLevel = switch (severity) {
          ErrorSeverity.debug => SentryLevel.debug,
          ErrorSeverity.info => SentryLevel.info,
          ErrorSeverity.warning => SentryLevel.warning,
          ErrorSeverity.error => SentryLevel.error, // Shouldn't reach here
          ErrorSeverity.fatal => SentryLevel.fatal, // Shouldn't reach here
        };
        
        await Sentry.captureMessage(
          logMessage,
          level: sentryLevel,
          withScope: (scope) {
            // Add operation context
            scope.setTag('operation_category', _getOperationCategory(operation));
            scope.setTag('operation_name', operation);
            scope.setTag('severity', severity.toString());
            
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
      }
    } catch (sentryError) {
      // Handle Sentry rate limiting and API errors gracefully
      final errorString = sentryError.toString();
      if (errorString.contains('rate') || errorString.contains('limit') || errorString.contains('429') || errorString.contains('quota')) {
        AppLogger.warning('Sentry rate limit reached - error reporting temporarily disabled: $sentryError');
      } else if (errorString.contains('ApiException') || errorString.contains('network')) {
        AppLogger.warning('Sentry network error - error reporting failed: $sentryError');
      } else {
        AppLogger.error('Failed to send error to Sentry: $sentryError');
      }
      
      // Don't propagate Sentry errors - they're secondary issues
      // The original error is already logged locally above
    }
    
    // Backend error reporting disabled - endpoint not available
    // TODO: Re-enable when backend has /errors/supabase endpoint
    if (sendToBackend) {
      AppLogger.debug('Backend error reporting disabled (endpoint not available)');
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
