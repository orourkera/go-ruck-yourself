import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class SimpleAILogger {
  final ApiClient _apiClient;

  SimpleAILogger(this._apiClient);

  /// Log AI cheerleader response - simple 3 column logging
  Future<void> logResponse({
    required String sessionId,
    required String personality,
    required String openaiResponse,
    bool isExplicit = false,
  }) async {
    AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] ===== logResponse method called =====');
    AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] sessionId: $sessionId (type: ${sessionId.runtimeType})');
    AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] personality: $personality');
    
    try {
      AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] Building logData object...');
      // Convert String sessionId to int for database
      int? sessionIdInt;
      try {
        sessionIdInt = int.parse(sessionId);
      } catch (e) {
        AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] Cannot convert sessionId to int: $sessionId - $e');
        return;
      }

      final logData = {
        'session_id': sessionIdInt,
        'personality': personality,
        'openai_response': openaiResponse,
        'is_explicit': isExplicit,
      };

      AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] About to call _apiClient.post to /ai-cheerleader/log');
      final response = await _apiClient.post(
        '/ai-cheerleader/log',
        logData,
      );
      AppLogger.error('[SIMPLE_AI_LOGGER_DEBUG] API call completed with status: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.info('[AI_LOG] Response logged successfully');
      } else {
        AppLogger.warning('[AI_LOG] Failed to log response: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('[AI_LOG] Error logging response: $e');
      // Don't throw - logging shouldn't break user experience
    }
  }
}
