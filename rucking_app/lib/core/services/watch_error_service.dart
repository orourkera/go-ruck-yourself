import 'package:flutter/services.dart';
import 'package:rucking_app/core/services/app_error_handler.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Service to handle watch app error telemetry and forward to Sentry
class WatchErrorService {
  static const MethodChannel _channel = MethodChannel('com.getrucky.gfy/watch_errors');
  
  static bool _isInitialized = false;
  
  /// Initialize the watch error service
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    _channel.setMethodCallHandler(_handleWatchErrorCall);
    _isInitialized = true;
    
    AppLogger.info('WatchErrorService initialized - ready to receive watch errors');
  }
  
  /// Handle incoming method calls from iOS watch error forwarding
  static Future<void> _handleWatchErrorCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'reportWatchError':
          await _handleWatchError(call.arguments);
          break;
        case 'reportWatchMessage':
          await _handleWatchMessage(call.arguments);
          break;
        default:
          AppLogger.warning('Unknown watch error method: ${call.method}');
      }
    } catch (e) {
      AppLogger.error('Failed to handle watch error call: $e');
    }
  }
  
  /// Handle watch app errors and forward to Sentry
  static Future<void> _handleWatchError(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      
      final String operation = data['operation'] ?? 'unknown_watch_operation';
      final String errorMessage = data['error'] ?? 'Unknown watch error';
      final String severity = data['severity'] ?? 'error';
      final Map<String, dynamic> context = Map<String, dynamic>.from(data['context'] ?? {});
      
      AppLogger.info('Received watch error: $operation - $errorMessage');
      
      // Convert severity string to ErrorSeverity enum
      final ErrorSeverity errorSeverity = _parseErrorSeverity(severity);
      
      // Create a synthetic error for Sentry
      final WatchAppError watchError = WatchAppError(
        operation: operation,
        message: errorMessage,
        context: context,
      );
      
      // Forward to Sentry via AppErrorHandler
      await AppErrorHandler.handleError(
        'Watch_$operation',
        watchError,
        context: context,
        severity: errorSeverity,
      );
      
    } catch (e) {
      AppLogger.error('Failed to process watch error: $e');
    }
  }
  
  /// Handle watch app messages and forward to Sentry
  static Future<void> _handleWatchMessage(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      
      final String operation = data['operation'] ?? 'unknown_watch_operation';
      final String message = data['message'] ?? 'Unknown watch message';
      final String severity = data['severity'] ?? 'info';
      final Map<String, dynamic> context = Map<String, dynamic>.from(data['context'] ?? {});
      
      AppLogger.info('Received watch message: $operation - $message');
      
      // Convert severity string to ErrorSeverity enum
      final ErrorSeverity errorSeverity = _parseErrorSeverity(severity);
      
      // Create a synthetic error for Sentry (for messages, we use a generic error)
      final WatchAppMessage watchMessage = WatchAppMessage(
        operation: operation,
        message: message,
        context: context,
      );
      
      // Forward to Sentry via AppErrorHandler
      await AppErrorHandler.handleError(
        'WatchMessage_$operation',
        watchMessage,
        context: context,
        severity: errorSeverity,
      );
      
    } catch (e) {
      AppLogger.error('Failed to process watch message: $e');
    }
  }
  
  /// Parse severity string to ErrorSeverity enum
  static ErrorSeverity _parseErrorSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'debug':
        return ErrorSeverity.debug;
      case 'info':
        return ErrorSeverity.info;
      case 'warning':
        return ErrorSeverity.warning;
      case 'error':
        return ErrorSeverity.error;
      case 'fatal':
        return ErrorSeverity.fatal;
      default:
        return ErrorSeverity.error;
    }
  }
}

/// Custom error class for watch app errors
class WatchAppError implements Exception {
  final String operation;
  final String message;
  final Map<String, dynamic> context;
  
  const WatchAppError({
    required this.operation,
    required this.message,
    required this.context,
  });
  
  @override
  String toString() => 'WatchAppError($operation): $message';
}

/// Custom error class for watch app messages
class WatchAppMessage implements Exception {
  final String operation;
  final String message;
  final Map<String, dynamic> context;
  
  const WatchAppMessage({
    required this.operation,
    required this.message,
    required this.context,
  });
  
  @override
  String toString() => 'WatchAppMessage($operation): $message';
}
