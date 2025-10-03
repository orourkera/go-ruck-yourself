import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class AiObservabilityService {
  AiObservabilityService(this._apiClient);

  final ApiClient _apiClient;

  Future<void> logLLMCall({
    required String contextType,
    required String model,
    required List<Map<String, String>> messages,
    required String response,
    required double latencyMs,
    Map<String, dynamic>? metadata,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    double? temperature,
    int? maxTokens,
    String? sessionId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'context_type': contextType,
        'model': model,
        'messages': _sanitizeMessages(messages),
        'response': _truncate(response, 4000),
        'latency_ms': latencyMs,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (completionTokens != null) 'completion_tokens': completionTokens,
        if (totalTokens != null) 'total_tokens': totalTokens,
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (sessionId != null) 'session_id': sessionId,
      };

      await _apiClient.post('/observability/llm', payload);
    } catch (err, stack) {
      AppLogger.warning('[AI_OBSERVABILITY] Failed to log LLM call: $err',
          stackTrace: stack);
    }
  }

  List<Map<String, String>> _sanitizeMessages(
      List<Map<String, String>> rawMessages) {
    return rawMessages
        .where((msg) => msg.containsKey('role'))
        .map((msg) => {
              'role': msg['role'] ?? 'user',
              'content': _truncate(msg['content'] ?? '', 2000),
            })
        .toList(growable: false);
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}
