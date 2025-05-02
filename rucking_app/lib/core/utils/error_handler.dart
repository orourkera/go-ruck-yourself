import 'package:rucking_app/core/utils/app_logger.dart';

/// A utility class to handle errors and provide user-friendly messages
class ErrorHandler {
  /// Convert technical error messages to user-friendly messages
  static String getUserFriendlyMessage(dynamic error, [String? context]) {
    // Log the original error for debugging
    final String errorContext = context != null ? '[$context]' : '';
    AppLogger.error('$errorContext Error: $error');
    
    // Map specific error patterns to user-friendly messages
    if (error.toString().contains('permission')) {
      return 'Please allow location access to track your rucking sessions.';
    } else if (error.toString().contains('network') || 
               error.toString().contains('SocketException') ||
               error.toString().contains('connection')) {
      return 'Network connection issue. Please check your internet connection.';
    } else if (error.toString().contains('authentication') || 
               error.toString().contains('401') ||
               error.toString().contains('Unauthorized')) {
      return 'Session expired. Please log in again.';
    } else if (error.toString().contains('HealthKit') || 
               error.toString().contains('health')) {
      return 'Unable to access health data. Please check your health permissions.';
    }
    
    // General user-friendly message if no specific pattern is matched
    return 'Something went wrong. Please try again later.';
  }
}
