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
  }) async {
    try {
      final logData = {
        'session_id': sessionId,
        'personality': personality,
        'openai_response': openaiResponse,
      };

      final response = await _apiClient.post(
        '/ai-cheerleader/log',
        data: logData,
      );

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
