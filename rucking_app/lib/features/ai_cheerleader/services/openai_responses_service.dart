import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rucking_app/core/utils/app_logger.dart';

/// Minimal SSE client for OpenAI Responses API streaming (o3 models, etc.).
class OpenAIResponsesService {
  final String apiKey;
  final String baseUrl;

  OpenAIResponsesService({required this.apiKey, this.baseUrl = 'https://api.openai.com/v1'});

  /// Streams a response from the Responses API.
  /// Calls [onDelta] with incremental text, and [onComplete] with the full text once completed.
  Future<void> stream({
    required String model,
    required String input,
    double? temperature,
    int? maxOutputTokens,
    void Function(String delta)? onDelta,
    required void Function(String full) onComplete,
    void Function(Object error)? onError,
  }) async {
    final uri = Uri.parse('$baseUrl/responses');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    final body = <String, dynamic>{
      'model': model,
      'input': input,
      'stream': true,
    };
    final isO3 = model.toLowerCase().startsWith('o3');
    // Reasoning models (o3*) do not accept temperature; omit it
    if (!isO3 && temperature != null) body['temperature'] = temperature;
    if (maxOutputTokens != null) body['max_output_tokens'] = maxOutputTokens;

    AppLogger.info('[OPENAI_SSE] Starting stream to $uri with model=$model');
    final req = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    StringBuffer full = StringBuffer();
    try {
      final resp = await http.Client().send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = await resp.stream.bytesToString();
        throw Exception('OpenAI SSE error ${resp.statusCode}: $text');
      }

      // Parse SSE lines
      await resp.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .forEach((line) {
        if (line.isEmpty) return; // SSE chunk separator
        if (!line.startsWith('data:')) return;
        final dataStr = line.substring(5).trim();
        if (dataStr == '[DONE]') {
          // End of stream
          return;
        }
        try {
          final map = jsonDecode(dataStr) as Map<String, dynamic>;
          final type = map['type']?.toString() ?? '';
          // Typical events we care about:
          // - response.output_text.delta  -> { type, delta, response: {...} }
          // - response.completed         -> { type, response: {...} }
          if (type.contains('response.output_text.delta')) {
            final delta = (map['delta'] ?? '').toString();
            if (delta.isNotEmpty) {
              full.write(delta);
              if (onDelta != null) onDelta(delta);
            }
          } else if (type.contains('response.delta') || type.contains('response.output_item.added')) {
            // Some responses stream text via item/content instead of output_text.delta
            String acc = '';
            void collect(dynamic node) {
              if (node is Map<String, dynamic>) {
                node.forEach((k, v) {
                  if (k == 'text' && v is String) {
                    acc += v;
                  } else {
                    collect(v);
                  }
                });
              } else if (node is List) {
                for (final e in node) collect(e);
              }
            }
            collect(map);
            if (acc.isNotEmpty) {
              full.write(acc);
              if (onDelta != null) onDelta(acc);
            }
          } else if (type.contains('response.completed')) {
            // Completed signal; onComplete below after forEach finishes
          } else {
            // Other events can be ignored; log sparingly
            AppLogger.debug('[OPENAI_SSE] Event: $type');
          }
        } catch (e) {
          // Tolerate non-JSON control lines
          AppLogger.debug('[OPENAI_SSE] Non-JSON line: $dataStr');
        }
      });

      final out = full.toString();
      AppLogger.info('[OPENAI_SSE] Completed stream; bytes=${out.length}');
      onComplete(out);
    } catch (e) {
      AppLogger.error('[OPENAI_SSE] Stream error: $e');
      if (onError != null) onError(e);
    }
  }
}
